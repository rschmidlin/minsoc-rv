import sys
import re

def convert_bytebin_to_word(input_file, output_file):
    memory = {}

    current_addr = 0

    with open(input_file) as f:
        for line in f:
            line = line.strip()

            if not line:
                continue

            # Address marker
            if line.startswith('@'):
                current_addr = int(line[1:], 16)
                continue

            # Split multiple byte values on line
            bytes_list = line.split()

            for b in bytes_list:
                memory[current_addr] = int(b, 16)
                current_addr += 1

    # Pack bytes into 32-bit little-endian words
    words = {}

    for addr, byte in memory.items():
        word_addr = addr // 4
        byte_offset = addr % 4

        if word_addr not in words:
            words[word_addr] = 0

        words[word_addr] |= byte << (8 * byte_offset)

    # Write word-oriented output
    with open(output_file, "w") as f:
        current_block = None

        for word_addr in sorted(words.keys()):
            if current_block != word_addr:
                f.write(f"@{word_addr:08X}\n")
                current_block = word_addr

            f.write(f"{words[word_addr]:08X}\n")

if __name__ == '__main__':
    print('Converting {} in byte addressing to {} in word addressing'.format(sys.argv[1], sys.argv[2]))
    filename_byte = sys.argv[1]
    filename_word = sys.argv[2]
    convert_bytebin_to_word(filename_byte, filename_word)
    