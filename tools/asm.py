"""asm.py - minimal two-pass RV32I assembler.

Supports every RV32I base instruction except FENCE/CSR, labels, '#' comments, ABI register
names and these pseudo-instructions:
    nop, li, mv, not, neg, j, jr, ret, beqz, bnez, bgt, ble, bgtu, bleu, call
Output: one 32-bit hex word per line, for $readmemh.

usage: python asm.py prog.s prog.hex
"""

import re
import sys

ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
       "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
       "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
       "t3", "t4", "t5", "t6"]
REGS = {f"x{i}": i for i in range(32)}
REGS.update({name: i for i, name in enumerate(ABI)})
REGS["fp"] = 8

R_OPS = {  # name: (funct7, funct3)
    "add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
    "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
    "or": (0x00, 6), "and": (0x00, 7),
}
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_I = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}


class AsmError(Exception):
    pass


def reg(tok):
    tok = tok.strip()
    if tok not in REGS:
        raise AsmError(f"bad register '{tok}'")
    return REGS[tok]


def num(tok):
    return int(tok.strip(), 0)


def mem_operand(tok):
    """'imm(rs1)' -> (imm, rs1)"""
    m = re.fullmatch(r"\s*(-?\w*)\s*\(\s*(\w+)\s*\)\s*", tok)
    if not m:
        raise AsmError(f"bad memory operand '{tok}'")
    return (num(m.group(1)) if m.group(1) else 0), reg(m.group(2))


def check_range(val, bits, what):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not lo <= val <= hi:
        raise AsmError(f"{what} {val} does not fit in {bits} signed bits")


def enc_r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    check_range(imm, 12, "I-immediate")
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3, op):
    check_range(imm, 12, "S-immediate")
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_b(off, rs2, rs1, f3):
    check_range(off, 13, "branch offset")
    if off & 1:
        raise AsmError("branch offset must be even")
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63


def enc_u(imm20, rd, op):
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op


def enc_j(off, rd):
    check_range(off, 21, "jump offset")
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | \
           (((o >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def split_li(val):
    """li rd, val -> list of (op, imm) in the order emitted."""
    val = val & 0xFFFFFFFF
    sval = val - (1 << 32) if val & 0x80000000 else val
    if -2048 <= sval <= 2047:
        return [("addi", sval)]
    lo = sval & 0xFFF
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((val - lo) >> 12) & 0xFFFFF
    return [("lui", hi)] + ([("addi", lo)] if lo else [])


def expand(mn, ops):
    """Pseudo-instructions -> list of (mnemonic, operands). Sizes are known here."""
    if mn == "nop":
        return [("addi", ["x0", "x0", "0"])]
    if mn == "li":
        out = []
        for i, (op, imm) in enumerate(split_li(num(ops[1]))):
            if op == "lui":
                out.append(("lui", [ops[0], str(imm)]))
            else:
                out.append(("addi", [ops[0], "x0" if i == 0 else ops[0], str(imm)]))
        return out
    if mn == "mv":
        return [("addi", [ops[0], ops[1], "0"])]
    if mn == "not":
        return [("xori", [ops[0], ops[1], "-1"])]
    if mn == "neg":
        return [("sub", [ops[0], "x0", ops[1]])]
    if mn == "j":
        return [("jal", ["x0", ops[0]])]
    if mn == "call":
        return [("jal", ["ra", ops[0]])]
    if mn == "jr":
        return [("jalr", ["x0", ops[0], "0"])]
    if mn == "ret":
        return [("jalr", ["x0", "ra", "0"])]
    if mn == "beqz":
        return [("beq", [ops[0], "x0", ops[1]])]
    if mn == "bnez":
        return [("bne", [ops[0], "x0", ops[1]])]
    swapped = {"bgt": "blt", "ble": "bge", "bgtu": "bltu", "bleu": "bgeu"}
    if mn in swapped:
        return [(swapped[mn], [ops[1], ops[0], ops[2]])]
    if mn == "jal" and len(ops) == 1:
        return [("jal", ["ra", ops[0]])]
    if mn == "jalr" and len(ops) == 1:
        return [("jalr", ["ra", ops[0], "0"])]
    return [(mn, ops)]


def encode(mn, ops, pc, labels):
    def target(tok):
        tok = tok.strip()
        if tok in labels:
            return labels[tok] - pc
        return num(tok)

    if mn in R_OPS:
        f7, f3 = R_OPS[mn]
        return enc_r(f7, reg(ops[2]), reg(ops[1]), f3, reg(ops[0]), 0x33)
    if mn in I_OPS:
        return enc_i(num(ops[2]), reg(ops[1]), I_OPS[mn], reg(ops[0]), 0x13)
    if mn in SHIFT_I:
        f7, f3 = SHIFT_I[mn]
        sh = num(ops[2])
        if not 0 <= sh <= 31:
            raise AsmError(f"shift amount {sh} out of range")
        return enc_r(f7, sh, reg(ops[1]), f3, reg(ops[0]), 0x13)
    if mn in LOADS:
        imm, rs1 = mem_operand(ops[1])
        return enc_i(imm, rs1, LOADS[mn], reg(ops[0]), 0x03)
    if mn in STORES:
        imm, rs1 = mem_operand(ops[1])
        return enc_s(imm, reg(ops[0]), rs1, STORES[mn], 0x23)
    if mn in BRANCHES:
        return enc_b(target(ops[2]), reg(ops[1]), reg(ops[0]), BRANCHES[mn])
    if mn == "lui":
        return enc_u(num(ops[1]), reg(ops[0]), 0x37)
    if mn == "auipc":
        return enc_u(num(ops[1]), reg(ops[0]), 0x17)
    if mn == "jal":
        return enc_j(target(ops[1]), reg(ops[0]))
    if mn == "jalr":
        if len(ops) == 2:                          # jalr rd, imm(rs1)
            imm, rs1 = mem_operand(ops[1])
        else:                                      # jalr rd, rs1, imm
            rs1, imm = reg(ops[1]), num(ops[2])
        return enc_i(imm, rs1, 0, reg(ops[0]), 0x67)
    if mn == "ecall":
        return 0x00000073
    if mn == "ebreak":
        return 0x00100073
    raise AsmError(f"unknown instruction '{mn}'")


def split_operands(text):
    return [t.strip() for t in text.split(",")] if text.strip() else []


def assemble(src):
    """Assembly text -> list of 32-bit words."""
    # pass 1: expand pseudo-instructions, assign addresses to labels
    labels, insns = {}, []
    for lineno, line in enumerate(src.splitlines(), 1):
        line = line.split("#")[0].strip()
        while ":" in line:
            name, line = line.split(":", 1)
            labels[name.strip()] = 4 * len(insns)
            line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        mn = parts[0].lower()
        ops = split_operands(parts[1] if len(parts) > 1 else "")
        try:
            for emn, eops in expand(mn, ops):
                insns.append((emn, eops, lineno, line))
        except (AsmError, ValueError, IndexError) as e:
            raise AsmError(f"line {lineno}: {line}: {e}") from None

    # pass 2: encode with every label known
    words = []
    for i, (mn, ops, lineno, line) in enumerate(insns):
        try:
            words.append(encode(mn, ops, 4 * i, labels) & 0xFFFFFFFF)
        except (AsmError, ValueError, IndexError) as e:
            raise AsmError(f"line {lineno}: {line}: {e}") from None
    return words


def write_hex(words, path):
    with open(path, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1]) as f:
        write_hex(assemble(f.read()), sys.argv[2])
