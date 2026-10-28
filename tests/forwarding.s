# forwarding.s - data hazards between ALU instructions, resolved without stalls.
# gp = check number; pass writes 1 to tohost, fail writes 0xBAD00000 + gp.

    li   gp, 1                   # chain: every operand comes from the previous 1-2 instrs
    li   t0, 1
    add  t1, t0, t0              # t0 from EX/MEM on both ports            -> 2
    add  t2, t1, t0              # t1 from EX/MEM, t0 from MEM/WB          -> 3
    add  t3, t2, t1              # t2 from EX/MEM, t1 from MEM/WB          -> 5
    add  t4, t3, t2              #                                          -> 8
    li   t6, 8
    bne  t4, t6, fail

    li   gp, 2                   # same register written twice: the younger value wins
    li   t0, 10
    li   t0, 20                  # in EX/MEM while the 10 is in MEM/WB
    add  t1, t0, zero
    li   t6, 20
    bne  t1, t6, fail

    li   gp, 3                   # distance 3: WB writes while ID reads (regfile bypass)
    li   t0, 0x123
    nop
    nop
    add  t1, t0, zero
    li   t6, 0x123
    bne  t1, t6, fail

    li   gp, 4                   # x0 is never forwarded
    addi x0, zero, 7
    add  t1, x0, x0
    bnez t1, fail

    li   gp, 5                   # store data forwarded
    li   t0, 0x55
    sw   t0, 0(zero)
    lw   t1, 0(zero)
    li   t6, 0x55
    bne  t1, t6, fail

    li   gp, 6                   # store address base forwarded
    li   t2, 0x40
    sw   t0, 8(t2)
    lw   t1, 0x48(zero)
    bne  t1, t0, fail

    li   gp, 7                   # branch operands forwarded
    li   t0, 3
    li   t1, 3
    bne  t0, t1, fail

    li   gp, 8                   # JALR base forwarded; link value checked
    auipc t0, 0                  # P
    addi t0, t0, 16              # P+16
    jalr ra, 0(t0)               # at P+8, jumps to P+16
    j    fail                    # P+12, must be skipped
    auipc t1, 0                  # P+16
    addi t1, t1, -4              # P+12 = expected link
    bne  ra, t1, fail

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
