"""iss.py - RV32I instruction-set simulator, the golden reference model.

Executes one instruction at a time, with no pipeline, and writes the same retirement trace
as tb_riscv.v. If the pipelined RTL and this model agree on every register write and every
store, in order, the pipeline's hazard handling is invisible - which is the whole point.

Matches riscv_top: separate instruction memory, data memory of DMEM_BYTES that wraps,
registers and memory start at zero, ECALL/EBREAK end the run.

usage: python iss.py prog.hex trace.txt
"""

import sys

DMEM_BYTES = 1024
MASK = 0xFFFFFFFF


def sx(val, bits):
    """sign-extend the low `bits` of val"""
    val &= (1 << bits) - 1
    return val - (1 << bits) if val >> (bits - 1) else val


def s32(val):
    return sx(val, 32)


def run(words, max_steps=200000):
    x = [0] * 32
    mem = bytearray(DMEM_BYTES)
    pc = 0
    trace = []

    def rd_mem(addr, n):
        return sum(mem[(addr + i) % DMEM_BYTES] << (8 * i) for i in range(n))

    def wr_mem(addr, n, val):
        for i in range(n):
            mem[(addr + i) % DMEM_BYTES] = (val >> (8 * i)) & 0xFF

    for _ in range(max_steps):
        idx = pc >> 2
        ins = words[idx] if idx < len(words) else 0x00000013
        op = ins & 0x7F
        rd = (ins >> 7) & 0x1F
        f3 = (ins >> 12) & 7
        rs1 = (ins >> 15) & 0x1F
        rs2 = (ins >> 20) & 0x1F
        f7 = ins >> 25
        a, b = x[rs1], x[rs2]
        imm_i = sx(ins >> 20, 12)
        imm_s = sx(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)
        imm_b = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) |
                   (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
        imm_u = ins & 0xFFFFF000
        imm_j = sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) |
                   (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)

        line = f"{pc:08x} {ins:08x}"
        next_pc = (pc + 4) & MASK
        result = None
        store = None

        if op == 0x37:                                   # LUI
            result = imm_u
        elif op == 0x17:                                 # AUIPC
            result = pc + imm_u
        elif op == 0x6F:                                 # JAL
            result = pc + 4
            next_pc = (pc + imm_j) & MASK
        elif op == 0x67:                                 # JALR
            result = pc + 4
            next_pc = (a + imm_i) & MASK & ~1
        elif op == 0x63:                                 # branches
            taken = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b),
                     6: a < b, 7: a >= b}.get(f3, False)
            if taken:
                next_pc = (pc + imm_b) & MASK
        elif op == 0x03:                                 # loads
            addr = (a + imm_i) & MASK
            n = 1 << (f3 & 3)
            val = rd_mem(addr, n)
            result = val if f3 & 4 or n == 4 else sx(val, 8 * n)
        elif op == 0x23:                                 # stores
            addr = (a + imm_s) & MASK
            n = 1 << (f3 & 3)
            val = b & ((1 << (8 * n)) - 1)
            wr_mem(addr, n, val)
            store = (n, addr, val)
        elif op in (0x13, 0x33):                         # ALU
            y = imm_i if op == 0x13 else b
            alt = (f7 & 0x20) != 0 and (op == 0x33 or f3 == 5)
            sh = y & 0x1F
            if f3 == 0:
                result = a - y if alt else a + y
            elif f3 == 1:
                result = a << sh
            elif f3 == 2:
                result = int(s32(a) < s32(y))
            elif f3 == 3:
                result = int(a < (y & MASK))
            elif f3 == 4:
                result = a ^ y
            elif f3 == 5:
                result = (s32(a) >> sh) if alt else (a >> sh)
            elif f3 == 6:
                result = a | y
            else:
                result = a & y
        elif op == 0x73:                                 # ECALL / EBREAK: stop
            trace.append(line)
            return trace, x
        # FENCE and unknown opcodes: NOP

        if result is not None and rd != 0:
            x[rd] = result & MASK
            line += f" x{rd}={x[rd]:08x}"
        if store:
            n, addr, val = store
            line += f" M{n}[{addr:08x}]={val:08x}"
        trace.append(line)
        pc = next_pc

    raise RuntimeError("ISS: no ECALL within max_steps")


def read_hex(path):
    with open(path) as f:
        return [int(t, 16) for t in f.read().split()]


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    trace, _ = run(read_hex(sys.argv[1]))
    with open(sys.argv[2], "w") as f:
        f.write("\n".join(trace) + "\n")
