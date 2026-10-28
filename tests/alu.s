# alu.s - every R- and I-type ALU operation on edge values, against hand-computed answers.
# gp holds the number of the current check. Pass writes 1 to tohost (0x80000000),
# fail writes 0xBAD00000 + gp.

    li   a0, 0x7fffffff
    li   a1, 0x80000000
    li   a2, -1
    li   a3, 5

    li   gp, 1
    add  t0, a0, a3              # signed overflow wraps
    li   t6, 0x80000004
    bne  t0, t6, fail

    li   gp, 2
    sub  t0, a1, a3
    li   t6, 0x7ffffffb
    bne  t0, t6, fail

    li   gp, 3
    sll  t0, a2, a3
    li   t6, 0xffffffe0
    bne  t0, t6, fail

    li   gp, 4
    srl  t0, a1, a3              # logical: zeros shifted in
    li   t6, 0x04000000
    bne  t0, t6, fail

    li   gp, 5
    sra  t0, a1, a3              # arithmetic: sign bit shifted in
    li   t6, 0xfc000000
    bne  t0, t6, fail

    li   gp, 6
    slt  t0, a1, a3              # -2^31 < 5 signed
    li   t6, 1
    bne  t0, t6, fail

    li   gp, 7
    sltu t0, a1, a3              # 0x80000000 > 5 unsigned
    bnez t0, fail

    li   gp, 8
    xor  t0, a0, a2
    li   t6, 0x80000000
    bne  t0, t6, fail

    li   gp, 9
    or   t0, a3, a1
    li   t6, 0x80000005
    bne  t0, t6, fail

    li   gp, 10
    and  t0, a2, a3
    li   t6, 5
    bne  t0, t6, fail

    li   gp, 11
    addi t0, a3, -6
    li   t6, -1
    bne  t0, t6, fail

    li   gp, 12
    slti t0, a2, 0
    li   t6, 1
    bne  t0, t6, fail

    li   gp, 13
    sltiu t0, a3, -1             # immediate is sign-extended, then compared unsigned
    li   t6, 1
    bne  t0, t6, fail

    li   gp, 14
    xori t0, a3, -1              # = not
    li   t6, 0xfffffffa
    bne  t0, t6, fail

    li   gp, 15
    ori  t0, a3, 0x7f0
    li   t6, 0x7f5
    bne  t0, t6, fail

    li   gp, 16
    andi t0, a2, 0xf0
    li   t6, 0xf0
    bne  t0, t6, fail

    li   gp, 17
    slli t0, a3, 31
    li   t6, 0x80000000
    bne  t0, t6, fail

    li   gp, 18
    srli t0, a2, 31
    li   t6, 1
    bne  t0, t6, fail

    li   gp, 19
    srai t0, a1, 31
    li   t6, -1
    bne  t0, t6, fail

    li   gp, 20
    lui  t0, 0xabcde
    li   t6, 0xabcde000
    bne  t0, t6, fail

    li   gp, 21
    auipc t0, 1                  # t0 = P + 0x1000
    auipc t1, 0                  # t1 = P + 4
    sub  t0, t0, t1
    li   t6, 0xffc
    bne  t0, t6, fail

    li   gp, 22
    li   t1, 33
    sll  t0, a3, t1              # only the low 5 bits of rs2 count: shift by 1
    li   t6, 10
    bne  t0, t6, fail

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
