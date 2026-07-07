#!/usr/bin/env python3
"""
diff_test.py — differential tester: LARS (golden) vs the Verilog LA32 core.

Takes a LoongArch32 assembly program written in this CPU's register dialect
(`rN` operands, the same one `la32.py` and `sim/*.s` already use), then:

  1. translates `rN` -> `$N` and runs it on LARS (../LARS/Lars.jar) under the
     CompactDataAtZero memory map, capturing the final 32 GPRs (+ a data window);
  2. assembles the same source with la32.py into the CPU's hex image;
  3. builds and runs the Verilog core (sim/diff_tb.v), capturing the same state;
  4. compares register-by-register (and word-by-word over the data window).

LARS is the reference; a mismatch is reported as a CPU bug.  Register numbers
are identical between the two worlds (both are LoongArch r0..r31), and the CPU
PC base is set to LARS's text base (0x3000) so the bl/jirl link register
compares by plain equality.

Usage:
    python3 tools/diff_test.py sim/prog.s
    python3 tools/diff_test.py sim/prog.s --mem 0x100 0x108
    python3 tools/diff_test.py sim/prog.s --cycles 600 --mem 0x100 0x110
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
LARS = os.environ.get("LARS_DIR", os.path.join(os.path.dirname(REPO), "LARS"))
LARS_JAR = os.path.join(LARS, "Lars.jar")

# LARS CompactDataAtZero text base; keep in sync with diff_tb.v RESET_VECTOR.
TEXT_BASE = 0x3000

GREEN = "\033[32m"
RED = "\033[31m"
DIM = "\033[2m"
RST = "\033[0m"


def translate_to_lars(src: str) -> str:
    """CPU dialect (rN) -> LARS dialect ($N).  Register numbers are identical."""
    out = []
    for line in src.splitlines():
        code, _, comment = line.partition("#")
        code = re.sub(r"\br(\d+)\b", r"$\1", code)
        out.append(code + ("#" + comment if comment else ""))
    return "\n".join(out)


def run_lars(asm_path: str, cycles: int, mem):
    """Run LARS; return (regs dict {n:val}, mem dict {addr:word})."""
    args = ["java", "-jar", "Lars.jar", "nc", "hex",
            "mc", "CompactDataAtZero", str(max(cycles, 100000))]
    args += [f"${i}" for i in range(32)]
    if mem:
        lo, hi = mem
        # LARS memory range is inclusive; step back one word so [lo,hi) matches.
        args.append(f"0x{lo:x}-0x{max(lo, hi - 4):x}")
    args.append(asm_path)
    r = subprocess.run(args, cwd=LARS, capture_output=True, text=True)

    regs, memout = {}, {}
    # The real register dump is the final block; LARS also echoes debug copies,
    # so walk backwards and stop when a register number repeats (one full set).
    reg_lines = [l for l in r.stdout.splitlines()
                 if re.match(r"^\$\d+\t0x[0-9a-fA-F]+$", l)]
    for l in reversed(reg_lines):
        m = re.match(r"^\$(\d+)\t0x([0-9a-fA-F]+)$", l)
        n = int(m.group(1))
        if n in regs:
            break
        regs[n] = int(m.group(2), 16) & 0xFFFFFFFF

    for l in r.stdout.splitlines():
        m = re.match(r"^Mem\[0x([0-9a-fA-F]+)\]\t(.*)$", l)
        if m:
            base = int(m.group(1), 16)
            words = re.findall(r"0x([0-9a-fA-F]+)", m.group(2))
            for i, w in enumerate(words):
                memout[base + 4 * i] = int(w, 16) & 0xFFFFFFFF

    if len(regs) != 32:
        errs = [l for l in r.stdout.splitlines() if "Error" in l or "exception" in l]
        raise RuntimeError(
            f"LARS produced {len(regs)}/32 registers.\n"
            + "\n".join(errs[-5:] or r.stdout.splitlines()[-5:]))
    return regs, memout


def run_cpu(hex_path: str, cycles: int, mem):
    """Build+run the Verilog core; return (regs dict, mem dict)."""
    rtl = [os.path.join(REPO, "rtl", f)
           for f in os.listdir(os.path.join(REPO, "rtl")) if f.endswith(".v")]
    vvp = os.path.join(REPO, "sim", "diff.vvp")
    build = subprocess.run(
        ["iverilog", "-g2012", "-I", "rtl", "-I", "sim",
         "-P", f"diff_tb.INIT_FILE=\"{hex_path}\"",
         "-o", vvp, "-s", "diff_tb"] + rtl + [os.path.join(REPO, "sim", "diff_tb.v")],
        cwd=REPO, capture_output=True, text=True)
    if build.returncode != 0:
        raise RuntimeError("iverilog build failed:\n" + build.stderr)

    dump = os.path.join(REPO, "sim", "state.txt")
    plus = [f"+CYCLES={cycles}", f"+DUMP={dump}"]
    if mem:
        plus += [f"+MEMLO={mem[0]:x}", f"+MEMHI={mem[1]:x}"]
    run = subprocess.run(["vvp", vvp] + plus, cwd=REPO, capture_output=True, text=True)

    regs, memout = {}, {}
    with open(dump) as f:
        for line in f:
            m = re.match(r"^r(\d+)\s+([0-9a-fA-F]+)$", line)
            if m:
                regs[int(m.group(1))] = int(m.group(2), 16) & 0xFFFFFFFF
                continue
            m = re.match(r"^m([0-9a-fA-F]+)\s+([0-9a-fA-F]+)$", line)
            if m:
                memout[int(m.group(1), 16)] = int(m.group(2), 16) & 0xFFFFFFFF
    return regs, memout


def main():
    ap = argparse.ArgumentParser(description="LARS-vs-CPU differential tester")
    ap.add_argument("src", help="assembly source in rN dialect (e.g. sim/prog.s)")
    ap.add_argument("--cycles", type=int, default=600,
                    help="CPU simulation cycles (default 600)")
    ap.add_argument("--mem", nargs=2, metavar=("LO", "HI"),
                    help="data window [LO,HI) to compare, e.g. --mem 0x100 0x110")
    ap.add_argument("-v", "--verbose", action="store_true",
                    help="print every register, not just mismatches")
    args = ap.parse_args()

    if not os.path.exists(LARS_JAR):
        sys.exit(f"LARS not found at {LARS_JAR} (set LARS_DIR)")

    mem = None
    if args.mem:
        mem = (int(args.mem[0], 0), int(args.mem[1], 0))

    src = open(args.src).read()

    # 1. LARS golden
    lars_asm = os.path.join(REPO, "sim", "_lars_tmp.asm")
    open(lars_asm, "w").write(translate_to_lars(src))
    lars_regs, lars_mem = run_lars(lars_asm, args.cycles, mem)

    # 2. CPU image via la32.py
    hexpath = os.path.join(REPO, "sim", "_diff_tmp.hex")
    asm = subprocess.run(["python3", "tools/la32.py", "asm", args.src],
                         cwd=REPO, capture_output=True, text=True)
    if asm.returncode != 0:
        sys.exit("la32.py assembly failed:\n" + asm.stderr)
    open(hexpath, "w").write(asm.stdout)

    # 3. CPU state
    cpu_regs, cpu_mem = run_cpu(hexpath, args.cycles, mem)

    # 4. compare
    print(f"{DIM}LARS (golden)  vs  Verilog CPU   —  {os.path.basename(args.src)}{RST}")
    fails = 0
    for i in range(32):
        lv, cv = lars_regs[i], cpu_regs[i]
        ok = lv == cv
        if not ok:
            fails += 1
        if args.verbose or not ok:
            tag = f"{GREEN}ok  {RST}" if ok else f"{RED}DIFF{RST}"
            print(f"  {tag} r{i:<2} lars={lv:#010x} cpu={cv:#010x}")

    for a in sorted(lars_mem):
        if a not in cpu_mem:
            continue
        lv, cv = lars_mem[a], cpu_mem[a]
        ok = lv == cv
        if not ok:
            fails += 1
        if args.verbose or not ok:
            tag = f"{GREEN}ok  {RST}" if ok else f"{RED}DIFF{RST}"
            print(f"  {tag} mem[{a:#06x}] lars={lv:#010x} cpu={cv:#010x}")

    print("-" * 48)
    if fails == 0:
        print(f"{GREEN}PASS{RST}  32 regs"
              + (f" + {len(lars_mem)} words" if lars_mem else "")
              + " match LARS")
        return 0
    print(f"{RED}FAIL{RST}  {fails} mismatch(es) vs LARS")
    return 1


if __name__ == "__main__":
    sys.exit(main())
