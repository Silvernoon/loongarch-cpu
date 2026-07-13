# `dome_short` CPU 仿真波形阅读指南

> 适用工程：`D:\loongarch-cpu`  
> 测试程序：`D:\loongarch-cpu\sim\dome_short.s`  
> Vivado 测试平台：`D:\loongarch-cpu\sim\dome_short_tb.v`  
> 波形分组脚本：`D:\loongarch-cpu\sim\dome_short_wave_setup.tcl`

## 1. 这几个测试文件分别是什么

| 文件 | 作用 |
|---|---|
| `sim/dome_short.s` | 在 LARS 中打开、汇编和单步执行的源程序 |
| `sim/dome_short.hex` | Vivado 指令存储器实际读取的十六进制机器码 |
| `sim/dome_short.bin` | 每行一条32位二进制机器码，用于查看和答辩展示；它是文本文件，不是原始二进制字节流 |
| `sim/dome_short_listing.txt` | 给人看的“地址—机器码—汇编指令”对照表，不参与仿真 |
| `sim/dome_short_tb.v` | CPU测试平台，指定程序文件、复位地址和仿真时长 |
| `sim/dome_short_wave_setup.tcl` | 每次启动行为仿真时动态创建六个波形分组 |
| `sim/dome_short_cpu_state.txt` | Vivado仿真结束后导出的寄存器和数据存储器状态 |
| `sim/dome_short_lars_state.txt` | LARS执行结束后导出的寄存器和数据存储器状态 |

Vivado实际使用的配置位于 `sim/dome_short_tb.v`：

```verilog
cpu #(
    .INIT_FILE("sim/dome_short.hex"),
    .RESET_VECTOR(32'h0000_3000)
) dut (
```

因此，Vivado第一条指令的架构地址是 `0x00003000`。

当前 `dome_short.hex` 和 `dome_short_listing.txt` 都有34条指令，机器码逐条一致。

---

## 2. 先理解波形窗口的三部分

Vivado波形窗口通常有三部分：

1. **Name（名称）**：信号名，例如 `x_pc`、`alu_a`。
2. **Value（当前值）**：黄色时间光标所在位置的信号值。
3. **Wave（波形）**：信号随时间变化的图形。

读图时不能只看整条波形，必须先把黄色时间光标放到某个明确时刻，再查看Value列。

建议把下列数值信号显示为十六进制：

- `if_pc`、`id_pc`、`x_pc`
- `if_inst`、`id_inst`
- `alu_a`、`alu_b`、`alu_y`
- `dbg_wb_data`、`wb_data`
- 地址、数据、寄存器和存储器内容

单比特控制信号，例如 `stall`、`hit`、`miss`、`branch_taken`，保持二进制显示即可。

---

## 3. 六个波形分组分别看什么

### 3.1 `top_debug`

主要信号：

- `clk`：时钟
- `rst_n`：低电平复位
- `dbg_pc`：当前取指PC，本项目中等于 `if_pc`
- `dbg_wb_we`：是否写回寄存器
- `dbg_wb_rd`：写回的寄存器编号
- `dbg_wb_data`：写回数据

用途：快速确认CPU是否运行、PC是否前进、寄存器是否发生写回。

注意：

```verilog
assign dbg_pc = if_pc;
```

所以 `dbg_pc` 不是写回阶段PC。不能把同一时刻的 `dbg_pc` 和 `dbg_wb_data` 当成同一条指令。

### 3.2 `pipeline_internal`

这是最重要的分组，主要用于观察流水线：

- `if_pc + if_inst`：取指阶段
- `id_pc + id_inst`：译码阶段
- `x_pc`：执行阶段指令地址
- `x_alu_op`：ALU操作编号
- `alu_a + alu_b + alu_y`：ALU两个输入和输出
- `ex_result`：执行阶段最终结果
- `branch_taken + branch_target`：跳转是否成立以及目标地址
- `ex_busy + div_busy + div_done`：除法等多周期执行状态
- `stall_pc + stall_if_id`：流水线暂停
- `flush_if_id + flush_id_ex`：分支跳转后的流水线清空
- `m_alu_result + m_store_data + m_load_data`：访存阶段
- `wb_reg_write + wb_rd + wb_data`：写回阶段

### 3.3 `register_file`

主要信号：

```text
/dome_short_tb/dut/u_rf/regs
```

展开后可以看到 `regs[0]` 到 `regs[31]`。

用途：观察通用寄存器最终值，或观察某个寄存器在写回沿之后是否改变。

### 3.4 `data_memory`

主要信号：

```text
/dome_short_tb/dut/u_dmem/mem
```

这是数据存储器字节数组。当前测试重点观察：

- `mem[0x300]`～`mem[0x303]`：组成32位字 `0x7abcd123`
- `mem[0x304]`：值为 `0xf0`

### 3.5 `instruction_memory_cache`

用于观察指令存储器和I-Cache：

- `addr`：CPU请求的取指地址
- `inst`：返回的机器码
- `stall`：I-Cache是否要求CPU暂停
- `hit`：命中
- `miss`：未命中
- `busy`：正在处理未命中
- `miss_count`：未命中等待周期计数
- `word_index`、`index`、`tag`：地址拆分结果
- `cache_data`、`cache_tag`、`cache_valid`：Cache内部数组
- `mem`：指令存储器内容

### 3.6 `data_memory_cache`

用于观察访存指令和D-Cache：

- `addr`：数据访问地址
- `we`：写使能
- `re`：读使能
- `width`：字节、半字或字访问宽度
- `load_unsigned`：加载是否零扩展
- `wdata`：写入数据
- `rdata`：读取数据
- `stall`：D-Cache暂停请求
- `hit`、`miss`、`busy`：命中、未命中和填充状态
- `byte_off`：字节偏移
- `fill_word`：Cache填充的数据
- `store_word`：写操作合并后的数据

---

## 4. 看流水线最重要的规则

同一时刻，CPU可以同时处理多条指令：

```text
IF：正在取第N条指令
ID：正在译码第N-1条指令
EX：正在执行第N-2条指令
MEM：正在访存第N-3条指令
WB：正在写回第N-4条指令
```

因此，不能把同一竖线上的所有信号都认为属于同一条指令。

正确对应关系：

| 想检查的内容 | 应该使用的信号 |
|---|---|
| 取出的机器码是否正确 | `if_pc + if_inst` |
| 当前译码的是哪条指令 | `id_pc + id_inst` |
| ALU正在执行哪条指令 | `x_pc + alu_a + alu_b + alu_y` |
| 是否发生分支跳转 | `x_pc + branch_taken + branch_target` |
| 访存地址和数据 | `m_alu_result`以及D-Cache信号 |
| 寄存器写回 | `dbg_wb_we + dbg_wb_rd + dbg_wb_data` |

**核心口诀：**

> 看机器码用 `if_pc`，看译码用 `id_pc`，看ALU用 `x_pc`，看结果提交用 `dbg_wb_*`。

---

## 5. 完整示例：怎样看 `add.w`

汇编和机器码对照：

```text
00003010  00100c44  add.w $4, $2, $3
```

前面已经执行：

```text
r2 = 10 = 0x0000000a
r3 = 20 = 0x00000014
```

因此预期：

```text
r4 = r2 + r3 = 30 = 0x0000001e
```

### 5.1 约195ns：取指

```text
if_pc   = 00003010
if_inst = 00100c44
```

说明CPU正确取出了 `add.w` 的机器码。

### 5.2 约235ns：译码

```text
if_pc   = 00003014
id_pc   = 00003010
x_pc    = 0000300c
alu_a   = 00000000
alu_b   = 00000014
alu_y   = 00000014
```

这时 `id_pc` 虽然是 `0x3010`，但ALU属于 `x_pc=0x300c` 的上一条指令：

```asm
addi.w $3, $0, 20
```

所以ALU执行的是 `0 + 20 = 20`，并不是 `add.w` 算错。

### 5.3 约275ns：执行

```text
x_pc  = 00003010
alu_a = 0000000a
alu_b = 00000014
alu_y = 0000001e
```

这才是 `add.w` 真正的执行时刻：

```text
10 + 20 = 30
```

### 5.4 约295ns：写回

```text
dbg_wb_we   = 1
dbg_wb_rd   = 4
dbg_wb_data = 0000001e
```

说明结果30被写入 `r4`。

答辩时可以按以下顺序说明：

1. `if_pc=0x3010` 时取到机器码 `0x00100c44`。
2. 指令经过译码后进入执行级。
3. `x_pc=0x3010` 时，ALU输入为10和20，输出为30。
4. 随后写回使能有效，目标寄存器为4，写回数据为30。

---

## 6. `x_alu_op=0` 不代表ALU结果是0

`x_alu_op` 是操作编号，不是计算结果。

`rtl/defines.vh` 中的主要编号：

| `x_alu_op` | 操作 |
|---:|---|
| 0 | ADD |
| 1 | SUB |
| 2 | SLT |
| 4 | AND |
| 5 | OR |
| 6 | XOR |
| 8 | SLL |
| 9 | SRL |
| 10 | SRA |
| 11 | MUL |
| 14 | DIV |
| 16 | MOD |
| 18 | PASSB，用于 `lu12i.w` |

因此：

```text
x_alu_op = 0
```

表示选择加法功能，不表示 `alu_y=0`。

真正结果必须看：

```text
alu_y
```

---

## 7. 地址为什么看起来对不上

### 7.1 架构PC与指令存储器数组下标不同

指令存储器使用：

```verilog
word_index = addr >> 2;
```

当前存储器深度为1024个word，实际使用 `word_index` 的低10位。

对于地址 `0x3010`：

```text
(0x3010 - 0x3000) / 4 = 4
```

所以：

```text
架构地址0x3000 -> u_imem.mem[0]
架构地址0x3004 -> u_imem.mem[1]
架构地址0x3010 -> u_imem.mem[4]
架构地址0x3084 -> u_imem.mem[33]
```

当前实际内容：

```text
u_imem.mem[0]  = 14f579b8
u_imem.mem[4]  = 00100c44
u_imem.mem[33] = 03400000
```

它们分别对应listing中的第一条、第五条和最后一条指令。

### 7.2 `dbg_pc`与写回结果不是同一阶段

本项目：

```text
dbg_pc = if_pc
```

当 `add.w` 写回 `r4=30` 时，取指阶段可能已经到 `0x3018`。这不是地址错误，而是流水线并行执行的正常现象。

### 7.3 Cache暂停后PC不会每个周期都加4

当I-Cache出现未命中时：

```text
miss = 1
stall = 1
```

PC和流水线寄存器会保持若干周期。因此不能按照“每10ns地址一定加4”机械推算。

### 7.4 分支会让PC跳转、重复或跳过

本程序的重要控制流：

```text
beq  0x3054 -> 0x305c，跳过0x3058
bne  0x3064 -> 0x3060，循环一次
bl   0x3068 -> 0x3070，同时r1=0x306c
jirl 0x3074 -> 0x306c，同时r22=0x3078
b    0x306c -> 0x307c，跳过0x3078
```

因此PC不一定一直顺序增加。

---

## 8. 怎样看普通算术、逻辑和移位指令

以执行阶段为准：

1. 在 `dome_short_listing.txt` 中找到指令地址。
2. 在波形中寻找 `x_pc` 等于该地址的时刻。
3. 查看 `alu_a`、`alu_b`、`alu_y`。
4. 向后寻找 `dbg_wb_we=1` 且 `dbg_wb_rd` 等于目标寄存器。
5. 检查 `dbg_wb_data` 是否等于预期结果。

代表性预期结果：

| 地址 | 指令 | 预期结果 |
|---|---|---|
| `0x3010` | `add.w $4,$2,$3` | `r4=30` |
| `0x3014` | `sub.w $5,$3,$2` | `r5=10` |
| `0x3018` | `slt $6,$2,$3` | `r6=1` |
| `0x301c` | `xor $7,$2,$3` | `r7=30` |
| `0x3020` | `slli.w $8,$2,2` | `r8=40` |
| `0x3028` | `srai.w $10,$9,2` | `r10=0xfffffffc`，即-4 |

---

## 9. 怎样看乘法、除法和取余

### 9.1 乘法

```asm
mul.w $12, $2, $3
```

预期：

```text
10 × 20 = 200 = 0x000000c8
```

寻找：

```text
x_pc = 0x302c
```

观察 `ex_result`，随后观察：

```text
dbg_wb_rd   = 12
dbg_wb_data = 000000c8
```

### 9.2 除法

```asm
div.w $13, $12, $2
```

预期：

```text
200 / 10 = 20
```

重点观察：

- `x_pc=0x3030`
- `ex_busy`
- `div_busy`
- `div_done`
- `stall_pc`
- `stall_if_id`

除法是多周期操作。正常现象是：

1. `div_busy` 拉高。
2. PC和前级流水线暂停。
3. 除法完成时 `div_done` 有效。
4. 最终写回 `r13=20`。

### 9.3 取余

```asm
mod.w $14, $12, $3
```

预期：

```text
200 % 20 = 0
```

最终应看到：

```text
dbg_wb_rd   = 14
dbg_wb_data = 00000000
```

这里结果0是正确结果，不是没有执行。

---

## 10. 怎样看加载、存储和D-Cache

测试程序使用的数据地址基址：

```text
r15 = 0x00000300
```

### 10.1 `st.w`

```asm
st.w $24, $15, 0
```

预期向 `0x300` 存入：

```text
0x7abcd123
```

在 `data_memory_cache` 中观察：

```text
addr  = 00000300
we    = 1
wdata = 7abcd123
```

第一次访问可能发生D-Cache miss，因此还可能看到：

```text
miss = 1
busy = 1
stall = 1
```

### 10.2 `ld.w`

```asm
ld.w $16, $15, 0
```

预期：

```text
r16 = 0x7abcd123
```

观察：

```text
addr  = 00000300
re    = 1
rdata = 7abcd123
```

然后观察写回：

```text
dbg_wb_rd   = 16
dbg_wb_data = 7abcd123
```

### 10.3 load-use暂停

紧接着执行：

```asm
add.w $17, $16, $0
```

由于它立即使用上一条 `ld.w` 的结果，可能出现load-use冒险。重点观察：

```text
stall_pc
stall_if_id
flush_id_ex
```

最终：

```text
r17 = 0x7abcd123
```

### 10.4 有符号和无符号字节加载

```asm
st.b  $9,  $15, 4
ld.b  $18, $15, 4
ld.bu $19, $15, 4
```

写入的低字节是：

```text
0xf0
```

预期：

```text
ld.b  ：r18 = 0xfffffff0，有符号扩展
ld.bu ：r19 = 0x000000f0，零扩展
```

---

## 11. 怎样看分支和跳转

判断分支时，以 `x_pc` 为准，同时观察：

```text
branch_taken
branch_target
flush_if_id
flush_id_ex
```

### 11.1 `beq`

```asm
0x3054: beq $4, $7, beq_ok
```

此时：

```text
r4 = 30
r7 = 30
```

预期：

```text
branch_taken  = 1
branch_target = 0000305c
```

地址 `0x3058` 是错误路径，不应提交写回。

### 11.2 `bne`循环

```asm
0x3060: addi.w $20,$20,-1
0x3064: bne $20,$0,loop
```

过程：

1. `r20` 从2减到1，`bne`成立，跳回 `0x3060`。
2. `r20` 从1减到0，`bne`不成立，继续执行 `0x3068`。

波形中会看到 `x_pc=0x3060` 和 `x_pc=0x3064` 重复出现。

### 11.3 `bl`和`jirl`

```asm
0x3068: bl call_target
0x3070: addi.w $21,$0,1
0x3074: jirl $22,$1,0
```

预期：

```text
bl目标地址       = 0x3070
r1返回地址       = 0x306c
jirl目标地址     = r1 = 0x306c
r22保存返回地址  = 0x3078
```

随后 `0x306c` 的无条件分支跳到 `0x307c`，所以 `0x3078` 的错误路径不应提交，最终 `r21=1`。

---

## 12. 怎样看寄存器数组

展开：

```text
register_file
└── regs
```

如果数组无法完全展开，也可以主要使用写回信号：

```text
dbg_wb_we
dbg_wb_rd
dbg_wb_data
```

在时钟上升沿附近：

- `dbg_wb_we=1`：本周期会写寄存器。
- `dbg_wb_rd`：目标寄存器编号。
- `dbg_wb_data`：写入数据。

`r0`恒为0，即使某条指令尝试写入，也不应改变。

---

## 13. 怎样看数据存储器数组

D-Cache中的 `mem` 是字节数组，所以32位字由连续4个字节组成。

例如地址 `0x300` 的32位小端字：

```text
word = {mem[0x303], mem[0x302], mem[0x301], mem[0x300]}
```

最终应组合得到：

```text
0x7abcd123
```

地址 `0x304` 的低字节最终是：

```text
0xf0
```

不要把单个 `mem[0x300]` 误认为完整的32位数据。

---

## 14. 为什么仿真结束时ALU和地址看起来不对

测试平台复位结束后继续运行600个时钟：

```verilog
repeat (600) @(posedge clk);
```

这是为了给Cache miss、除法和分支循环留出足够时间。

程序最后一条listing地址是：

```text
0x00003084
```

CPU没有自动停止机制，执行完最后一条后会继续从后续地址读取默认 `nop`。

当前仿真结束附近可能看到：

```text
if_pc = 0x00003210
id_pc = 0x0000320c
x_pc  = 0x00000000
alu_a = 0
alu_b = 0
alu_y = 0
```

这是程序已经执行完成后的空闲/默认指令状态，不表示前面的指令执行错误。

检查前面指令时，应缩放到对应时间段，不要只看仿真结束时刻。

---

## 15. 最终结果检查表

Vivado和LARS当前导出的最终状态一致：

| 寄存器 | 预期值 | 含义 |
|---|---:|---|
| `r1` | `0000306c` | `bl`保存的返回地址 |
| `r2` | `0000000a` | 10 |
| `r3` | `00000014` | 20 |
| `r4` | `0000001e` | 10+20=30 |
| `r5` | `0000000a` | 20-10=10 |
| `r6` | `00000001` | 10<20 |
| `r7` | `0000001e` | 10 xor 20=30 |
| `r8` | `00000028` | 10左移2位=40 |
| `r9` | `fffffff0` | -16 |
| `r10` | `fffffffc` | -16算术右移2位=-4 |
| `r12` | `000000c8` | 10×20=200 |
| `r13` | `00000014` | 200/10=20 |
| `r14` | `00000000` | 200%20=0 |
| `r15` | `00000300` | 数据区基地址 |
| `r16` | `7abcd123` | `ld.w`结果 |
| `r17` | `7abcd123` | load-use后的结果 |
| `r18` | `fffffff0` | `ld.b`符号扩展 |
| `r19` | `000000f0` | `ld.bu`零扩展 |
| `r20` | `00000000` | 循环结束 |
| `r21` | `00000001` | 函数体执行，错误路径未提交 |
| `r22` | `00003078` | `jirl`保存的返回地址 |
| `r24` | `7abcd123` | `lu12i.w + ori`结果 |

数据存储器：

```text
m00000300 = 7abcd123
m00000304 = 000000f0
m00000308 = 00000000
```

对应文件：

```text
D:\loongarch-cpu\sim\dome_short_cpu_state.txt
D:\loongarch-cpu\sim\dome_short_lars_state.txt
```

---

## 16. 答辩时推荐的演示顺序

### 第一步：证明程序一致

打开：

```text
sim/dome_short.s
sim/dome_short.bin
sim/dome_short_listing.txt
```

说明LARS执行的汇编程序和Vivado加载的机器码来自同一份程序。

### 第二步：证明取指正确

在波形中找到：

```text
if_pc   = 0x3010
if_inst = 0x00100c44
```

在listing中指出它对应：

```asm
add.w $4,$2,$3
```

### 第三步：证明ALU正确

找到：

```text
x_pc  = 0x3010
alu_a = 10
alu_b = 20
alu_y = 30
```

### 第四步：证明写回正确

找到：

```text
dbg_wb_we   = 1
dbg_wb_rd   = 4
dbg_wb_data = 30
```

### 第五步：展示复杂功能

依次展示：

1. 除法多周期暂停：`div_busy`、`div_done`。
2. D-Cache miss和hit：`miss`、`hit`、`stall`。
3. load-use暂停：`stall_pc`、`stall_if_id`。
4. 分支跳转与清空：`branch_taken`、`branch_target`、`flush_if_id`、`flush_id_ex`。
5. 最终寄存器和数据存储器值。

---

## 17. 常见误读速查

| 看到的现象 | 实际原因 |
|---|---|
| `id_pc=0x3010`，但ALU不是10+20 | ALU属于 `x_pc`，不能用 `id_pc` 对照 |
| `x_alu_op=0` | 0代表ADD操作，不是结果为0 |
| 写回30时 `dbg_pc` 已经是0x3018 | `dbg_pc=if_pc`，与写回阶段不是同一条指令 |
| PC连续几个周期不变 | Cache miss、除法或冒险导致stall |
| PC重复出现0x3060和0x3064 | `bne`循环正常执行 |
| PC跳过0x3058 | `beq`成立，错误路径被清除 |
| `mem[4]`中是0x3010的指令 | `mem[4]`是数组下标，0x3010是架构地址 |
| 仿真末尾PC超过0x3084 | CPU执行完程序后继续取默认nop |
| 仿真末尾ALU为0 | 已经进入默认nop或流水线气泡，不代表前面计算错误 |
| `mod.w`写回0 | 200%20本来就等于0 |

---

## 18. 一句话读图法

每次检查一条指令，都按照下面四步：

```text
1. 用 if_pc + if_inst 确认取指
2. 用 x_pc 确认当前执行的是哪条指令
3. 用 alu_a、alu_b、alu_y 或访存信号检查运算过程
4. 用 dbg_wb_we、dbg_wb_rd、dbg_wb_data 检查最终提交结果
```

不要把不同流水级在同一时刻的信号当成同一条指令。
