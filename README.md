# 5-Stage Pipelined RV32I RISC-V Core

A classic 5-stage in-order RISC-V pipeline in Verilog that runs the full RV32I base
integer ISA. It handles data hazards with forwarding and load-use stalls, and control
hazards with branch flushing. It is verified by comparing traces against a Python
instruction-set simulator on directed and constrained-random programs, and the testbench
is itself checked with injected bugs. It closes timing at 100 MHz on an Artix-7.

## Results

| | |
|---|---|
| ISA | RV32I: all 37 computational, load/store and branch/jump instructions; FENCE runs as a NOP, ECALL/EBREAK halt |
| Regression | 6 directed tests and 50 random programs; **15,025 retired instructions match the reference model, 0 mismatches** |
| Mutation check | **8 of 8** injected pipeline bugs caught |
| Timing | **100 MHz** on Artix-7 `xc7a35tcpg236-1` (10 ns clock, WNS +0.054 ns, post-route) |
| Area | 1,959 LUTs (1,083 logic + 876 distributed RAM), 452 flip-flops, 0 BRAM, 0 DSP. Includes 4 KB instruction and 1 KB data memory |
| CPI | 1.04 (ALU test) to 1.46 (bubble sort); see the table below |

## Architecture

```
    IF            ID               EX                 MEM             WB
 +------+  I  +---------+  I  +-------------+  E  +----------+  M  +---------+
 | PC   |  F  | decode  |  D  | fwd muxes   |  X  | data mem |  E  | write   |
 | imem |--/--| regfile |--/--| ALU         |--/--| ld/st    |--/--| regfile |
 +------+  I  | imm gen |  E  | branch cmp  |  M  | align    |  W  +---------+
    ^      D  | hazard  |  X  +-------------+  E  +----------+  B       |
    |         +---------+       |    ^    ^          |                  |
    +--- redirect (taken) ------+    |    +- EX/MEM -+                  |
                                     +------------ MEM/WB --------------+
```

| Stage | Work |
|---|---|
| IF | Fetch at PC. Predict not-taken: the next PC is PC + 4 |
| ID | Decode, read the register file, build the immediate, detect load-use hazards |
| EX | Pick forwarded operands, run the ALU, compare branch operands, resolve branches and jumps |
| MEM | Load or store with byte enables; align and sign- or zero-extend load data |
| WB | Write the result or load data to the register file |

| File | Contents |
|---|---|
| `rtl/riscv_core.v` | Pipeline registers, stage logic, stall/flush control |
| `rtl/decoder.v` | Control signals from the opcode, including `uses_rs1`/`uses_rs2` |
| `rtl/alu.v` | 10 ALU operations; also computes every address and branch target |
| `rtl/regfile.v` | 32 x 32 registers, 2 read ports and 1 write port, write-through bypass |
| `rtl/imm_gen.v` | I/S/B/U/J immediates |
| `rtl/forward_unit.v` | Forwarding select for EX operands |
| `rtl/hazard_unit.v` | Load-use stall detection |
| `rtl/lsu.v` | Store byte enables and lane replication; load extraction and extension |
| `rtl/imem.v`, `rtl/dmem.v` | Asynchronous-read memories (map to distributed RAM) |
| `rtl/riscv_top.v` | Core and memories, program-load port, `tohost` output register |

## Hazard handling

**Data hazards: forwarding.** An instruction reads its registers in ID, but the two
instructions ahead of it may not have written theirs yet. The forwarding unit compares the
EX instruction's `rs1`/`rs2` with the destination registers in EX/MEM and MEM/WB. On a
match it takes the value from that pipeline register instead.
- EX/MEM has priority, because it holds the newer value. `forwarding.s` check 2 covers this.
- x0 is never forwarded.
- A third case (the producer is in WB while the consumer is in ID) is handled inside the
  register file: a read and a write of the same register in the same cycle return the new
  value.

**Data hazards: load-use stall.** A load's data only exists at the end of MEM. The next
instruction needs it at the start of EX, one cycle earlier. So the hazard unit:
1. holds PC and IF/ID for one cycle,
2. inserts a bubble into ID/EX,
3. lets the data arrive through MEM/WB forwarding on the next cycle.

The decoder's `uses_rs1`/`uses_rs2` flags stop false stalls. Without them, a `lui x5` after
`lw x5` would stall even though `lui` reads no register.

**Control hazards.** Branches and jumps resolve in EX. When one is taken, the two younger
instructions in IF/ID and ID/EX are flushed into bubbles, a 2-cycle penalty. Every pipeline
register carries a valid bit, and a bubble has all its write enables cleared, so a flushed
instruction can never write a register or memory.

Cycle accounting is exact across the whole regression:
`cycles = instructions + 4 (pipeline fill) + load-use stalls + 2 x taken branches/jumps`.

## Verification

```
 test.s --asm.py--> test.hex --+--> iss.py (golden model) --> expected trace --+
                               |                                              +--> diff
                               +--> xsim: tb_riscv + RTL -----> actual trace --+
```

- **Trace comparison.** The testbench logs every instruction as it leaves WB, with its PC,
  encoding, register write and any store. `tools/iss.py` is a one-instruction-at-a-time
  RV32I simulator with no pipeline, and it writes the same format. The traces must match
  line for line, so every register write and every store is checked in program order. A
  hazard bug cannot hide, even when it does not change the final result.
- **Directed tests** (`tests/`) also check themselves against hand-computed answers and
  report pass/fail through `tohost`. This catches a bug that the ISS and the RTL might share.

| Test | Covers | Instr | Cycles | CPI | Stalls | Taken |
|---|---|---|---|---|---|---|
| `alu.s` | All R/I ops on overflow, sign and shift edges | 103 | 107 | 1.04 | 0 | 0 |
| `forwarding.s` | EX/MEM and MEM/WB forwarding, priority, regfile bypass, x0, store data/address, JALR base | 51 | 58 | 1.14 | 1 | 1 |
| `load_use.s` | Load into ALU rs1/rs2, store data, load address, branch; load to x0 | 51 | 65 | 1.27 | 8 | 1 |
| `branches.s` | All 6 conditions, JAL/JALR links, flush, loop, back-to-back taken branches | 68 | 114 | 1.68 | 0 | 21 |
| `memory.s` | LB/LH/LW/LBU/LHU/SB/SH/SW, byte lanes, sign extension, negative offsets | 73 | 79 | 1.08 | 2 | 0 |
| `bubble_sort.s` | Real program: xorshift fill, sort subroutine, order and checksum check | 1215 | 1779 | 1.46 | 136 | 212 |

- **Constrained-random programs** (`tools/randgen.py`). The constraints:
  - registers come from x0-x7, so back-to-back dependencies, load-use pairs and writes to x0
    are constant;
  - loads and stores use a protected base register with aligned in-range offsets;
  - branches, JAL and AUIPC+JALR only jump forward, so every program terminates.

  The 50-program regression retires 15,025 instructions, with 902 load-use stalls and
  1,032 taken branches/jumps.
- **Mutation check** (`run_tests.py --mutate`). Each mutation copies the RTL, injects one
  realistic bug and reruns the regression. All 8 are caught:

| Injected bug | Caught by |
|---|---|
| No EX/MEM forwarding | `alu` |
| No MEM/WB forwarding | `alu` |
| x0 gets forwarded | `forwarding` |
| No load-use stall | `forwarding` |
| No flush on a taken branch | `forwarding` |
| No register-file write-through | `alu` |
| SRA behaves like SRL | `alu` |
| LB zero-extends | `memory` |

## Synthesis

The run is out of context on Artix-7 `xc7a35tcpg236-1` with Vivado 2025.1, through
synthesis, place and route. It meets **100 MHz** with +0.054 ns slack. Reports are in
`synth/reports/`.

The critical path (12 logic levels, 9.66 ns) is the expected one for this design:

```
EX/MEM.rd -> forwarding compare -> forward mux -> 32-bit branch comparator (carry chain)
          -> redirect -> PC clock enable
```

Resolving branches in EX puts forwarding, comparison and the PC update in one cycle. To
go faster you would either register the redirect (a 3-cycle penalty) or predict branches
in IF.

## Running

```bash
python tools/run_tests.py                 # directed tests + 50 random programs (Vivado xsim)
python tools/run_tests.py --random 200    # more random programs
python tools/run_tests.py --mutate        # mutation check
python tools/asm.py tests/alu.s alu.hex   # assemble one program
python tools/iss.py alu.hex alu.trace     # run it on the reference model
cd synth && vivado -mode batch -source build.tcl -tclargs 10.0
```

`run_tests.py` expects Vivado in `C:/Xilinx/2025.1/Vivado/bin`. Set `VIVADO_BIN` to use
another location.

## Limitations

- No CSRs, interrupts or exceptions. ECALL/EBREAK only stop the simulation, and misaligned
  accesses are not trapped.
- Static not-taken prediction with a 2-cycle taken penalty, which is the largest CPI cost
  in `bubble_sort`. A branch target buffer or resolving branches in ID would reduce it.
- Memories use asynchronous reads (distributed RAM). Block RAM needs a registered read,
  which would split IF and MEM into address and data cycles.
