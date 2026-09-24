#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <argp.h>
#include <fcntl.h>
#include <unistd.h>
#include <gelf.h>
#include <elf-loader.h>
#include "verilator_tb_utils.h"
#include "jtagServer.h"

#define VCD_DEFAULT_NAME "../sim.vcd"

VerilatorTbUtils::VerilatorTbUtils(uint32_t *mem, uint32_t memBase, size_t memWords)
  : mem(mem), memBase(memBase), memWords(memWords), t(0), timeout(0), vcdDump(false), vcdDumpStart(0), vcdDumpStop(0),
    vcdFileName((char *)VCD_DEFAULT_NAME), vcdDumping(false), jtagEnable(false),
    lastClk(0), jtagPort(5555) {
  tfp = new VerilatedVcdC;
  jtag = new VerilatorJtagServer(10); /* Jtag clock is 10 period */

  Verilated::traceEverOn(true);
  printf("Tracing on\n");
}

VerilatorTbUtils::~VerilatorTbUtils() {
    if (vcdDumping)
      tfp->close();
}

bool VerilatorTbUtils::doJTAG(uint8_t *tms, uint8_t *tdi, uint8_t *tck, uint8_t tdo) {
  if (jtagEnable)
    jtag->doJTAG(t, tms, tdi, tck, tdo);
  return true;
}

bool VerilatorTbUtils::doCycle() {
  if (vcdDumpStop && t >= vcdDumpStop) {
    if (vcdDumping) {
      printf("VCD dump stopped (%lu)\n", t);
      tfp->close();
    }
    vcdDumping = false;
  } else if (vcdDump && t >= vcdDumpStart) {
    if (!vcdDumping) {
      printf("VCD dump started (%lu)\n", t);
      tfp->open(vcdFileName);
    }
    vcdDumping = true;
  }

  if (vcdDumping)
    tfp->dump((vluint64_t)t);

  if(timeout && t >= timeout) {
    printf("Timeout reached\n");
    return false;
  }

  if (Verilated::gotFinish()) {
    printf("Caught $finish()\n");
    return false;
  }

  t++;
  return true;
}

bool VerilatorTbUtils::clkPosEdge(uint8_t clk) {
  bool isEdge = lastClk == 0 && clk == 1;
  lastClk = clk;
  return isEdge;
}

/* Load the PT_LOAD segments of an ELF file into mem. Segment addresses are
 * bus addresses and are translated relative to memBase, so the RAM does not
 * have to be mapped at address 0. */
bool VerilatorTbUtils::loadElf(char *fileName) {
  printf("Loading %s\n", fileName);

  if (elf_version(EV_CURRENT) == EV_NONE)
    return false;

  int fd = open(fileName, O_RDONLY, 0);
  if (fd < 0) {
    printf("Can't open %s\n", fileName);
    return false;
  }

  Elf *elf = elf_begin(fd, ELF_C_READ, NULL);
  size_t phdrNum;
  bool ok = elf && elf_kind(elf) == ELF_K_ELF && !elf_getphdrnum(elf, &phdrNum);
  if (!ok)
    printf("Error loading elf file\n");

  for (size_t i = 0; ok && i < phdrNum; i++) {
    GElf_Phdr phdr;
    if (gelf_getphdr(elf, i, &phdr) != &phdr) {
      ok = false;
      break;
    }
    if (phdr.p_type != PT_LOAD || phdr.p_memsz == 0)
      continue;

    printf("Program header %lu: addr 0x%08X, size 0x%08X\n", i,
           (unsigned int)phdr.p_paddr, (unsigned int)phdr.p_filesz);

    uint64_t end = phdr.p_paddr + phdr.p_memsz;
    if (phdr.p_paddr < memBase || (phdr.p_paddr & 3) ||
        (memWords && end > memBase + (uint64_t)memWords * 4)) {
      printf("Segment 0x%08X-0x%08X outside memory 0x%08X-0x%08X\n",
             (unsigned int)phdr.p_paddr, (unsigned int)end, memBase,
             (unsigned int)(memBase + memWords * 4));
      ok = false;
      break;
    }

    /* Copy file contents, zero-fill the rest (.bss) */
    uint8_t *seg = (uint8_t *)calloc(1, (phdr.p_memsz + 3) & ~3ULL);
    if (phdr.p_filesz) {
      Elf_Data *data = elf_getdata_rawchunk(elf, phdr.p_offset, phdr.p_filesz, ELF_T_BYTE);
      if (data == NULL) {
        printf("Couldn't load program data chunk\n");
        free(seg);
        ok = false;
        break;
      }
      memcpy(seg, data->d_buf, data->d_size);
    }

    uint32_t *dst = this->mem + (phdr.p_paddr - memBase) / 4;
    for (uint64_t off = 0; off < phdr.p_memsz; off += 4)
      dst[off / 4] = seg[off] | (seg[off + 1] << 8) | (seg[off + 2] << 16) |
                     ((uint32_t)seg[off + 3] << 24);  /* RISC-V: little endian */
    free(seg);
  }

  if (elf)
    elf_end(elf);
  close(fd);

  return ok;
}

bool VerilatorTbUtils::loadBin(char *fileName) {
  uint8_t *bin_data;
  int size;
  FILE *bin_file = fopen(fileName, "rb");

  printf("Loading %s\n", fileName);

  if (bin_file == NULL) {
    printf("Error opening bin file\n");
    return false;
  }
  fseek(bin_file, 0, SEEK_END);
  size = ftell(bin_file);
  rewind(bin_file);
  bin_data = (uint8_t *)malloc(size);
  if (fread(bin_data, 1, size, bin_file) != size) {
    printf("Error reading bin file\n");
    return false;
  }

  for (int i=0; i < size; i+=4)
    this->mem[i/4] = read_32(bin_data, i);

  free(bin_data);

  return true;
}

#define OPT_TIMEOUT 512
#define OPT_ELFLOAD 513
#define OPT_BINLOAD 514

static struct argp_option options[] = {
  { 0, 0, 0, 0, "Simulation control:", 1 },
  { "timeout", OPT_TIMEOUT, "VAL", 0, "Stop the sim at VAL" },
  { "elf_load", OPT_ELFLOAD, "FILE", 0, "Load program from ELF FILE" },
  { "bin_load", OPT_BINLOAD, "FILE", 0, "Load program from binary FILE" },
  { 0, 0, 0, 0, "VCD generation:", 2 },
  { "vcd", 'v', "FILE", OPTION_ARG_OPTIONAL, "Enable and save VCD to FILE" },
  { "vcdstart", 's', "VAL", 0, "Delay VCD generation until VAL" },
  { "vcdstop", 't', "VAL", 0, "Terminate VCD generation at VAL" },
  { 0, 0, 0, 0, "Remote debugging:", 3 },
  { "jtag_server", 'j', "PORT", OPTION_ARG_OPTIONAL, "Enable openocd JTAG server, opt. specify PORT" },
  { 0 },
};

struct argp verilator_tb_utils_argp = {options, VerilatorTbUtils::parseOpts,
                                       0, 0};

void VerilatorTbUtils::parsePlusArgs() {
  const char *p;

  p = Verilated::commandArgsPlusMatch("elf_load=");
  if (p[0]) loadElf(const_cast<char*>(p + strlen("+elf_load=")));

  p = Verilated::commandArgsPlusMatch("bin_load=");
  if (p[0]) loadBin(const_cast<char*>(p + strlen("+bin_load=")));

  p = Verilated::commandArgsPlusMatch("timeout=");
  if (p[0]) timeout = strtol(p + strlen("+timeout="), NULL, 10);

  p = Verilated::commandArgsPlusMatch("vcd=");
  if (p[0]) {
    vcdDump = true;
    vcdFileName = strdup(p + strlen("+vcd="));
  }

  p = Verilated::commandArgsPlusMatch("vcdstart=");
  if (p[0]) vcdDumpStart = strtol(p + strlen("+vcdstart="), NULL, 10);

  p = Verilated::commandArgsPlusMatch("vcdstop=");
  if (p[0]) vcdDumpStop = strtol(p + strlen("+vcdstop="), NULL, 10);

  p = Verilated::commandArgsPlusMatch("jtag_server=");
  if (p[0]) {
    jtagEnable = true;
    jtagPort = atoi(p + strlen("+jtag_server="));
    jtag->init_jtag_server(jtagPort);
  }
}

int VerilatorTbUtils::parseOpts(int key, char *arg, struct argp_state *state) {
  VerilatorTbUtils *tbUtils = static_cast<VerilatorTbUtils *>(state->input);

  switch (key) {
  case OPT_TIMEOUT:
    tbUtils->timeout = strtol(arg, NULL, 10);
    break;

  case OPT_ELFLOAD:
    tbUtils->loadElf(arg);
    break;

  case OPT_BINLOAD:
    tbUtils->loadBin(arg);
    break;

  case 'v':
    tbUtils->vcdDump = true;
    if (arg)
      tbUtils->vcdFileName = arg;
    break;

  case 's':
    tbUtils->vcdDumpStart = strtol(arg, NULL, 10);
    break;

  case 't':
    tbUtils->vcdDumpStop = strtol(arg, NULL, 10);
    break;

  case 'j':
      tbUtils->jtagEnable = true;
      if (arg)
        tbUtils->jtagPort = atoi(arg);
      tbUtils->jtag->init_jtag_server(tbUtils->jtagPort);
    break;

  default:
    return ARGP_ERR_UNKNOWN;
  }

  return 0;
}
