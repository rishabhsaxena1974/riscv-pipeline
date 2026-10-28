"""run_tests.py - regression for the pipelined core.

For each test program:
    assemble (asm.py) -> expected trace (iss.py) -> RTL trace (Vivado xsim) -> compare
A test passes when the two traces are identical line for line: same instructions retired
in the same order, same register writes, same stores. Directed tests must additionally
report success through tohost (their own hand-computed checks).

usage:
    python tools/run_tests.py                 directed tests + 50 random programs
    python tools/run_tests.py --random 200    directed tests + 200 random programs
    python tools/run_tests.py --mutate        inject known bugs into a copy of the RTL and
                                              check that the regression catches each one
Set VIVADO_BIN if Vivado is not in C:/Xilinx/2025.1/Vivado/bin.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import asm      # noqa: E402
import iss      # noqa: E402
import randgen  # noqa: E402

VIVADO_BIN = Path(os.environ.get("VIVADO_BIN", "C:/Xilinx/2025.1/Vivado/bin"))
DIRECTED = ["alu", "forwarding", "load_use", "branches", "memory", "bubble_sort"]
RANDOM_LEN = 300
TOHOST_PASS = "M4[80000000]=00000001"

# (name, file, text to find, replacement) - each one is a realistic pipeline bug
MUTATIONS = [
    ("no EX/MEM forwarding",     "forward_unit.v", "mem_reg_write && mem_rd", "1'b0 && mem_rd"),
    ("no MEM/WB forwarding",     "forward_unit.v", "wb_reg_write  && wb_rd",  "1'b0 && wb_rd"),
    ("x0 gets forwarded",        "forward_unit.v", "mem_rd != 5'd0 && ",      ""),
    ("no load-use stall",        "hazard_unit.v",  "assign stall = id_valid", "assign stall = 1'b0"),
    ("no flush on taken branch", "riscv_core.v",   "rst || redirect",         "rst"),
    ("no regfile write-through", "regfile.v",      "(we && wa == ra",         "(1'b0 && wa == ra"),
    ("SRA behaves like SRL",     "alu.v",          "$signed(a) >>> shamt",    "a >> shamt"),
    ("LB zero-extends",          "lsu.v",          "{{24{shifted[7]}}",       "{{24{1'b0}}"),
]


def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True)


def compile_rtl(rtl_dir, sim_dir):
    sim_dir.mkdir(parents=True, exist_ok=True)
    srcs = " ".join(str(p) for p in sorted(rtl_dir.glob("*.v")))
    tb = ROOT / "tb" / "tb_riscv.v"
    for cmd in (f'"{VIVADO_BIN / "xvlog.bat"}" -i "{rtl_dir}" {srcs} "{tb}"',
                f'"{VIVADO_BIN / "xelab.bat"}" tb_riscv -s riscv_sim'):
        r = run(cmd, sim_dir)
        if r.returncode != 0:
            sys.exit(f"compile failed:\n{r.stdout}\n{r.stderr}")


def simulate(sim_dir, hex_path, trace_path):
    r = run(f'"{VIVADO_BIN / "xsim.bat"}" riscv_sim -R '
            f'-testplusarg HEX:{hex_path.as_posix()} -testplusarg TRACE:{trace_path.as_posix()}',
            sim_dir)
    m = re.search(r"(DONE|TIMEOUT) CYCLES=(\d+) INSTRET=(\d+)(?: STALLS=(\d+) REDIRECTS=(\d+))?",
                  r.stdout)
    if not m:
        return None
    return {"status": m.group(1), "cycles": int(m.group(2)), "instret": int(m.group(3)),
            "stalls": int(m.group(4) or 0), "redirects": int(m.group(5) or 0)}


def build_tests(n_random, seed0, work):
    """-> list of (name, source text, directed?)"""
    tests = [(t, (ROOT / "tests" / f"{t}.s").read_text(), True) for t in DIRECTED]
    for i in range(n_random):
        seed = seed0 + i
        src = randgen.Gen(seed).program(RANDOM_LEN)
        (work / f"rand_{seed}.s").write_text(src)
        tests.append((f"rand_{seed}", src, False))
    return tests


def run_test(name, src, directed, sim_dir, work):
    hex_path = work / f"{name}.hex"
    asm.write_hex(asm.assemble(src), hex_path)
    expected, _ = iss.run(iss.read_hex(hex_path))

    trace_path = work / f"{name}.rtl.trace"
    stats = simulate(sim_dir, hex_path, trace_path)
    if stats is None or stats["status"] != "DONE":
        return False, "simulation did not finish", stats
    actual = trace_path.read_text().splitlines()

    for i, (e, a) in enumerate(zip(expected, actual)):
        if e != a:
            return False, f"trace line {i + 1}: expected '{e}', got '{a}'", stats
    if len(expected) != len(actual):
        return False, f"trace length: expected {len(expected)}, got {len(actual)}", stats
    if directed and TOHOST_PASS not in expected[-2]:
        return False, f"self-check failed: {expected[-2]}", stats
    return True, "", stats


def regression(n_random, seed0):
    work = ROOT / "sim" / "work"
    work.mkdir(parents=True, exist_ok=True)
    sim_dir = ROOT / "sim" / "xsim"
    compile_rtl(ROOT / "rtl", sim_dir)

    total = {"cycles": 0, "instret": 0, "stalls": 0, "redirects": 0}
    failures = 0
    print(f"{'test':14s} {'instr':>7s} {'cycles':>7s} {'CPI':>6s} {'stalls':>7s} {'flushes':>8s}  result")
    for name, src, directed in build_tests(n_random, seed0, work):
        ok, msg, st = run_test(name, src, directed, sim_dir, work)
        failures += not ok
        if st:
            for k in total:
                total[k] += st[k]
        if directed or not ok:
            cpi = f"{st['cycles'] / st['instret']:.2f}" if st and st["instret"] else "-"
            print(f"{name:14s} {st['instret'] if st else '-':>7} {st['cycles'] if st else '-':>7} "
                  f"{cpi:>6s} {st['stalls'] if st else '-':>7} {st['redirects'] if st else '-':>8}  "
                  f"{'PASS' if ok else 'FAIL ' + msg}")
    print(f"random: {n_random} programs x ~{RANDOM_LEN} instructions (seeds {seed0}-{seed0 + n_random - 1})")
    print(f"total: {total['instret']} instructions retired, {total['cycles']} cycles, "
          f"{total['stalls']} load-use stalls, {total['redirects']} taken branches/jumps")
    print("ALL PASS" if failures == 0 else f"{failures} FAILED")
    return failures == 0


def mutation_check(n_random, seed0):
    work = ROOT / "sim" / "work"
    work.mkdir(parents=True, exist_ok=True)
    tests = build_tests(n_random, seed0, work)
    caught_all = True
    for k, (name, fname, old, new) in enumerate(MUTATIONS):
        mut_rtl = ROOT / "sim" / f"mutant{k}" / "rtl"
        if mut_rtl.exists():
            shutil.rmtree(mut_rtl)
        shutil.copytree(ROOT / "rtl", mut_rtl)
        text = (mut_rtl / fname).read_text()
        if old not in text:
            sys.exit(f"mutation '{name}': pattern not found in {fname}")
        (mut_rtl / fname).write_text(text.replace(old, new))
        sim_dir = mut_rtl.parent / "xsim"
        compile_rtl(mut_rtl, sim_dir)
        caught_by = None
        for tname, src, directed in tests:
            ok, _, _ = run_test(tname, src, directed, sim_dir, work)
            if not ok:
                caught_by = tname
                break
        caught_all &= caught_by is not None
        print(f"{name:26s} {'caught by ' + caught_by if caught_by else 'NOT CAUGHT'}")
    print("all mutants caught" if caught_all else "SOME MUTANTS SURVIVED")
    return caught_all


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--random", type=int, default=50, help="number of random programs")
    ap.add_argument("--seed", type=int, default=1, help="first random seed")
    ap.add_argument("--mutate", action="store_true", help="run the mutation check instead")
    args = ap.parse_args()
    ok = mutation_check(args.random, args.seed) if args.mutate else regression(args.random, args.seed)
    sys.exit(0 if ok else 1)
