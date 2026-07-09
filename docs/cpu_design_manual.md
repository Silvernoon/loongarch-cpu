# LoongArch CPU 项目理解与答辩手册

这份手册面向零基础同学，目标不是把所有 Verilog 语法都讲完，而是帮助你顺着一个 CPU 从小部件到完整系统的思路，把本项目讲清楚、答清楚。

项目定位可以先记住一句话：

> 本项目实现了一颗基于 LoongArch32 基础整数指令子集的五级顺序流水 CPU，包含结构化 ALU、组合乘法器、多周期除法器、数据/控制冒险处理，以及最小直接映射 I-Cache 和 D-Cache。

---

## 1. 先理解 CPU 到底在做什么

CPU 的核心工作可以简化成一句话：

> 不断从内存取出一条指令，理解这条指令要做什么，读取需要的数据，执行运算，访问内存，最后把结果写回寄存器。

比如一条指令：

```asm
add.w r3, r1, r2
```

意思是：

```text
r3 = r1 + r2
```

CPU 做这条指令时，大致经历这些动作：

1. 取指：根据 PC 从指令存储器取出 `add.w r3, r1, r2` 的机器码。
2. 译码：控制单元识别它是加法指令。
3. 读寄存器：从寄存器堆读出 `r1` 和 `r2` 的值。
4. 执行：ALU 做加法。
5. 写回：把结果写入 `r3`。

再看一条访存指令：

```asm
ld.w r23, r22, 0
```

意思是：

```text
r23 = memory[r22 + 0]
```

它比加法多一步数据存储器访问：

1. 取指。
2. 译码。
3. 读取基址寄存器 `r22`。
4. ALU 计算地址 `r22 + 0`。
5. 数据存储器读取这个地址的数据。
6. 写回 `r23`。

这个项目的所有模块，都是围绕这些动作拆出来的。

---

## 2. 这个项目的目录怎么读

核心目录只有三个：

```text
rtl/    CPU 设计源码，真正的硬件模块都在这里
sim/    仿真文件、测试程序、期望值检查文件
tools/  简单汇编器和差分测试脚本
```

最重要的源码文件：

```text
rtl/cpu.v              CPU 顶层，把所有模块连成完整五级流水
rtl/defines.vh         指令编码、ALU 操作码、立即数类型等宏定义
rtl/control_unit.v     控制单元，负责译码
rtl/regfile.v          32 个通用寄存器
rtl/alu.v              算术逻辑单元
rtl/mult_unit.v        乘法单元
rtl/div_unit.v         多周期除法单元
rtl/imem.v             指令存储器和最小 I-Cache
rtl/dmem.v             数据存储器和最小 D-Cache
rtl/hazard_unit.v      冒险处理单元
rtl/forwarding_unit.v  前递单元
```

四个流水寄存器：

```text
rtl/if_id_reg.v
rtl/id_ex_reg.v
rtl/ex_mem_reg.v
rtl/mem_wb_reg.v
```

可以把它们理解为五级流水之间的“分隔栏”，负责把上一阶段的结果保存到下一拍，让下一阶段继续处理。

---

## 3. 从最小部件开始：1 位全加器

文件：`rtl/full_adder.v`

CPU 里最基础的算术部件是加法器。加法器又可以从 1 位全加器开始理解。

1 位全加器有三个输入：

```text
a      当前位的第一个数
b      当前位的第二个数
cin    低一位传来的进位
```

有两个输出：

```text
sum    当前位的结果
cout   传给高一位的进位
```

它实现的是：

```text
a + b + cin = cout * 2 + sum
```

例如：

```text
a=1, b=1, cin=0
1 + 1 + 0 = 2
所以 sum=0, cout=1
```

项目里的 `full_adder.v` 没有直接写 `a + b + cin`，而是用门电路原语写：

```verilog
xor  g-2(axb,  a, b);
xor  g-1(sum,  axb, cin);
and  g0(ab,   a, b);
and  g1(cxab, cin, axb);
or   g2(cout, ab, cxab);
```

答辩时可以这样讲：

> 全加器是最小算术单元。这个项目没有完全依赖 Verilog 的 `+` 运算符，而是用 `xor/and/or` 门原语搭建 1 位全加器，再把它扩展成 32 位加法器，更贴近计算机组成原理中的硬件结构。

---

## 4. 从 1 位扩展到 32 位：加法器和减法器

文件：`rtl/adder32.v`

32 位加法器就是把 32 个 1 位全加器串起来：

```text
bit0 的 cout -> bit1 的 cin
bit1 的 cout -> bit2 的 cin
...
bit31 的 cout -> 最终 cout
```

这叫行波进位加法器，因为进位像波一样从低位传到高位。

本项目的 `adder32.v` 同时支持加法和减法：

```text
sub = 0: a + b
sub = 1: a - b
```

减法如何变成加法？

计算机中使用补码：

```text
a - b = a + (~b) + 1
```

所以项目里的做法是：

```verilog
assign carry[0] = sub;
xor invert(b_x[i], b[i], sub);
```

当 `sub=0`：

```text
b_x = b
carry[0] = 0
结果是 a + b
```

当 `sub=1`：

```text
b_x = ~b
carry[0] = 1
结果是 a + ~b + 1，也就是 a - b
```

这个加法器还输出：

```text
cout      无符号进位
overflow  有符号溢出
```

这些信号后面会用于比较指令，比如 `slt`、`sltu`、分支判断。

答辩时可以这样讲：

> 32 位加减法器由 32 个全加器串联而成。减法通过对第二操作数按位取反并让最低位进位为 1 实现，也就是补码减法。这个加法器不仅用于加减法，也复用于比较、分支和除法中的试减。

---

## 5. ALU：CPU 的核心运算部件

文件：`rtl/alu.v`

ALU 是 Arithmetic Logic Unit，也就是算术逻辑单元。它负责大部分普通运算。

本项目 ALU 支持：

```text
ADD     加法
SUB     减法
SLT     有符号小于比较
SLTU    无符号小于比较
AND     按位与
OR      按位或
XOR     按位异或
NOR     按位或非
SLL     逻辑左移
SRL     逻辑右移
SRA     算术右移
PASSB   直接输出 B，用于 lu12i.w
```

### 5.1 ALU 的输入和输出

可以把 ALU 理解成一个函数：

```text
y = ALU(a, b, op)
```

其中：

```text
a   第一个操作数
b   第二个操作数
op  操作类型
y   运算结果
```

比如：

```text
a = 10
b = 20
op = ADD
y = 30
```

### 5.2 SLT 和 SLTU 怎么实现

`slt r5, r1, r2` 的意思是：

```text
如果 r1 < r2，则 r5 = 1，否则 r5 = 0
```

本项目不是直接用 `<` 运算符，而是通过一次减法判断：

```text
a - b
```

有符号比较：

```text
slt_signed = overflow ^ diff[31]
```

无符号比较：

```text
slt_unsigned = ~cout
```

这样做的好处是复用已有加减法器，符合组成原理中“比较可以由减法实现”的思想。

答辩时可以这样讲：

> ALU 不是孤立写行为逻辑，而是复用了 `adder32`、桶形移位器和门级逻辑阵列。比较指令由减法结果推导，减少了额外比较硬件。

---

## 6. 移位器：为什么不用循环一位一位移

文件：`rtl/barrel_shifter.v`

移位指令包括：

```text
sll.w    逻辑左移
srl.w    逻辑右移
sra.w    算术右移
slli.w   立即数逻辑左移
srli.w   立即数逻辑右移
srai.w   立即数算术右移
```

例如：

```asm
slli.w r11, r1, 4
```

意思是：

```text
r11 = r1 << 4
```

32 位数最多移动 31 位。项目中的桶形移位器分 5 级：

```text
第 1 级：根据 shamt[0] 决定是否移动 1 位
第 2 级：根据 shamt[1] 决定是否移动 2 位
第 3 级：根据 shamt[2] 决定是否移动 4 位
第 4 级：根据 shamt[3] 决定是否移动 8 位
第 5 级：根据 shamt[4] 决定是否移动 16 位
```

比如要左移 13 位：

```text
13 = 8 + 4 + 1
二进制是 01101
所以依次经过移动 1、4、8 位的级
```

为什么这样设计？

如果一位一位移动，硬件路径可能很长。桶形移位器用多级选择器组合出任意移位量，逻辑层数更少。

答辩时可以这样讲：

> 移位器采用五级桶形结构，每一级对应 1、2、4、8、16 位移位。这样可以用较少级数完成 0 到 31 位任意移位，比逐位移位更适合组合逻辑实现。

---

## 7. 乘法器：组合阵列乘法

文件：

```text
rtl/array_mult.v
rtl/mult_unit.v
```

乘法可以从小学竖式理解：

```text
      a
  x   b
-------
  部分积0
 部分积1
部分积2
...
```

二进制乘法更简单：

如果 `b` 的某一位是 1，就保留一份移位后的 `a`；如果是 0，这一行就是 0。

例如：

```text
a = 1011
b = 0101

b[0] = 1 -> 1011
b[1] = 0 -> 0000
b[2] = 1 -> 1011 左移 2 位
b[3] = 0 -> 0000
```

项目里的 `array_mult.v` 做了三件事：

1. 生成 32 行部分积。
2. 用全加器组成的 carry-save 结构压缩部分积。
3. 最后用 64 位行波加法得到完整乘积。

`mult_unit.v` 在外层处理有符号和无符号：

```text
mul.w     取乘积低 32 位
mulh.w    有符号乘法，取高 32 位
mulh.wu   无符号乘法，取高 32 位
```

注意：

> 当前乘法器是组合逻辑，不是多周期乘法器。

答辩时如果老师问“乘法是不是多周期”，要诚实回答：

> 不是。项目中乘法是组合阵列乘法器，单条乘法指令在 EX 阶段组合得到结果。多周期设计主要体现在除法器上。

---

## 8. 除法器：多周期恢复余数除法

文件：`rtl/div_unit.v`

除法比乘法复杂很多。本项目使用多周期恢复余数除法器。

支持：

```text
div.w    有符号除法，取商
div.wu   无符号除法，取商
mod.w    有符号除法，取余数
mod.wu   无符号除法，取余数
```

### 8.1 为什么除法要多周期

32 位除法通常需要逐位试商。每一轮大致做：

1. 余数左移，引入被除数的一位。
2. 尝试减去除数。
3. 如果够减，商的这一位为 1，保留减法结果。
4. 如果不够减，商的这一位为 0，恢复原余数。

32 位数要做 32 轮，所以适合多周期。

### 8.2 div_unit 的状态

`div_unit.v` 有几个状态：

```text
S_IDLE   空闲，等待 start
S_CALC   正在逐位计算
S_FIX    修正符号并输出结果
```

关键握手信号：

```text
start   CPU 发出开始除法的脉冲
busy    除法器正在工作
done    结果有效，持续一个周期
```

当 EX 阶段遇到除法指令时，CPU 会启动除法器。除法没完成之前，流水线必须停住，否则后面的指令会错误前进。

在 `cpu.v` 中，除法相关逻辑可以概括为：

```text
div_start = 当前 EX 是除法 && 尚未启动 && 除法器不 busy
ex_busy   = 当前 EX 是除法 && 除法尚未 done
```

`hazard_unit` 看到 `ex_busy` 后，会冻结 PC 和 IF/ID，`id_ex_reg` 也保持当前除法指令，直到除法完成。

答辩时可以这样讲：

> 除法器采用 busy/done 握手。除法指令进入 EX 后启动除法器，在 busy 期间 hazard 单元冻结流水线，防止后续指令越过还没有完成的除法。done 到来后，商或余数作为 EX 结果继续流向后续阶段。

---

## 9. 指令格式和译码

文件：

```text
rtl/defines.vh
rtl/control_unit.v
rtl/imm_gen.v
```

LoongArch32 指令都是 32 位。常见字段：

```text
rd = inst[4:0]
rj = inst[9:5]
rk = inst[14:10]
```

比如三寄存器指令：

```asm
add.w rd, rj, rk
```

表示：

```text
rd = rj + rk
```

### 9.1 control_unit 做什么

控制单元的任务是：

> 看懂机器码，并生成控制信号。

例如遇到：

```asm
add.w r3, r1, r2
```

控制单元会生成类似这样的信号：

```text
reg_write   = 1      需要写寄存器
alu_op      = ADD    ALU 做加法
alu_src_imm = 0      第二操作数来自寄存器，不是立即数
mem_read    = 0      不读内存
mem_write   = 0      不写内存
wb_sel      = ALU    写回数据来自 ALU 结果
```

遇到：

```asm
ld.w r23, r22, 0
```

控制信号变成：

```text
reg_write   = 1
alu_op      = ADD
alu_src_imm = 1      地址偏移来自立即数
mem_read    = 1
mem_write   = 0
wb_sel      = MEM    写回数据来自数据存储器
```

遇到：

```asm
st.w r16, r22, 0
```

控制信号变成：

```text
reg_write   = 0      store 不写寄存器
alu_src_imm = 1
mem_read    = 0
mem_write   = 1
```

### 9.2 imm_gen 做什么

立即数就是指令里直接带的小数字。

例如：

```asm
addi.w r1, r0, 10
```

这里的 `10` 就是立即数。

不同指令的立即数字段位置不同，所以需要 `imm_gen.v` 统一抽取并扩展：

```text
SI12    12 位有符号立即数，用于 addi、ld、st
UI12    12 位无符号立即数，用于 andi、ori、xori
SHAMT   移位量
SI20    高位立即数，用于 lu12i.w、pcaddu12i
OFF16   分支偏移
OFF26   b/bl 跳转偏移
```

答辩时可以这样讲：

> 译码阶段由 `control_unit` 识别指令类型并生成控制信号，由 `imm_gen` 根据指令格式抽取立即数。这样顶层数据通路不用关心具体指令编码，只根据控制信号选择数据来源和执行动作。

---

## 10. 寄存器堆：CPU 的小型高速数据区

文件：`rtl/regfile.v`

LoongArch32 有 32 个通用寄存器：

```text
r0 到 r31
```

本项目实现的是 32 x 32 位寄存器堆：

```text
32 个寄存器
每个寄存器 32 位
```

它有：

```text
两个读端口：同时读 rj 和 rk
一个写端口：WB 阶段写回 rd
```

### 10.1 为什么需要两个读端口

因为很多指令需要两个源操作数：

```asm
add.w r3, r1, r2
```

同一个周期要读 `r1` 和 `r2`，所以需要两个读端口。

### 10.2 r0 恒为 0

项目中规定：

```text
读 r0 永远得到 0
写 r0 被忽略
```

这是很多 RISC 架构常见设计，可以简化指令使用。

### 10.3 写优先旁路

`regfile.v` 还有一个小优化：

如果同一周期既要写某个寄存器，又要读这个寄存器，那么读端口直接返回即将写入的新值。

这模拟了经典流水线中的：

```text
前半周期写回，后半周期读寄存器
```

答辩时可以这样讲：

> 寄存器堆提供两个异步读端口和一个同步写端口，支持 r0 恒零，并实现写优先旁路，减少 WB 到 ID 的数据相关问题。

---

## 11. PC 和取指阶段

文件：

```text
rtl/pc.v
rtl/imem.v
```

PC 是 Program Counter，程序计数器。它保存当前要取的指令地址。

正常情况下：

```text
PC = PC + 4
```

为什么加 4？

因为每条 LoongArch 指令都是 32 位，也就是 4 字节。

如果遇到分支或跳转：

```text
PC = branch_target
```

如果遇到 stall：

```text
PC 保持不变
```

### 11.1 imem 和 I-Cache

`imem.v` 现在不是单纯数组读指令，而是包含一个最小直接映射 I-Cache。

它由三类信息组成：

```text
valid       这一行是否有效
tag         这一行缓存的是哪个地址范围
data        缓存的 32 位指令
```

本项目 I-Cache 的特点：

```text
直接映射
一行缓存一条 32 位指令
只读
miss 时 stall 若干周期
miss 完成后从后备指令存储器填充 cache line
```

### 11.2 I-Cache 的 hit 和 miss

当 CPU 访问地址 `addr`：

1. 先计算 cache index。
2. 读取这一行的 valid 和 tag。
3. 如果 `valid=1` 且 tag 匹配，就是 hit。
4. 否则就是 miss。

hit：

```text
马上返回指令，不停顿
```

miss：

```text
stall = 1
等待 MISS_PENALTY 周期
从后备存储器取指令
填入 cache
stall 结束
```

答辩时可以这样讲：

> I-Cache 是一字宽直接映射 cache。它展示了 cache 的基本机制：valid、tag、data、hit/miss 和 miss stall。为了控制复杂度，没有实现多字 cache line 和替换算法扩展。

---

## 12. 五级流水线：项目的主干

文件：`rtl/cpu.v`

本项目采用经典五级流水：

```text
IF   Instruction Fetch      取指
ID   Instruction Decode     译码和读寄存器
EX   Execute                执行
MEM  Memory Access          访存
WB   Write Back             写回
```

完整数据流：

```text
PC
  -> I-Cache / imem
  -> IF/ID
  -> control_unit + regfile + imm_gen
  -> ID/EX
  -> ALU / mult_unit / div_unit / branch_unit
  -> EX/MEM
  -> D-Cache / dmem
  -> MEM/WB
  -> regfile
```

### 12.1 为什么要流水线

如果不用流水线，一条指令必须完整走完所有步骤，下一条才能开始。

```text
周期1: 指令1 IF
周期2: 指令1 ID
周期3: 指令1 EX
周期4: 指令1 MEM
周期5: 指令1 WB
周期6: 指令2 IF
```

这样效率低。

流水线把不同指令放在不同阶段同时执行：

```text
周期1: 指令1 IF
周期2: 指令1 ID, 指令2 IF
周期3: 指令1 EX, 指令2 ID, 指令3 IF
周期4: 指令1 MEM, 指令2 EX, 指令3 ID, 指令4 IF
周期5: 指令1 WB, 指令2 MEM, 指令3 EX, 指令4 ID, 指令5 IF
```

理想情况下，流水线填满后每周期完成一条指令。

### 12.2 流水寄存器的作用

四个流水寄存器：

```text
IF/ID
ID/EX
EX/MEM
MEM/WB
```

它们的作用是保存每一级之间的结果。

例如 IF 阶段取到：

```text
PC
PC + 4
inst
```

这些信息会被 `if_id_reg` 保存。下一周期 ID 阶段才能稳定使用这些信息。

答辩时可以这样讲：

> 流水寄存器把组合逻辑阶段隔开，使每一级在一个时钟周期内完成自己的工作。它们还支持 stall、flush、bubble，从而配合冒险处理。

---

## 13. 数据冒险：为什么需要前递和停顿

文件：

```text
rtl/forwarding_unit.v
rtl/hazard_unit.v
```

数据冒险指的是：

> 后一条指令需要使用前一条指令还没写回的结果。

例如：

```asm
addi.w r1, r0, 10
add.w  r2, r1, r1
```

第二条指令需要 `r1`，但第一条指令的结果还没写回寄存器。如果直接从寄存器堆读，可能读到旧值。

### 13.1 前递解决 ALU 相关

前递就是不等结果写回寄存器，而是从后面流水级直接把结果送回 EX 阶段。

本项目支持：

```text
EX/MEM -> EX
MEM/WB -> EX
```

例如：

```asm
add.w r3, r1, r2
sub.w r4, r3, r5
```

`sub.w` 在 EX 阶段需要 `r3`，而 `add.w` 的结果可能还在 EX/MEM 阶段。`forwarding_unit` 检测到目标寄存器和源寄存器相同，就选择从 EX/MEM 前递。

答辩时可以这样讲：

> 前递单元比较 EX 阶段源寄存器和 MEM/WB、EX/MEM 阶段目的寄存器。如果匹配并且目标寄存器会写回，就让 EX 阶段操作数来自前递通路，而不是来自 ID/EX 保存的旧值。

### 13.2 load-use 冒险必须停顿

有一种情况前递也不够：

```asm
ld.w  r23, r22, 0
add.w r24, r23, r0
```

`ld.w` 的数据要到 MEM 阶段从数据存储器读出。紧跟着的 `add.w` 在下一周期就要进入 EX，太早了。

解决方法：

```text
停顿 1 个周期
向 ID/EX 插入一个 bubble
```

也就是让 `add.w` 等一拍，等 load 数据可以通过 MEM/WB 前递后再执行。

`hazard_unit.v` 检测条件大致是：

```text
EX 阶段指令是 load
并且它的目的寄存器等于 ID 阶段指令的源寄存器
```

触发后：

```text
stall_pc     = 1
stall_if_id  = 1
bubble_id_ex = 1
```

答辩时可以这样讲：

> ALU 结果可以前递，但 load 的数据在 MEM 阶段末才可用，紧邻的消费者无法直接前递。因此 load-use 冒险需要冻结 PC 和 IF/ID，并向 ID/EX 插入一个空泡。

---

## 14. 控制冒险：分支为什么要冲刷

文件：

```text
rtl/branch_unit.v
rtl/hazard_unit.v
rtl/pc.v
```

控制冒险来自分支和跳转。

例如：

```asm
beq r26, r27, eq_ok
addi.w r26, r0, 99
eq_ok:
addi.w r28, r0, 1
```

如果 `beq` 成立，`addi.w r26, r0, 99` 不应该执行。

但在流水线中，当分支到 EX 阶段才知道是否跳转时，后面两条指令可能已经被取入流水线。

本项目的处理：

```text
分支在 EX 阶段解析
如果 taken，则 PC 重定向到目标地址
同时 flush IF/ID 和 ID/EX
```

这意味着错误路径上的指令会被清成 NOP，不会写寄存器，也不会访问内存。

### 14.1 branch_unit 怎么判断

`branch_unit.v` 支持：

```text
BEQ     等于
BNE     不等于
BLT     有符号小于
BGE     有符号大于等于
BLTU    无符号小于
BGEU    无符号大于等于
ALWAYS  无条件跳转
```

等于比较：

```text
a - b == 0
```

小于比较复用加法器减法结果：

```text
有符号小于 = overflow ^ diff[31]
无符号小于 = ~cout
```

答辩时可以这样讲：

> 本项目不做动态分支预测。分支在 EX 阶段解析，taken 时重定向 PC，并冲刷已经进入 IF/ID 和 ID/EX 的错误路径指令。这是经典五级流水的基础控制冒险处理方式。

---

## 15. 数据存储器和 D-Cache

文件：`rtl/dmem.v`

数据存储器负责 load/store。

支持访问宽度：

```text
字节    8 位
半字    16 位
字      32 位
```

支持指令：

```text
ld.b     读字节并符号扩展
ld.bu    读字节并零扩展
ld.h     读半字并符号扩展
ld.hu    读半字并零扩展
ld.w     读字
st.b     写字节
st.h     写半字
st.w     写字
```

### 15.1 小端序

LoongArch 使用小端序。一个 32 位数据：

```text
0x12345678
```

存到地址 `0x100` 时：

```text
mem[0x100] = 0x78
mem[0x101] = 0x56
mem[0x102] = 0x34
mem[0x103] = 0x12
```

读回一个 word 时再组合成：

```text
0x12345678
```

### 15.2 符号扩展和零扩展

假设内存中一个字节是：

```text
0xFE
```

作为有符号 8 位数，它是 -2。

`ld.b` 要符号扩展：

```text
0xFFFFFFFE
```

`ld.bu` 要零扩展：

```text
0x000000FE
```

这就是 `load_unsigned` 控制信号的作用。

### 15.3 D-Cache 设计

D-Cache 也是最小直接映射：

```text
valid + tag + data
```

特点：

```text
一行一个 32 位 word
load miss 时 stall，之后从后备 byte memory 填充
store 使用 write-through
store 命中时同时更新 cache line 和后备 memory
store miss 时等待 refill，再合并写入
```

为什么使用 write-through？

因为它简单，适合课程设计：

```text
每次 store 都更新后备内存
cache 和 memory 更容易保持一致
不用 dirty bit
不用写回时机管理
```

答辩时可以这样讲：

> D-Cache 是一字宽直接映射 cache，支持 load/store 的 hit/miss/stall。store 采用 write-through，因此不需要 dirty bit，简化了一致性处理。这个 cache 主要用于展示 cache 的基本结构和流水线 stall 交互。

---

## 16. Cache miss 和流水线如何配合

文件：

```text
rtl/cpu.v
rtl/hazard_unit.v
rtl/imem.v
rtl/dmem.v
rtl/ex_mem_reg.v
rtl/mem_wb_reg.v
```

Cache miss 会让访问不能在当前周期完成，所以流水线必须停住。

本项目有两个 stall：

```text
i_stall   I-Cache miss
d_stall   D-Cache miss
```

### 16.1 I-Cache miss

I-Cache miss 发生在 IF 阶段。处理方法：

```text
冻结 PC
冻结 IF/ID
向 ID/EX 注入 bubble
```

这样做的目的是：

```text
前端等待取指完成
后面的执行阶段不会重复执行 ID 阶段那条指令
```

### 16.2 D-Cache miss

D-Cache miss 发生在 MEM 阶段。处理方法：

```text
冻结整条流水
保持 EX/MEM 不变
保持 MEM/WB 不变
```

为什么要冻结整条流水？

因为 MEM 阶段那条 load/store 指令还没完成。如果让流水继续前进，这条访存指令可能丢失，或者后面指令错误提交。

答辩时可以这样讲：

> I-Cache miss 属于前端取指停顿，主要冻结 PC 和 IF/ID，并向后端注入空泡。D-Cache miss 发生在 MEM 阶段，必须冻结整条流水，保持拥有访存请求的指令不被覆盖，直到 cache 返回数据。

---

## 17. 顶层 cpu.v 怎么把所有东西连起来

文件：`rtl/cpu.v`

可以按五级流水看 `cpu.v`：

### 17.1 IF 阶段

主要模块：

```text
pc
imem
```

输入：

```text
stall_pc
branch_taken
branch_target
```

输出：

```text
if_pc
if_pc4
if_inst
```

### 17.2 ID 阶段

主要模块：

```text
control_unit
imm_gen
regfile
```

做的事情：

```text
解析指令字段 rd/rj/rk
生成控制信号
读寄存器
生成立即数
确定目的寄存器
```

### 17.3 EX 阶段

主要模块：

```text
forwarding_unit
alu
mult_unit
div_unit
branch_unit
```

做的事情：

```text
选择前递操作数
执行 ALU 运算
执行乘法或除法
判断分支是否 taken
计算分支目标地址
```

EX 结果选择：

```text
如果是除法，选 div_y
否则如果是乘法，选 mul_y
否则选 alu_y
```

### 17.4 MEM 阶段

主要模块：

```text
dmem
```

做的事情：

```text
load 从内存读数据
store 向内存写数据
普通 ALU 指令只是把结果继续传递
```

### 17.5 WB 阶段

做的事情：

```text
从 ALU 结果、内存数据、PC+4 中选择一个写回寄存器
```

写回选择：

```text
WB_ALU   普通 ALU、乘法、除法结果
WB_MEM   load 数据
WB_PC4   bl/jirl 的链接地址
```

答辩时可以这样讲：

> `cpu.v` 是顶层数据通路。它不负责具体运算细节，而是把 PC、存储器、控制单元、寄存器堆、ALU、乘除法单元、冒险处理单元和流水寄存器连接起来，形成 IF、ID、EX、MEM、WB 五级流水。

---

## 18. 用一条指令走完整流水：add.w 示例

汇编：

```asm
addi.w r1, r0, 10
addi.w r2, r0, 20
add.w  r3, r1, r2
```

关注第三条：

```asm
add.w r3, r1, r2
```

### IF

PC 指向这条指令，I-Cache/imem 返回机器码。

```text
if_inst = add.w 的机器码
if_pc   = 当前 PC
if_pc4  = PC + 4
```

### ID

译码得到：

```text
rd = r3
rj = r1
rk = r2
alu_op = ADD
reg_write = 1
wb_sel = WB_ALU
```

寄存器堆读取：

```text
r1_data
r2_data
```

### EX

前递单元先判断 `r1`、`r2` 的最新值是否还在流水线后级。

如果前两条 `addi.w` 还没写回，前递通路会把它们的结果送入 ALU。

ALU 执行：

```text
10 + 20 = 30
```

### MEM

这不是 load/store，不访问数据存储器，只把 ALU 结果继续传递。

### WB

写回：

```text
r3 = 30
```

答辩时可以强调：

> 这个例子体现了流水线和前递的配合。`add.w` 依赖前两条 `addi.w` 的结果，但不需要停顿，因为 ALU 结果可以从后级前递到 EX。

---

## 19. 用一条 load-use 例子解释停顿

汇编：

```asm
ld.w  r23, r22, 0
add.w r24, r23, r0
```

问题：

```text
add.w 需要 r23
但 r23 是上一条 ld.w 从内存读出来的
load 数据到 MEM 阶段才可用
```

如果不停顿，`add.w` 在 EX 阶段会拿到旧的 `r23`。

项目处理：

```text
hazard_unit 检测到 load-use
stall_pc = 1
stall_if_id = 1
bubble_id_ex = 1
```

效果：

```text
ld.w 继续向 MEM 阶段前进
add.w 在 ID 阶段等一拍
中间插入一个 NOP
下一拍 add.w 再进 EX，此时 load 结果可以前递
```

答辩时可以画成：

```text
周期1: ld IF
周期2: ld ID,  add IF
周期3: ld EX,  add ID
周期4: ld MEM, add ID, bubble EX
周期5: ld WB,  add EX
```

---

## 20. 用分支例子解释 flush

汇编：

```asm
addi.w r26, r0, 5
addi.w r27, r0, 5
beq    r26, r27, eq_ok
addi.w r26, r0, 99
eq_ok:
addi.w r28, r0, 1
```

`r26 == r27`，所以分支成立。

但是在 `beq` 到 EX 阶段前，CPU 可能已经顺序取了：

```asm
addi.w r26, r0, 99
```

这条是错误路径指令，不能执行。

项目处理：

```text
branch_unit 判断 taken
pc 重定向到 eq_ok
flush_if_id = 1
flush_id_ex = 1
```

效果：

```text
错误路径指令被清成 NOP
不会写 r26
下一次取指从 eq_ok 开始
```

答辩时可以说：

> 因为项目没有做分支预测，所以默认顺序取指。分支在 EX 阶段确定 taken 后，冲刷后面已经进入流水线的错误路径指令。

---

## 21. 用 Cache 例子解释 hit/miss

假设 I-Cache 有 4 行，每行一条指令。

访问地址：

```text
0x00
```

第一次访问：

```text
valid = 0
miss
stall
从 imem 后备数组读取指令
填入 cache
```

第二次访问 `0x00`：

```text
valid = 1
tag 匹配
hit
立即返回指令
```

再访问一个映射到同一 index 的地址，比如：

```text
0x40
```

如果 index 相同但 tag 不同：

```text
冲突 miss
新指令替换旧 cache line
```

这就是直接映射 cache 的核心特点：

> 每个地址只能放到固定的一行，所以结构简单，但可能发生冲突 miss。

`sim/cache_tb.v` 专门测试了：

```text
第一次 I-Cache 访问 miss
重复访问 hit
冲突地址 miss
D-Cache 写入后 hit 读取
D-Cache 冲突后重新 refill 能恢复数据
```

---

## 22. 项目支持哪些指令

### 22.1 算术逻辑类

```text
add.w
sub.w
slt
sltu
and
or
xor
nor
addi.w
slti
sltui
andi
ori
xori
lu12i.w
pcaddu12i
```

### 22.2 移位类

```text
sll.w
srl.w
sra.w
slli.w
srli.w
srai.w
```

### 22.3 乘除类

```text
mul.w
mulh.w
mulh.wu
div.w
div.wu
mod.w
mod.wu
```

### 22.4 访存类

```text
ld.b
ld.h
ld.w
ld.bu
ld.hu
st.b
st.h
st.w
```

### 22.5 分支跳转类

```text
beq
bne
blt
bge
bltu
bgeu
b
bl
jirl
```

答辩时不要说实现了完整 LoongArch。准确说法是：

> 实现了 LoongArch32 基础整数指令子集，覆盖算术逻辑、移位、乘除、访存、条件分支和跳转链接等课程设计常用指令。

---

## 23. 仿真和验证怎么讲

重要文件：

```text
sim/cpu_tb.v        基础测试
sim/cpu_tb2.v       压力测试
sim/cache_tb.v      cache 专项测试
sim/diff_tb.v       差分测试 testbench
tools/la32.py       简易汇编器
tools/diff_test.py  LARS 差分测试驱动
```

### 23.1 基础测试

`sim/prog.s` 覆盖：

```text
基础算术
立即数
逻辑运算
移位
乘法
load/store
load-use 冒险
分支 taken/not taken
除法
bl 跳转
```

`sim/checks.vh` 中写了期望寄存器和内存结果。

### 23.2 压力测试

`sim/prog2.s` 覆盖：

```text
循环和后向分支
MULH 高位乘法
有符号/无符号除法
有符号/无符号比较
半字访存和符号扩展
```

### 23.3 Cache 测试

`sim/cache_tb.v` 覆盖：

```text
I-Cache 首次 miss
I-Cache 重复 hit
I-Cache 直接映射冲突
D-Cache load miss
D-Cache store hit
D-Cache 冲突后 refill
```

### 23.4 差分测试

`tools/diff_test.py` 的思路：

1. 同一份汇编程序先交给 LARS 模拟器运行，得到标准寄存器和内存结果。
2. 再用本项目 CPU 跑同一程序。
3. 比较 32 个寄存器和指定内存范围。
4. 如果一致，说明 CPU 功能行为和参考模型一致。

答辩时可以这样讲：

> 验证分为三层：定向 testbench 检查基础功能，cache_tb 检查 cache hit/miss/stall，diff_test 则把 LARS 作为功能参考，对寄存器和内存最终状态进行差分比对。

---

## 24. 答辩时最容易被问的问题

### 问题 1：你的 CPU 是单周期、多周期还是流水线？

回答：

> 是五级顺序流水 CPU。整体采用 IF、ID、EX、MEM、WB 五级流水。除法单元内部是多周期的，除法执行时会冻结流水线。乘法是组合阵列乘法器，不是多周期。

### 问题 2：为什么 load-use 要停顿？

回答：

> 因为 load 的数据要到 MEM 阶段才从数据存储器出来，而紧跟的下一条指令在下一周期就会进入 EX 阶段使用这个值。这个时间点数据还不可用，所以必须停顿一拍并插入 bubble。

### 问题 3：前递解决了什么？

回答：

> 前递解决 ALU 指令之间的数据相关。当前一条指令的结果还没写回寄存器，但已经在 EX/MEM 或 MEM/WB 阶段时，可以直接送回 EX 阶段作为操作数，避免不必要停顿。

### 问题 4：分支怎么处理？

回答：

> 分支在 EX 阶段解析。如果判断 taken，就把 PC 重定向到目标地址，同时 flush IF/ID 和 ID/EX 中的错误路径指令。项目没有实现动态分支预测。

### 问题 5：Cache 是什么结构？

回答：

> I-Cache 和 D-Cache 都是最小直接映射 cache，一行一个 32 位 word。每行包含 valid、tag、data。miss 时通过 stall 暂停流水，等待固定 MISS_PENALTY 周期后从后备存储填充。

### 问题 6：D-Cache 的 store 怎么处理？

回答：

> 使用 write-through。store 时同步更新后备内存，命中时也更新 cache line。这样不需要 dirty bit，逻辑更简单，适合课程设计展示。

### 问题 7：为什么没有乱序和多发射？

回答：

> 本项目定位是基础五级顺序流水 CPU，重点是完整实现数据通路、控制、乘除法、冒险处理和 cache 机制。乱序和多发射需要寄存器重命名、保留站、ROB、提交逻辑等复杂结构，超出当前课程设计主线，可以作为后续扩展方向。

### 问题 8：你的除法器如何保证有符号结果正确？

回答：

> 除法开始时先根据操作数符号转换为绝对值做无符号逐位除法，最后根据商和余数应有的符号进行修正。商向零截断，余数符号跟随被除数。

### 问题 9：为什么 r0 永远是 0？

回答：

> 这是 RISC 架构常见设计。硬件上读 r0 直接返回 0，写 r0 被忽略。这样可以简化很多指令，比如用 `addi.w r1, r0, 10` 实现加载小立即数。

### 问题 10：如何证明项目能正确运行？

回答：

> 通过多个仿真程序验证。`cpu_tb` 检查基础指令、访存、分支和除法；`cpu_tb2` 检查循环、MULH、符号扩展和有/无符号除法；`cache_tb` 检查 cache hit/miss/stall；另外差分测试脚本可以和 LARS 参考模拟器比较最终寄存器和内存状态。

---

## 25. 答辩讲解顺序建议

答辩时不要一上来讲代码细节，推荐按这个顺序：

### 第一步：一句话介绍项目

> 我们实现的是一颗 LoongArch32 基础整数子集的五级顺序流水 CPU，支持算术逻辑、移位、乘除法、访存、分支跳转、数据/控制冒险处理，以及最小直接映射 I-Cache 和 D-Cache。

### 第二步：讲总体结构

按五级流水讲：

```text
IF:  PC + I-Cache/imem
ID:  control_unit + regfile + imm_gen
EX:  ALU + mult_unit + div_unit + branch_unit
MEM: D-Cache/dmem
WB:  写回寄存器
```

### 第三步：讲一个普通指令如何执行

用：

```asm
add.w r3, r1, r2
```

说明取指、译码、读寄存器、ALU 加法、写回。

### 第四步：讲冒险处理

按三个点：

```text
数据冒险：前递
load-use：停顿加 bubble
控制冒险：分支 taken 后 flush
```

### 第五步：讲乘除法

```text
乘法：组合阵列乘法器
除法：多周期恢复余数除法器，busy/done 握手
```

### 第六步：讲 Cache

```text
直接映射
valid/tag/data
hit/miss
miss stall
D-Cache write-through
```

### 第七步：讲验证

```text
基础测试
压力测试
Cache 专项测试
LARS 差分测试
```

---

## 26. 可以画在报告里的图

### 26.1 总体数据通路图

```text
              branch_target
                   ^
                   |
+----+       +-----------+      +----------+      +----------+      +----------+
| PC | ----> | I-Cache   | ---> | IF/ID    | ---> | ID/EX    | ---> | EX/MEM   |
+----+       | imem      |      +----------+      +----------+      +----------+
  ^          +-----------+            |                 |                 |
  |                                   v                 v                 v
  |                              +---------+       +-----------+      +----------+
  |                              | Control |       | ALU/MUL   |      | D-Cache |
  |                              | RegFile |       | DIV/BR    |      | dmem    |
  |                              | ImmGen  |       +-----------+      +----------+
  |                              +---------+                              |
  |                                                                       v
  |                                                               +-------------+
  +---------------------------------------------------------------| MEM/WB      |
                                                                  +-------------+
                                                                         |
                                                                         v
                                                                      RegFile
```

### 26.2 五级流水示意

```text
Cycle 1: I1 IF
Cycle 2: I1 ID   I2 IF
Cycle 3: I1 EX   I2 ID   I3 IF
Cycle 4: I1 MEM  I2 EX   I3 ID   I4 IF
Cycle 5: I1 WB   I2 MEM  I3 EX   I4 ID   I5 IF
```

### 26.3 Cache line 结构

```text
+-------+------+----------+
| valid | tag  | data     |
+-------+------+----------+
| 1 bit | addr | 32 bits  |
+-------+------+----------+
```

---

## 27. 项目的边界和不足要主动说清楚

主动说明边界反而更显得可靠。

当前已经实现：

```text
五级顺序流水
LoongArch32 基础整数子集
结构化 ALU
组合乘法
多周期除法
前递
load-use stall
分支 flush
最小 I-Cache / D-Cache
仿真和差分测试框架
```

没有实现：

```text
乱序执行
多发射
动态分支预测
完整异常/中断
完整 LoongArch 指令集
多级 cache
write-back cache
虚拟内存
```

答辩时可以这样说：

> 本项目没有追求复杂处理器的全部特性，而是围绕计组课程重点，把五级流水、控制信号、运算部件、冒险处理、乘除法和基础 cache 机制做完整，并通过仿真验证功能正确性。

---

## 28. 最后速记版

如果只剩 1 分钟准备答辩，记住这段：

> 这个项目是一颗 LoongArch32 基础整数子集的五级流水 CPU。取指阶段由 PC 和 I-Cache/imem 完成，译码阶段由 control_unit 产生控制信号并从 regfile 读操作数，执行阶段由 ALU、乘法器、除法器和分支单元完成运算，访存阶段通过 D-Cache/dmem 处理 load/store，写回阶段把 ALU、内存或 PC+4 的结果写回寄存器。数据冒险通过 EX/MEM、MEM/WB 前递解决，load-use 通过停顿和 bubble 解决，分支在 EX 阶段解析并 flush 错误路径。乘法是组合阵列乘法，除法是 busy/done 握手的多周期恢复余数除法。Cache 是最小直接映射结构，包含 valid、tag、data，miss 时通过 stall 暂停流水。项目通过基础测试、压力测试、Cache 专项测试和 LARS 差分测试验证。
