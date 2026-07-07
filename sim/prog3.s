# =============================================================================
# prog3.s — broad-coverage differential test (checked against LARS golden model)
#
# Exercises every instruction class the core implements, aiming at the corner
# cases most likely to diverge: signed vs unsigned compares/divides, MULH high
# words, arithmetic-vs-logical shifts, the >= / < branch boundaries, and
# sign/zero-extended sub-word loads.  Run with:
#     python3 tools/diff_test.py sim/prog3.s --mem 0x300 0x314
# =============================================================================

# ---- immediates & logical (r1..r7) -----------------------------------------
    lu12i.w r1, 0x7abcd          # r1 = 0x7abcd000
    ori     r1, r1, 0x123        # r1 = 0x7abcd123
    addi.w  r2, r0, -1           # r2 = 0xffffffff
    andi    r3, r1, 0xfff        # r3 = 0x123
    xori    r4, r1, 0x0ff        # r4 = 0x7abcd1dc
    slti    r5, r2, 0            # -1 < 0 signed -> 1
    sltui   r6, r2, 1            # 0xffffffff < 1 unsigned -> 0
    nor     r7, r1, r0           # r7 = ~r1

# ---- shifts: logical vs arithmetic, register & immediate (r8..r13) ---------
    slli.w  r8, r2, 31           # r8 = 0x80000000 (sign bit set; r2 = -1)
    srai.w  r9, r8, 4            # arithmetic  -> 0xf8000000
    srli.w  r10, r8, 4           # logical     -> 0x08000000
    addi.w  r11, r0, 3
    sll.w   r12, r8, r11         # 0x80000000 << 3 = 0 (shift out)
    sra.w   r13, r8, r11         # arith >> 3   = 0xf0000000

# ---- multiply high words, signed & unsigned (r14..r16) ---------------------
    mulh.w  r14, r2, r2          # hi((-1)*(-1)) = 0
    mulh.wu r15, r2, r2          # hi(0xffffffff^2) = 0xfffffffe
    mul.w   r16, r2, r2          # lo = 1

# ---- signed / unsigned divide & mod, negative operands (r17..r20) ----------
    addi.w  r17, r0, -17
    addi.w  r18, r0, 5
    div.w   r19, r17, r18        # signed -17/5 = -3 (trunc toward zero)
    mod.w   r20, r17, r18        # signed -17%5 = -2

# ---- branch boundary tests: bge (>=) and bltu (<) --------------------------
    addi.w  r21, r0, 5
    addi.w  r22, r0, 5
    bge     r21, r22, ge_ok      # 5 >= 5  -> taken (the LARS bge boundary case)
    addi.w  r21, r0, 111         # skipped if bge correct
ge_ok:
    addi.w  r23, r0, 1           # marker: reached here
    bltu    r22, r21, bad        # 5 < 5 unsigned -> NOT taken
    addi.w  r24, r0, 2           # executed (fallthrough)
    b       after
bad:
    addi.w  r24, r0, 999         # must never run
after:

# ---- store / load round-trip with sign & zero extension (r25..r30) ---------
    lu12i.w r25, 0
    ori     r25, r25, 0x300      # base = 0x300
    lu12i.w r26, 0x7edcb
    ori     r26, r26, 0xa98      # r26 = 0x7edcba98
    st.w    r26, r25, 0          # mem[0x300] = 0x7edcba98
    ld.w    r27, r25, 0          # r27 = 0x7edcba98
    st.h    r26, r25, 4          # mem[0x304] = 0xba98
    ld.h    r28, r25, 4          # sign-extend -> 0xffffba98
    ld.hu   r29, r25, 4          # zero-extend -> 0x0000ba98
    st.b    r26, r25, 8          # mem[0x308] = 0x98
    ld.b    r30, r25, 8          # sign-extend -> 0xffffff98

# ---- jump-and-link (r31 = ra via bl) ---------------------------------------
    bl      done
    addi.w  r5, r0, 777          # skipped by bl
done:
    nop
    nop
    nop
