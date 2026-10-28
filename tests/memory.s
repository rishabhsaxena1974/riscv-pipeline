# memory.s - byte/halfword/word loads and stores, sign vs zero extension, byte lanes.
# gp = check number; pass writes 1 to tohost, fail writes 0xBAD00000 + gp.

    li   s0, 0x200
    li   t0, 0x8899aabb
    sw   t0, 0(s0)               # bytes at 0x200..0x203: bb aa 99 88 (little-endian)

    li   gp, 1
    lb   t1, 0(s0)
    li   t6, 0xffffffbb
    bne  t1, t6, fail

    li   gp, 2
    lbu  t1, 0(s0)
    li   t6, 0xbb
    bne  t1, t6, fail

    li   gp, 3
    lb   t1, 1(s0)
    li   t6, 0xffffffaa
    bne  t1, t6, fail

    li   gp, 4
    lbu  t1, 3(s0)
    li   t6, 0x88
    bne  t1, t6, fail

    li   gp, 5
    lh   t1, 0(s0)
    li   t6, 0xffffaabb
    bne  t1, t6, fail

    li   gp, 6
    lhu  t1, 2(s0)
    li   t6, 0x8899
    bne  t1, t6, fail

    li   gp, 7
    lh   t1, 2(s0)
    li   t6, 0xffff8899
    bne  t1, t6, fail

    li   gp, 8                   # SB writes one lane only
    li   t2, 0x11
    sb   t2, 1(s0)
    lw   t1, 0(s0)
    li   t6, 0x889911bb
    bne  t1, t6, fail

    li   gp, 9                   # SH to the upper half
    li   t2, 0x2233
    sh   t2, 2(s0)
    lw   t1, 0(s0)
    li   t6, 0x223311bb
    bne  t1, t6, fail

    li   gp, 10                  # SB stores only the low byte of rs2
    li   t2, 0x12345677
    sb   t2, 3(s0)
    lw   t1, 0(s0)
    li   t6, 0x773311bb
    bne  t1, t6, fail

    li   gp, 11                  # positive halfword stays positive
    li   t2, 0x7fff
    sh   t2, 0(s0)
    lh   t1, 0(s0)
    bne  t1, t2, fail

    li   gp, 12                  # negative offset
    sw   t0, -4(s0)
    addi s1, s0, -4
    lw   t1, 0(s1)
    bne  t1, t0, fail

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
