# bubble_sort.s - a real program: fill 16 words with xorshift values, sort them
# (signed, ascending) in a subroutine, then check the order and that the sum is unchanged.
# The inner loop is full of load-use pairs and taken/not-taken branches.
# gp = check number; pass writes 1 to tohost, fail writes 0xBAD00000 + gp.

    li   s0, 0x100               # array base
    li   s1, 16                  # n
    li   t0, 12345               # xorshift state
    mv   t3, s0
    li   t1, 0
    li   s2, 0                   # sum before sorting
fill:
    slli t2, t0, 13
    xor  t0, t0, t2
    srli t2, t0, 17
    xor  t0, t0, t2
    slli t2, t0, 5
    xor  t0, t0, t2
    sw   t0, 0(t3)
    add  s2, s2, t0
    addi t3, t3, 4
    addi t1, t1, 1
    blt  t1, s1, fill

    call sort

    mv   t3, s0                  # check a[i] <= a[i+1] and the sum
    li   t1, 1
    lw   t4, 0(t3)
    mv   s3, t4
check:
    lw   t5, 4(t3)
    add  s3, s3, t5
    li   gp, 1
    blt  t5, t4, fail
    mv   t4, t5
    addi t3, t3, 4
    addi t1, t1, 1
    blt  t1, s1, check
    li   gp, 2
    bne  s2, s3, fail
    j    pass

sort:                            # bubble sort a[0..n-1] at s0, n in s1
    addi a0, s1, -1
outer:
    mv   a1, s0
    li   a2, 0
inner:
    lw   a3, 0(a1)
    lw   a4, 4(a1)
    ble  a3, a4, noswap          # load-use on a4
    sw   a4, 0(a1)
    sw   a3, 4(a1)
noswap:
    addi a1, a1, 4
    addi a2, a2, 1
    blt  a2, a0, inner
    addi a0, a0, -1
    bnez a0, outer
    ret

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
