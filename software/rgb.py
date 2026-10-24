#!/usr/bin/env python3
# Control the RGB bits of axil_regs through /dev/mem. Run as root.
#   sudo ./rgb.py red        sudo ./rgb.py 5        sudo ./rgb.py off
#   sudo ./rgb.py dump
# Register 1 (offset 0x04) bits [2:0] = {red, green, blue}.
import mmap, os, sys

BASE = 0x40000000   # axil_regs base address: copy from the Vivado Address Editor
SPAN = 0x1000       # one page; covers the 8 registers at 0x00..0x1C
REG_RGB = 1         # register index (byte offset 4 * REG_RGB)

COLORS = {"off": 0, "blue": 1, "green": 2, "cyan": 3,
          "red": 4, "magenta": 5, "yellow": 6, "white": 7}

def open_regs(path="/dev/mem"):
    fd = os.open(path, os.O_RDWR | os.O_SYNC)
    m = mmap.mmap(fd, SPAN, mmap.MAP_SHARED,
                  mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)
    os.close(fd)                      # mapping stays valid after close
    return m, memoryview(m).cast("I") # 32-bit word view: regs[k] is offset 4k

def main():
