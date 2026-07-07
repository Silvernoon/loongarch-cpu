
# ---- loop: sum 1..10 into r3 (backward branch, forwarding chain) ----
    addi.w  r1, r0, 1        # i = 1
    addi.w  r2, r0, 10       # n = 10
    addi.w  r3, r0, 0        # sum = 0
loop:
    add.w   r3, r3, r1       # sum += i     (r3 forwarded each iter)
    addi.w  r1, r1, 1        # i++
    bge     r2, r1, loop     # while (n >= i)   -> sum = 55
# r3 should be 55

# ---- MULH high word (signed & unsigned) ----
    lu12i.w r4, 0x10000      # r4 = 0x10000000
    lu12i.w r5, 0x10000      # r5 = 0x10000000
    mulh.wu r6, r4, r5       # hi(0x10000000*0x10000000)=0x01000000
    addi.w  r7, r0, -1       # r7 = -1
    mulh.w  r8, r7, r7       # hi((-1)*(-1)=1) = 0
    mulh.wu r9, r7, r7       # hi(0xffffffff*0xffffffff)=0xfffffffe

# ---- unsigned vs signed divide ----
    addi.w  r10, r0, -20     # -20
    addi.w  r11, r0, 3
    div.w   r12, r10, r11    # signed: -20/3 = -6
    mod.w   r13, r10, r11    # signed: -20%3 = -2
    div.wu  r14, r10, r11    # unsigned: 0xffffffec / 3
    mod.wu  r15, r10, r11    # unsigned remainder

# ---- unsigned compare boundary ----
    addi.w  r16, r0, -1      # 0xffffffff
    addi.w  r17, r0, 1
    sltu    r18, r17, r16    # 1 < 0xffffffff unsigned = 1
    slt     r19, r16, r17    # -1 < 1 signed = 1

# ---- store halfword / load signed & unsigned ----
    lu12i.w r20, 0
    ori     r20, r20, 0x200
    addi.w  r21, r0, -2      # 0xfffffffe
    st.h    r21, r20, 0      # mem[0x200] = 0xfffe
    ld.h    r22, r20, 0      # sign-extend -> 0xfffffffe
    ld.hu   r23, r20, 0      # zero-extend -> 0x0000fffe

    nop
    nop
    nop
