
# ---- basic arithmetic / immediates ----
    addi.w  r1, r0, 10        # r1 = 10
    addi.w  r2, r0, 20        # r2 = 20
    add.w   r3, r1, r2        # r3 = 30      (forward r2 from prior)
    sub.w   r4, r2, r1        # r4 = 10
    slt     r5, r1, r2        # r5 = 1
    sltu    r6, r2, r1        # r6 = 0
    and     r7, r1, r2        # r7 = 10&20 = 0
    or      r8, r1, r2        # r8 = 30
    xor     r9, r1, r2        # r9 = 30
    nor     r10, r1, r0       # r10 = ~10
    slli.w  r11, r1, 4        # r11 = 160
    srli.w  r12, r2, 1        # r12 = 10
    srai.w  r13, r10, 1       # r13 = arithmetic
    ori     r14, r0, 0xff     # r14 = 255
    andi    r15, r14, 0x0f    # r15 = 15
    lu12i.w r16, 0x12345      # r16 = 0x12345000
    ori     r16, r16, 0x678   # r16 = 0x12345678

# ---- multiply ----
    addi.w  r17, r0, 7
    addi.w  r18, r0, 6
    mul.w   r19, r17, r18     # r19 = 42
    addi.w  r20, r0, -3
    mul.w   r21, r20, r18     # r21 = -18

# ---- load / store round-trip (r22 base = 0x100) ----
    lu12i.w r22, 0
    ori     r22, r22, 0x100
    st.w    r16, r22, 0       # mem[0x100] = 0x12345678
    ld.w    r23, r22, 0       # r23 = 0x12345678  (load-use into next)
    add.w   r24, r23, r0      # r24 = 0x12345678  (depends on load -> stall)
    st.b    r1, r22, 4        # mem[0x104] = 10 (byte)
    ld.bu   r25, r22, 4       # r25 = 10

# ---- branch taken / not taken ----
    addi.w  r26, r0, 5
    addi.w  r27, r0, 5
    beq     r26, r27, eq_ok   # taken
    addi.w  r26, r0, 99       # skipped
eq_ok:
    addi.w  r28, r0, 1        # r28 = 1  (proves branch landed here)
    blt     r27, r26, no_take # 5 < 1? no -> not taken
    addi.w  r29, r0, 7        # executed (branch not taken)
no_take:
    addi.w  r30, r0, 3

# ---- divide ----
    addi.w  r5, r0, 100
    addi.w  r6, r0, 7
    div.w   r7, r5, r6        # r7 = 14
    mod.w   r8, r5, r6        # r8 = 2

# ---- unconditional jump to end ----
    bl      done
    addi.w  r9, r0, 123       # skipped by bl? bl links then jumps -> skipped
done:
    addi.w  r11, r0, 55       # final marker
    nop
    nop
    nop
