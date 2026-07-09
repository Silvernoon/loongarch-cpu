# 关于指令

## 指令支持机制:一条指令流过五级要哪些"开关"

 支持一条指令 = 让译码器给它配好一组控制信号,数据通路里的 mux/enable 早已铺好。没有微码、没有查找表 ROM,纯组合逻辑硬连线。三个文件协作:

### defines.vh — opcode 字典

 底部从 GNU binutils(loongarch-opc.c)逐条抄来的真实 match/mask 对。每类指令一个 mask:

- 3R 类 MASK_3R = 0xffff8000(高 17 位是 opcode)
- 2RI12 0xffc00000、1RI20 0xfe000000、2RI16/I26 0xfc000000

### control_unit.v — 译码即"配开关"(纯组合)

 机制是 mask-then-match:

 ```verilog
   wire [31:0] m3r = inst & `MASK_3R;   // 抠出 opcode 位
   ...
   if (m3r == `OP_ADD_W) begin reg_write=1; alu_op=`ALU_ADD; end
 ```

 先 set_defaults 把全部信号打到安全默认(不写寄存器、不访存、不跳转),
 再由匹配到的那一条 else if 覆盖它需要的信号。
 产出约 20 个控制信号:
 reg_write / wb_sel / alu_op / alu_src_imm /
 imm_sel / mem_* / is_branch / br_cond /
 use_mul / use_div / rd_is_src / link_r1 ...

 没匹配上 → illegal=1(NOP 也走这条,无害)。

 关键点:第 149–153 行的 reads_rj/reads_rk 不是重新译码,
 而是从已产出的控制信号推导出来,保证与译码结果永不矛盾 —— 这是给 hazard/forwarding 用的源寄存器占用信息。

### imm_gen.v — 立即数抽取/扩展

 按 imm_sel 选 6 种格式之一:
 SI12 符号扩展、UI12 零扩展、SHAMT、SI20({i20,12'b0})、OFF16/OFF26(符号扩展后 <<2)。

 要加一条新指令,只需三步:
 在 defines.vh 加 match/mask → 在 control_unit.v 加一条 else if 配信号
 → (若新立即数格式)在 imm_gen.v 加一个 case。

 数据通路本身通常不用动。

## 已支持的指令(共 40 条,LA32 基础整数集)

| 类别 | 指令 | 机制要点 |
| --------------- | --------------- | --------------- |
| 3R 算术/逻辑 | add.w sub.w slt sltu and or xor nor | ALU 单周期,SLT/SLTU 复用减法器推导 |
| 3R 移位 | sll.w srl.w sra.w | 桶形移位器 |
| 3R 乘 | mul.w mulh.w mulh.wu | 阵列乘法器,高/低字 + 有无符号选择 |
| 3R 除/模 | div.w div.wu mod.w mod.wu | 恢复余数除法器,多周期(约 34 周期),busy/done 握手停顿流水 |
| 2RI5 移位立即 | slli.w srli.w srai.w | shamt = inst\[14:10\] |
| 2RI12 算术立即 | addi.w slti sltui | si12 符号扩展 |
| 2RI12 逻辑立即 | andi ori xori | ui12 零扩展 |
| 2RI12 load | ld.w ld.h ld.b ld.hu ld.bu | 地址=rj+si12,dmem 按宽度符号/零扩展 |
| 2RI12 store | st.w st.h st.b | rd_is_src=1,rd 提供存储数据 |
| 1RI20 | lu12i.w pcaddu12i | lu12i 走 ALU_PASSB;pcaddu12i 走 alu_src_pc 用 PC 做加数 |
| 2RI16 条件分支 | beq bne blt bge bltu bgeu | 比较 rj vs rd,EX 解析,冲刷两条错误取指 |
| 2RI16 寄存器跳转 | jirl | rd=PC+4,目标=rj+off16<<2 |
| I26 无条件 | b bl | bl 链接返回地址到 r1(link_r1) |
| 伪指令 | nop | = andi r0,r0,0,归入 illegal 但无副作用 |
