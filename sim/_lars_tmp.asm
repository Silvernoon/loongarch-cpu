# =============================================================================
# prog3.s — broad-coverage differential test (checked against LARS golden model)

# Exercises every instruction class the core implements, aiming at the corner
# cases most likely to diverge: signed vs unsigned compares/divides, MULH high
# words, arithmetic-vs-logical shifts, the >= / < branch boundaries, and
# sign/zero-extended sub-word loads.  Run with:
#     python3 tools/diff_test.py sim/prog3.s --mem 0x300 0x314
# =============================================================================

# ---- immediates & logical (r1..r7) -----------------------------------------
    lu12i.w $1, 0x7abcd          # r1 = 0x7abcd000
    ori     $1, $1, 0x123        # r1 = 0x7abcd123
    addi.w  $2, $0, -1           # r2 = 0xffffffff
    andi    $3, $1, 0xfff        # r3 = 0x123
    xori    $4, $1, 0x0ff        # r4 = 0x7abcd1dc
    slti    $5, $2, 0            # -1 < 0 signed -> 1
    sltui   $6, $2, 1            # 0xffffffff < 1 unsigned -> 0
    nor     $7, $1, $0           # r7 = ~r1

# ---- shifts: logical vs arithmetic, register & immediate (r8..r13) ---------
    slli.w  $8, $2, 31           # r8 = 0x80000000 (sign bit set; r2 = -1)
    srai.w  $9, $8, 4            # arithmetic  -> 0xf8000000
    srli.w  $10, $8, 4           # logical     -> 0x08000000
    addi.w  $11, $0, 3
    sll.w   $12, $8, $11         # 0x80000000 << 3 = 0 (shift out)
    sra.w   $13, $8, $11         # arith >> 3   = 0xf0000000

# ---- multiply high words, signed & unsigned (r14..r16) ---------------------
    mulh.w  $14, $2, $2          # hi((-1)*(-1)) = 0
    mulh.wu $15, $2, $2          # hi(0xffffffff^2) = 0xfffffffe
    mul.w   $16, $2, $2          # lo = 1

# ---- signed / unsigned divide & mod, negative operands (r17..r20) ----------
    addi.w  $17, $0, -17
    addi.w  $18, $0, 5
    div.w   $19, $17, $18        # signed -17/5 = -3 (trunc toward zero)
    mod.w   $20, $17, $18        # signed -17%5 = -2

# ---- branch boundary tests: bge (>=) and bltu (<) --------------------------
    addi.w  $21, $0, 5
    addi.w  $22, $0, 5
    bge     $21, $22, ge_ok      # 5 >= 5  -> taken (the LARS bge boundary case)
    addi.w  $21, $0, 111         # skipped if bge correct
ge_ok:
    addi.w  $23, $0, 1           # marker: reached here
    bltu    $22, $21, bad        # 5 < 5 unsigned -> NOT taken
    addi.w  $24, $0, 2           # executed (fallthrough)
    b       after
bad:
    addi.w  $24, $0, 999         # must never run
after:

# ---- store / load round-trip with sign & zero extension (r25..r30) ---------
    lu12i.w $25, 0
    ori     $25, $25, 0x300      # base = 0x300
    lu12i.w $26, 0x7edcb
    ori     $26, $26, 0xa98      # r26 = 0x7edcba98
    st.w    $26, $25, 0          # mem[0x300] = 0x7edcba98
    ld.w    $27, $25, 0          # r27 = 0x7edcba98
    st.h    $26, $25, 4          # mem[0x304] = 0xba98
    ld.h    $28, $25, 4          # sign-extend -> 0xffffba98
    ld.hu   $29, $25, 4          # zero-extend -> 0x0000ba98
    st.b    $26, $25, 8          # mem[0x308] = 0x98
    ld.b    $30, $25, 8          # sign-extend -> 0xffffff98

# ---- jump-and-link (r31 = ra via bl) ---------------------------------------
    bl      done
    addi.w  $5, $0, 777          # skipped by bl
done:
    nop
    nop
    nop