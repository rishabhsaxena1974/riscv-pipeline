# branches.s - all six branch conditions, JAL/JALR links, flushing and loops.
# gp = check number; pass writes 1 to tohost, fail writes 0xBAD00000 + gp.

    li   a0, -1
    li   a1, 1

    li   gp, 1
    beq  a0, a1, fail            # not taken
    bne  a0, a1, b1              # taken
    j    fail
b1:
    li   gp, 2
    blt  a0, a1, b2              # signed: -1 < 1
    j    fail
b2:
    li   gp, 3
    bltu a0, a1, fail            # unsigned: 0xffffffff > 1
    bgeu a0, a1, b3
    j    fail
b3:
    li   gp, 4
    bge  a1, a0, b4
    j    fail
b4:
    li   gp, 5
    bge  a0, a0, b5              # equal counts as >=
    j    fail
b5:
    li   gp, 6                   # the two instructions after a taken branch never commit
    li   t0, 0
    beq  zero, zero, b6
    addi t0, t0, 1
    addi t0, t0, 2
b6:
    bnez t0, fail

    li   gp, 7                   # JAL writes the return address, JALR returns
    jal  ra, f1
r1:
    j    b7
f1:
    auipc t1, 0                  # address of f1
    addi t1, t1, -4              # = address of r1
    bne  ra, t1, fail
    jalr x0, 0(ra)
b7:
    li   gp, 8                   # backward branch: sum 10..1
    li   t0, 0
    li   t1, 10
loop:
    add  t0, t0, t1
    addi t1, t1, -1
    bnez t1, loop
    li   t6, 55
    bne  t0, t6, fail

    li   gp, 9                   # taken branches back to back
    beq  zero, zero, c1
    j    fail
c1:
    beq  zero, zero, c2
    j    fail
c2:
    jal  x0, c3
    j    fail
c3:

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
