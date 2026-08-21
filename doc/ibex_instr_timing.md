# Ibex Instruction-Interface: Timing-Diagramme

## Signale an `ibex_top`

```
ibex_top (Master)          Speicher (Slave)
     instr_req_o   ──────►
     instr_addr_o  ──────►
     instr_gnt_i   ◄──────
     instr_rvalid_i◄──────
     instr_rdata_i ◄──────
     instr_err_i   ◄──────
```

**Protokollregeln**
- `instr_addr_o` muss stabil bleiben, solange `req_o=1` und `gnt_i=0`.
- `gnt_i=1` zeigt an, dass der Slave die Adresse übernommen hat; `req_o` darf danach wechseln.
- `rvalid_i` kommt N Zyklen nach dem `gnt_i`, unabhängig vom aktuellen `req_o`.

---

## Modus 1: Prefetch Buffer (`ICache=0`)

Jede Instruktion erzeugt einen separaten Speicherzugriff.
Maximal 2 gleichzeitig ausstehende Requests (`NUM_REQS = 2`).

### 1a – Sequentieller Fetch, kein Wait-State

```
Zyklus     │  1  │  2  │  3  │  4  │  5  │  6  │
───────────┼─────┼─────┼─────┼─────┼─────┼─────┤
req_o      │  1  │  1  │  1  │  1  │  1  │  1  │
addr_o     │ A+0 │ A+4 │ A+8 │A+12 │A+16 │A+20 │
gnt_i      │  1  │  1  │  1  │  1  │  1  │  1  │
rvalid_i   │  0  │  1  │  1  │  1  │  1  │  1  │
rdata_i    │  –  │D@A+0│D@A+4│D@A+8│D@A12│D@A16│
```

Der Prefetch Buffer füllt beide Outstanding-Slots sofort → ununterbrochener Datenstrom.

### 1b – Fetch mit Wait-States (Speicher nicht sofort bereit)

```
Zyklus     │  1  │  2  │  3  │  4  │  5  │  6  │
───────────┼─────┼─────┼─────┼─────┼─────┼─────┤
req_o      │  1  │  1  │  1  │  1  │  1  │  1  │
addr_o     │ A+0 │ A+0 │ A+4 │ A+4 │ A+8 │ A+8 │
gnt_i      │  0  │  1  │  0  │  1  │  0  │  1  │
rvalid_i   │  0  │  0  │  1  │  0  │  1  │  0  │
rdata_i    │  –  │  –  │D@A+0│  –  │D@A+4│  –  │
```

`addr_o` bleibt stabil bis `gnt_i=1`. `rvalid_i` erscheint 1 Zyklus nach `gnt_i`.

### 1c – Branch

```
Zyklus     │  1  │  2  │  3  │  4  │  5  │  6  │
───────────┼─────┼─────┼─────┼─────┼─────┼─────┤
req_o      │  1  │  1  │  1  │  1  │  1  │  1  │
addr_o     │ A+4 │ A+8 │ B+0 │ B+4 │ B+8 │B+12 │
gnt_i      │  1  │  1  │  1  │  1  │  1  │  1  │
rvalid_i   │  1  │  1  │  0  │  1  │  1  │  1  │
rdata_i    │D@A+4│D@A+8│  –  │D@B+0│D@B+4│D@B+8│
branch_i   │  0  │  1  │  0  │  0  │  0  │  0  │
addr_i     │  –  │ B+0 │  –  │  –  │  –  │  –  │
```

Branch in Zyklus 2: Das FIFO wird geleert. Das `rvalid` für A+8 (Zyklus 3) trifft
noch ein, wird aber intern verworfen (`branch_discard_q`).

---

## Modus 2: ICache (`ICache=1`)

**Cache-Parameter:**
- Cache-Line = 64 Bit = 2 × 32-Bit-Words (`IC_LINE_BEATS = 2`)
- 2 Ways, 4 Fill-Buffer (`NUM_FB = 4`)
- Throttle bei mehr als 2 aktiven Fill-Buffern (`FB_THRESHOLD = NUM_FB - 2 = 2`)

### 2a – Cache Hit (warmer Cache)

Bei einem Treffer läuft **kein externer Zugriff**. Die Daten kommen aus dem internen
SRAM über die zweistufige IC0→IC1-Pipeline (1 Zyklus Latenz).

```
Zyklus     │  1  │  2  │  3  │  4  │  5  │
───────────┼─────┼─────┼─────┼─────┼─────┤
req_o      │  0  │  0  │  0  │  0  │  0  │  ← kein externer Zugriff
addr_o     │  –  │  –  │  –  │  –  │  –  │
gnt_i      │  –  │  –  │  –  │  –  │  –  │
rvalid_i   │  0  │  0  │  0  │  0  │  0  │
rdata_i    │  –  │  –  │  –  │  –  │  –  │
```

### 2b – Cache Miss (2 Beats zur Füllung einer Cache-Line)

Adresse A → Cache-Line-Base L = `{A[31:3], 3'b000}`

```
Zyklus     │  1  │  2  │  3  │  4  │  5  │  6  │
───────────┼─────┼─────┼─────┼─────┼─────┼─────┤
req_o      │  1  │  1  │  0  │  0  │  0  │  0  │
addr_o     │  L  │ L+4 │  –  │  –  │  –  │  –  │
gnt_i      │  1  │  1  │  –  │  –  │  –  │  –  │
rvalid_i   │  0  │  0  │  1  │  1  │  0  │  0  │
rdata_i    │  –  │  –  │Beat0│Beat1│  –  │  –  │
```

Nach Empfang beider Beats: Cache-Line wird ins SRAM geschrieben.
Folgende Zugriffe auf dieselbe Line sind Hits (→ Fall 2a).

### 2c – Zwei aufeinanderfolgende Misses

```
Zyklus     │  1  │  2  │  3  │  4  │  5  │  6  │  7  │  8  │
───────────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┼─────┤
req_o      │  1  │  1  │  1  │  1  │  0  │  0  │  0  │  0  │
addr_o     │ L0  │L0+4 │ L1  │L1+4 │  –  │  –  │  –  │  –  │
gnt_i      │  1  │  1  │  1  │  1  │  –  │  –  │  –  │  –  │
rvalid_i   │  0  │  0  │  0  │  0  │  1  │  1  │  1  │  1  │
rdata_i    │  –  │  –  │  –  │  –  │B0L0 │B1L0 │B0L1 │B1L1 │
```

Der ICache nutzt 2 Fill-Buffer gleichzeitig. Throttling setzt ein, sobald
mehr als 2 Fill-Buffer aktiv sind.

---

## Modus-Vergleich

| Eigenschaft              | Prefetch Buffer | ICache Hit | ICache Miss |
|--------------------------|-----------------|------------|-------------|
| Externer Zugriff         | immer           | **nie**    | ja          |
| Beats pro Zugriff        | 1               | –          | 2           |
| Adress-Alignment extern  | 4-Byte (Word)   | –          | 8-Byte (Line) |
| Outstanding-Tiefe        | 2 Requests      | –          | 4 Fill-Buffer × 2 Beats |
| Branch-Strafe extern     | sofortiger Reset | –         | neuer Miss-Fetch für Ziellinie |
| Warm-up nötig            | nein            | –          | ja          |

---

## Wishbone B4 Registered-Feedback-Burst am `ibex_wb_host_adapter`

Der Adapter (`ibex_wb_host_adapter`) setzt das CTI/BTE-Protokoll um:

| `wb_cti_o` | Bedeutung           | Einsatz                     |
|------------|---------------------|-----------------------------|
| `3'b000`   | Classic Cycle       | Einzelner Beat (`req_len=1`) |
| `3'b010`   | Incrementing Burst  | Multi-Beat (`req_len>1`)     |
| `3'b111`   | End of Burst        | nicht genutzt (wb_ram-Kompatibilität) |

`wb_bte_o` ist immer `2'b00` (Linear Burst).

### WB Classic Cycle – Einzelner Beat (`req_len=1`, CTI=000)

```
Zyklus     │  1  │  2  │  3  │  4  │
───────────┼─────┼─────┼─────┼─────┤
wb_cyc     │  1  │  1  │  0  │  0  │
wb_stb     │  1  │  1  │  0  │  0  │
wb_cti     │ 000 │ 000 │  –  │  –  │
wb_bte     │ 00  │ 00  │  –  │  –  │
wb_adr     │  A  │  A  │  –  │  –  │
wb_ack     │  0  │  1  │  0  │  0  │
wb_dat_r   │  –  │  D  │  –  │  –  │
```

`wb_ram` erzeugt genau einen Ack-Puls pro Classic-Cycle
(`ack = valid & !prev_ack`).

### WB Incrementing Burst – 2 Beats (`req_len=2`, CTI=010)

```
Zyklus     │  1  │  2  │  3  │  4  │  5  │
───────────┼─────┼─────┼─────┼─────┼─────┤
wb_cyc     │  1  │  1  │  1  │  0  │  0  │
wb_stb     │  1  │  1  │  1  │  0  │  0  │
wb_cti     │ 010 │ 010 │ 010 │  –  │  –  │
wb_bte     │ 00  │ 00  │ 00  │  –  │  –  │
wb_adr     │  L  │  L  │ L+4 │  –  │  –  │
wb_ack     │  0  │  1  │  1  │  0  │  0  │
wb_dat_r   │  –  │Beat0│Beat1│  –  │  –  │
```

`wb_ram` erzeugt `ack = valid` bei CTI=010 (jeden Zyklus solange STB=1).
Nach dem letzten Ack deassertiert der Adapter STB/CYC.

> **ICache-Betrieb:** `ibex_wb.sv` setzt `instr_req_len = ICache ? 2 : 1`.
> Bei `ICache=1` wird damit automatisch der 2-Beat-Burst für jeden
> Cache-Line-Fill genutzt.
