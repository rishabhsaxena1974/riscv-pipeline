# load_use.s - a load followed by an instruction that needs its result.
# These need one stall cycle; the data then comes from MEM/WB.
# gp = check number; pass writes 1 to tohost, fail writes 0xBAD00000 + gp.

    li   s0, 0x100
    li   t0, 0x1234
    sw   t0, 0(s0)

    li   gp, 1                   # load -> ALU rs1
    lw   t1, 0(s0)
    addi t2, t1, 1
    li   t6, 0x1235
    bne  t2, t6, fail

    li   gp, 2                   # load -> ALU rs2
    lw   t1, 0(s0)
    add  t2, t0, t1
    li   t6, 0x2468
    bne  t2, t6, fail

    li   gp, 3                   # load -> store data
    lw   t1, 0(s0)
    sw   t1, 4(s0)
    lw   t2, 4(s0)
    bne  t2, t0, fail

    li   gp, 4                   # load -> load address (pointer chase)
    sw   s0, 8(s0)
    lw   t1, 8(s0)
    lw   t2, 0(t1)
    bne  t2, t0, fail

    li   gp, 5                   # load -> branch operand
    lw   t1, 0(s0)
    beq  t1, t0, ok5
    j    fail
ok5:
    li   gp, 6                   # distance 2: no stall, forwarded from MEM/WB
    lw   t1, 0(s0)
    nop
    addi t2, t1, 0
    bne  t2, t0, fail

    li   gp, 7                   # load to x0 is discarded
    lw   zero, 0(s0)
    addi t2, zero, 0
    bnez t2, fail

    li   gp, 8                   # two loads back to back, then use both
    li   t3, 0x99
    sw   t3, 12(s0)
    lw   t1, 0(s0)
    lw   t2, 12(s0)
    add  t4, t1, t2
    li   t6, 0x12cd
    bne  t4, t6, fail

pass:
    li   t5, 0x80000000
    li   t6, 1
    sw   t6, 0(t5)
    ecall
fail:
    li   t5, 0x80000000
    li   t6, 0xbad00000
    add  t6, t6, gp
    sw   t6, 0(t5)
    ecall
