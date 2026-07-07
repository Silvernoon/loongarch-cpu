# =============================================================================
# LoongArch32 pipelined CPU — build / simulation
#
# Requires Icarus Verilog (iverilog + vvp).  Install on Arch: pacman -S iverilog
#
#   make            # build + run the base regression
#   make stress     # build + run the second (stress) program
#   make diff       # differential-test prog.s + prog2.s against LARS (golden)
#   make wave       # open the last VCD in gtkwave
#   make clean
# =============================================================================
IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
FLAGS    := -g2012 -I rtl -I sim

RTL := $(wildcard rtl/*.v)

.PHONY: all test stress diff diff-base diff-stress wave clean

all: test

test: sim/prog.hex
	$(IVERILOG) $(FLAGS) -o sim/cpu.vvp -s cpu_tb $(RTL) sim/cpu_tb.v
	$(VVP) sim/cpu.vvp

stress: sim/prog2.hex
	$(IVERILOG) $(FLAGS) -o sim/cpu2.vvp -s cpu_tb2 $(RTL) sim/cpu_tb2.v
	$(VVP) sim/cpu2.vvp

# ---- differential testing against LARS (golden reference) -------------------
# tools/diff_test.py translates rN->$N, runs LARS + the core, and diffs the
# final architectural state.  Set LARS_DIR if LARS is not at ../LARS.
diff: diff-base diff-stress diff-cover

diff-base:
	$(PYTHON) tools/diff_test.py sim/prog.s --mem 0x100 0x108

diff-stress:
	$(PYTHON) tools/diff_test.py sim/prog2.s --mem 0x200 0x204

diff-cover:
	$(PYTHON) tools/diff_test.py sim/prog3.s --mem 0x300 0x30c

wave:
	gtkwave sim/cpu.vcd &

clean:
	rm -f sim/*.vvp sim/*.vcd
