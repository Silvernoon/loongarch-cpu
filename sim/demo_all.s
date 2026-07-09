# =============================================================================
# demo_all.s
#
# Defense demo program: one assembly file covering every instruction implemented
# by this LoongArch32 CPU.  The same file is intended to be opened in LARS/MARS
# for step execution and assembled into sim/demo_all.hex for Vivado CPU testing.
# Register syntax uses $N so LARS can open it directly; tools/la32.py also
# accepts the same syntax.
# =============================================================================

# ---- arithmetic, logical, and immediate instructions ------------------------
    lu12i.w    $1, 0x7abcd          # $1 = 0x7abcd000
    ori        $1, $1, 0x123        # $1 = 0x7abcd123
    pcaddu12i  $2, 0                # exercise PC-relative high-immediate add

    addi.w     $3, $0, 10           # $3 = 10
    addi.w     $4, $0, 20           # $4 = 20
    add.w      $5, $3, $4           # $5 = 30
    sub.w      $6, $4, $3           # $6 = 10
    slt        $7, $3, $4           # signed 10 < 20
    sltu       $8, $4, $3           # unsigned 20 < 10 -> 0
    slti       $9, $3, 11           # 10 < 11
    sltui      $10, $3, 11          # unsigned 10 < 11
    and        $11, $3, $4
    or         $12, $3, $4
    xor        $13, $3, $4
    nor        $14, $3, $0
    andi       $15, $1, 0xfff
    xori       $16, $15, 0x0ff

# ---- shift instructions -----------------------------------------------------
    slli.w     $17, $3, 2
    srli.w     $18, $17, 1
    addi.w     $19, $0, -16
    srai.w     $20, $19, 2
    addi.w     $21, $0, 3
    sll.w      $22, $3, $21
    srl.w      $23, $22, $21
    sra.w      $24, $19, $21

# ---- multiply and divide instructions --------------------------------------
    mul.w      $25, $3, $4
    mulh.w     $26, $19, $4
    mulh.wu    $27, $19, $4
    div.w      $28, $25, $3
    mod.w      $29, $25, $4
    div.wu     $30, $25, $3
    mod.wu     $31, $25, $3

# ---- load/store instructions ------------------------------------------------
    lu12i.w    $2, 0
    ori        $2, $2, 0x300        # data base = 0x300
    st.w       $1, $2, 0
    ld.w       $5, $2, 0
    st.h       $19, $2, 4
    ld.h       $6, $2, 4
    ld.hu      $7, $2, 4
    st.b       $19, $2, 8
    ld.b       $8, $2, 8
    ld.bu      $9, $2, 8

# ---- conditional branches ---------------------------------------------------
    addi.w     $10, $0, 5
    addi.w     $11, $0, 5
    addi.w     $12, $0, 7

    beq        $10, $11, beq_ok
    addi.w     $13, $0, 100         # skipped if beq works
beq_ok:
    bne        $10, $12, bne_ok
    addi.w     $13, $0, 101         # skipped if bne works
bne_ok:
    blt        $10, $12, blt_ok
    addi.w     $13, $0, 102         # skipped if blt works
blt_ok:
    bge        $12, $10, bge_ok
    addi.w     $13, $0, 103         # skipped if bge works
bge_ok:
    bltu       $10, $12, bltu_ok
    addi.w     $13, $0, 104         # skipped if bltu works
bltu_ok:
    bgeu       $12, $10, bgeu_ok
    addi.w     $13, $0, 105         # skipped if bgeu works
bgeu_ok:

# ---- b / bl / jirl ----------------------------------------------------------
    bl         call_target           # writes return address to $1
after_call:
    b          end_demo

call_target:
    addi.w     $15, $0, 1            # proves call target executed
    jirl       $16, $1, 0            # return to after_call
    addi.w     $15, $0, 2            # skipped if jirl works

end_demo:
    nop
    nop
    nop
