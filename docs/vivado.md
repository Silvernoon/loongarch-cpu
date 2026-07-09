# Vivado

diff_tb 靠命令行参数配置,xsim 里对应关系:

- INIT_FILE(hex 镜像路径)、RESET_VECTOR 是 parameter
→ 用 -generic_top 传,或直接改 diff_tb.v 第 34–35 行默认值。先手动生成 hex:

  ```sh
     python3 tools/la32.py asm sim/prog.s > sim/prog.hex
  ```

- CYCLES/MEMLO/MEMHI/DUMP 是 +plusargs → xsim 用 -testplusarg 传:

  ```bash
     xsim ... -testplusarg CYCLES=600 -testplusarg MEMLO=100 -testplusarg MEMHI=108
  ```

   (注意 MEMLO/MEMHI 用 %h 读,给纯 16 进制数字不带 0x)

 Vivado GUI 里最省事的做法:
 把 diff_tb 设为仿真顶层,在 Simulation Settings
 → `xsim.simulate.xsim.more_options` 填 `-testplusarg CYCLES=600 -testplusarg MEMLO=100 -testplusarg MEMHI=108`,
 generic 在 xsim.elaborate.xelab.more_options 填 `-generic_top "INIT_FILE=sim/prog.hex"`。
 跑完 xsim 会生成 state.txt。

但 Vivado 侧没有自动比对 —— diff_test.py 的比对逻辑是纯 Python,不依赖 iverilog。
所以即使你在 Vivado 里跑,最实用的比对方式仍是让 diff_test.py 那步产出 LARS 金标准,
再拿你 Vivado 生成的 state.txt 跟它对。
