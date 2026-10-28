"""randgen.py - constrained-random RV32I program generator.

Directed tests check the hazards someone thought of; random programs find the ones nobody
did. The constraints keep every program legal and terminating:
  - rd/rs come from a small pool (x0-x7), so back-to-back dependencies, load-use pairs and
    writes to x0 happen all the time
  - x31 is a fixed base pointer (0x100) that is never overwritten; loads and stores use it
    with aligned offsets inside the 1 KB data memory
  - branches and jumps only go forward, skipping 0-3 instructions, so every program ends
  - x9 is reserved as the AUIPC base for the AUIPC+JALR pattern
Ends with ECALL.

usage: python randgen.py <seed> <n_instructions> out.s
"""

import random
import sys

POOL = [f"x{i}" for i in range(0, 8)]
WEIGHTS = [1] + [6] * 7                 # x0 is rare but present
BASE = "x31"
R_OPS = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
I_OPS = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SH_OPS = ["slli", "srli", "srai"]
LOADS = {"lb": 1, "lh": 2, "lw": 4, "lbu": 1, "lhu": 2}
STORES = {"sb": 1, "sh": 2, "sw": 4}
BRANCHES = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]


class Gen:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.lines = []
        self.label_id = 0

    def r(self):
        return self.rng.choices(POOL, WEIGHTS)[0]

    def interesting(self):
        """values that stress sign, overflow and shift edges"""
        return self.rng.choice([0, 1, -1, 0x7FFFFFFF, -0x80000000, 0x80, 0xFF, 0xFFFF,
                                0x8000, self.rng.randint(-2**31, 2**31 - 1)])

    def emit(self, s):
        self.lines.append("    " + s)

    def label(self):
        self.label_id += 1
        return f"L{self.label_id}"

    def mem_offset(self, size):
        return self.rng.randrange(-256, 256 - size + 1, size)   # base 0x100 -> 0..511

    def simple(self, single=False):
        """one non-control instruction (two for a forced load-use pair, unless single)"""
        k = self.rng.random()
        if k < 0.30:
            self.emit(f"{self.rng.choice(R_OPS)} {self.r()}, {self.r()}, {self.r()}")
        elif k < 0.50:
            self.emit(f"{self.rng.choice(I_OPS)} {self.r()}, {self.r()}, {self.rng.randint(-2048, 2047)}")
        elif k < 0.60:
            self.emit(f"{self.rng.choice(SH_OPS)} {self.r()}, {self.r()}, {self.rng.randint(0, 31)}")
        elif k < 0.65:
            self.emit(f"{self.rng.choice(['lui', 'auipc'])} {self.r()}, {self.rng.randint(0, 0xFFFFF)}")
        elif k < 0.85:
            op = self.rng.choice(list(LOADS))
            self.emit(f"{op} {self.r()}, {self.mem_offset(LOADS[op])}({BASE})")
            if not single and self.rng.random() < 0.5:   # force a load-use pair
                self.emit(f"{self.rng.choice(R_OPS)} {self.r()}, {self.lines[-1].split()[1].rstrip(',')}, {self.r()}")
        else:
            op = self.rng.choice(list(STORES))
            self.emit(f"{op} {self.r()}, {self.mem_offset(STORES[op])}({BASE})")

    def control(self):
        k = self.rng.random()
        skip = self.rng.randint(0, 3)
        if k < 0.6:
            lab = self.label()
            self.emit(f"{self.rng.choice(BRANCHES)} {self.r()}, {self.r()}, {lab}")
        elif k < 0.85:
            lab = self.label()
            self.emit(f"jal {self.r()}, {lab}")
        else:                                            # AUIPC + JALR, forward
            lab = None
            self.emit("auipc x9, 0")
            self.emit(f"jalr {self.r()}, {8 + 4 * skip}(x9)")
        for _ in range(skip):                            # JALR offset counts these exactly
            self.simple(single=True)
        if lab:
            self.lines.append(f"{lab}:")

    def program(self, n):
        self.emit(f"li {BASE}, 0x100")
        for reg in POOL[1:]:
            self.emit(f"li {reg}, {self.interesting()}")
        for i in range(32):                              # seed data memory
            self.emit(f"li x1, {self.interesting()}")
            self.emit(f"sw x1, {4 * i - 64}({BASE})")
        while len(self.lines) < n:
            if self.rng.random() < 0.15:
                self.control()
            else:
                self.simple()
        self.emit("ecall")
        return "\n".join(self.lines) + "\n"


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    with open(sys.argv[3], "w") as f:
        f.write(Gen(int(sys.argv[1])).program(int(sys.argv[2])))
