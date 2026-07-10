# LoongArch

所有指令为32位

寄存器操作数域从低位（第 0 bit）开始依次排列，操作码（opcode）从高位（第 31 bit）开始排列，立即数域位于寄存器域与操作码之间。

## ALU 算术逻辑单元

IAM 整数(浮点)矩阵乘法器

加（减）乘除

逻辑运算

移位

## 运行

使用经典5步流水

- 取指IF
- 译码ID/寄存器取值RF
- 执行EX
- 访存MA
- 写回WB

##

使用哈佛结构存储器（现代常用改进型哈佛）

## CU 控制单元

读指令，指挥其他部件运作

## PC程序计数器

指向内存正在执行的指令

## DP 内部总线

各部件通过DP交换数据

## REG 寄存器

## BUS 系统总线

CPU通过BUS与外部模块交流

---

## 实现 (rtl/)

基于 README 的规格，实现了一颗 **LoongArch32 基础整数指令集** 的五级流水 CPU。
每个模块单独一个文件，尽量贴近物理结构：算术单元由门级/全加器组合而成，
而不是直接用 `*` `/` `+` 让综合器推断黑盒。

### 物理运算单元（替换原行为级 ALU）

| 文件               | 说明                                                                                |
| ------------------ | ----------------------------------------------------------------------------------- |
| `full_adder.v`     | 1 位全加器，纯 `and/or/xor` 门原语                                                  |
| `adder32.v`        | 32 位行波进位加/减法器，由 32 个全加器串联；导出进位与有符号溢出                    |
| `barrel_shifter.v` | 对数桶形移位器（1/2/4/8/16 五级 mux），支持 SLL/SRL/SRA                             |
| `array_mult.v`     | 32×32 阵列乘法器：AND 阵列生成部分积 + 进位保存树 + 末级行波加                      |
| `mult_unit.v`      | 有/无符号选择与高低字选择（MUL/MULH/MULH.WU），符号靠取反处理                       |
| `div_unit.v`       | 32 位恢复余数除法器，逐位迭代（多周期），有/无符号，商向零截断                      |
| `alu.v`            | 单周期组合 ALU，组合上面的加法器、桶形移位器与逻辑门阵列；SLT/SLTU 由同一次减法推导 |

### 数据通路与流水线

| 文件                                | 阶段  | 说明                                             |
| ----------------------------------- | ----- | ------------------------------------------------ |
| `pc.v`                              | IF    | 程序计数器 + PC 加法器，支持重定向/停顿          |
| `imem.v`                            | IF    | 哈佛结构指令存储 + 最小直接映射 I-Cache（`$readmemh` 载入程序） |
| `control_unit.v`                    | ID    | CU 译码，产生所有控制信号（操作码取自 binutils） |
| `imm_gen.v`                         | ID    | 各指令格式立即数抽取与扩展                       |
| `regfile.v`                         | ID/WB | 双端口寄存器堆，r0 恒零，写优先旁路              |
| `branch_unit.v`                     | EX    | 分支条件判定（复用减法器做比较）                 |
| `forwarding_unit.v`                 | EX    | EX/MEM、MEM/WB → EX 前递                         |
| `hazard_unit.v`                     | —     | load-use 停顿、分支冲刷、除法多周期停顿          |
| `dmem.v`                            | MA    | 字节/半字/字访存 + 最小直接映射 D-Cache，带符号/零扩展 |
| `{if_id,id_ex,ex_mem,mem_wb}_reg.v` | —     | 四个流水寄存器，支持停顿/冒泡/冲刷               |
| `cpu.v`                             | —     | 顶层，按数据通路图连接五级流水                   |

分支/跳转在 EX 解析，随后冲刷两条错误取指。除法在 EX 用 busy/done 握手停顿流水。
I-Cache miss 会冻结取指/译码前端并向 EX 注入气泡，D-Cache miss 会冻结整条流水，
保证 MEM 阶段访存指令不会丢失。

### 最小 Cache

`imem.v` 和 `dmem.v` 现在都包含一个一字宽 cache line 的直接映射 Cache：

- I-Cache：只读，`valid + tag + data`，miss 后等待 `MISS_PENALTY` 周期并从指令后备存储填充。
- D-Cache：`valid + tag + data`，支持字节/半字/字 load/store；store 采用 write-through，并同步更新命中的 cache line。
- Cache 的目标是期末设计展示用的基础 hit/miss/stall 机制，不实现多字 cache line、dirty/write-back、替换策略扩展或异常处理。
- `sim/cache_tb.v` 专门检查首次 miss、重复 hit、直接映射冲突、D-Cache refill，以及 Vivado/XSim 目录下 `sim/prog.hex` 的自动查找。

### 构建与仿真

需要 Icarus Verilog。

```sh
make          # 编译并运行基础回归（33 项寄存器/访存检查）
make stress   # 运行第二个压力程序（循环、MULH、有/无符号除法、访存符号扩展）
```

两个测试程序（`sim/prog.s`、`sim/prog2.s`）的期望值固化在
`sim/checks.vh`、`sim/checks2.vh` 中，`make` 运行时逐寄存器比对。
用 `tools/la32.py` 可重新汇编生成 `.hex` 镜像。

Vivado 2019.1 下已验证：

- `sources_1` / `sim_1` 语法检查通过。
- `cache_tb`、`cpu_tb`、`cpu_tb2` 行为仿真均为 `errors=0`。
- 当前工程器件 `xc7vx485tffg1157-1` 在本机没有 Synthesis license；换用免费器件尝试完整综合时，结构化 32x32 阵列乘法器展开耗时很长，因此本项目以 Vivado 语法检查和行为仿真作为当前交付证据。

### 差分测试：以 LARS 为标准

除了 `tools/la32.py` 这个轻量参考模型，本项目还接入了 **LARS**
（LoongArch Assembler and Runtime Simulator，MARS 的龙芯移植版，`../LARS`）
作为**功能标准**，对 CPU 做差分测试：同一份汇编源程序分别在 LARS 和
Verilog 核上运行，逐寄存器 + 逐字比对最终体系结构状态。LARS 的结果为准，
不一致即视为 CPU 缺陷。

需要 `java`、`iverilog`/`vvp`、`python3`，且 LARS 位于 `../LARS`
（或用环境变量 `LARS_DIR` 指定）。

```sh
make diff          # 三个程序全部对拍
make diff-base     # 仅 prog.s
make diff-stress   # 仅 prog2.s
make diff-cover    # 仅 prog3.s（覆盖全部指令类别）
```

也可以直接调用驱动脚本对任意程序对拍：

```sh
python3 tools/diff_test.py <程序.s> [--mem LO HI] [--cycles N] [-v]
# 例：
python3 tools/diff_test.py sim/prog3.s --mem 0x300 0x30c -v
```

- 程序用 CPU 的 `rN` 寄存器写法（与 `sim/*.s`、`la32.py` 一致），
  驱动脚本自动把 `rN` 翻译成 LARS 的 `$N`（寄存器编号相同）。
- `--mem LO HI` 按字比对数据存储器区间 `[LO, HI)`；省略则只比寄存器。
- `--cycles N` 为长程序延长仿真周期（除法每次约 34 周期，默认 600）。
- `-v` 打印全部 32 个寄存器，否则只列出不一致项。

#### 实现要点

- **内存映射对齐**：LARS 用 `CompactDataAtZero` 配置（数据段基址 0、
  文本段基址 `0x3000`）。测试平台 `sim/diff_tb.v` 把 CPU 的 `RESET_VECTOR`
  设为 `0x3000`，使 `bl`/`jirl` 写入的返回地址与 LARS 完全相等，
  从而全部按值直接比对，无需偏移换算。数据段两边都从 0 起址，天然对齐。
- **功能与机器码双重对齐**：本机 `D:/LARS/Lars.jar` 已修正原版 LARS 中
  `addi.w` 与 `sltui` 误用同一编码、分支标签按 `PC+4` 计算偏移的问题。配合
  `CompactDataAtZero` 后，LARS 文本段从 `0x3000` 开始；`sim/demo_all.s` 导出的
  65 个机器字与 `sim/demo_all.hex` 逐字一致（差异数为 0），最终 32 个寄存器状态
  也与 Vivado/XSim 一致。原版 JAR 保存在 `D:/LARS/Lars.jar.bak-*`。
- **`lu12i.w` 立即数范围**：LARS 按有符号 20 位做边界检查
  （`-0x80000..0x7ffff`），而 `la32.py` 直接截断。共享源程序须落在有符号范围内，
  `prog3.s` 的高位立即数据此选取。
