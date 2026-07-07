// =============================================================================
// diff_tb.v  —  differential-test harness testbench for the LA32 core
//
// Runs the CPU on a program image and dumps the final architectural state
// (all 32 GPRs + a configurable data-memory window) to a plain-text file the
// Python driver (tools/diff_test.py) diffs against the LARS golden model.
//
// Everything is overridable from the command line via +plusargs so one compiled
// image serves every test program:
//
//   vvp diff_tb.vvp +HEX=sim/prog.hex +CYCLES=300 \
//                   +DUMP=sim/state.txt +MEMLO=0x100 +MEMHI=0x108
//
// RESET_VECTOR defaults to 0x3000 so the PC base matches LARS's
// CompactDataAtZero text base (0x00003000); this makes the link register
// written by bl/jirl compare by plain equality.  imem masks the low word bits
// so the image still loads and fetches from word 0.
// =============================================================================
`timescale 1ns / 1ps

module diff_tb;
    reg clk = 0, rst_n = 0;
    wire [31:0] dbg_pc, dbg_wb_data;
    wire        dbg_wb_we;
    wire [4:0]  dbg_wb_rd;

    // ---- runtime configuration (plusargs, with defaults) ------------------
    reg [1023:0] hex_file;
    reg [1023:0] dump_file;
    integer      cycles;
    integer      mem_lo, mem_hi;

    // INIT_FILE must be known at elaboration for $readmemh in imem, so the
    // image path is fixed by a parameter the driver overrides with -P.
    parameter    INIT_FILE    = "sim/prog.hex";
    parameter [31:0] RESET_VECTOR = 32'h0000_3000;

    cpu #(.INIT_FILE(INIT_FILE), .RESET_VECTOR(RESET_VECTOR)) dut(
        .clk(clk), .rst_n(rst_n),
        .dbg_pc(dbg_pc), .dbg_wb_we(dbg_wb_we),
        .dbg_wb_rd(dbg_wb_rd), .dbg_wb_data(dbg_wb_data)
    );

    always #5 clk = ~clk;

    integer fd, i, a;
    reg [31:0] word;

    initial begin
        // defaults
        cycles    = 4000;
        mem_lo    = 0;
        mem_hi    = 0;
        dump_file = "sim/state.txt";
        if (!$value$plusargs("CYCLES=%d", cycles)) cycles = 4000;
        if (!$value$plusargs("MEMLO=%h", mem_lo))  mem_lo = 0;
        if (!$value$plusargs("MEMHI=%h", mem_hi))  mem_hi = 0;
        void'($value$plusargs("DUMP=%s", dump_file));

        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (cycles) @(posedge clk);

        fd = $fopen(dump_file, "w");
        if (fd == 0) begin
            $display("ERROR: cannot open dump file");
            $finish;
        end

        // ---- register file ------------------------------------------------
        for (i = 0; i < 32; i = i + 1) begin
            if (i == 0) $fwrite(fd, "r%0d %08x\n", i, 32'd0);
            else        $fwrite(fd, "r%0d %08x\n", i, dut.u_rf.regs[i]);
        end

        // ---- data memory window (word granularity, little-endian) ---------
        // mem_hi is exclusive; a==mem_hi is not dumped, matching a [lo,hi) range.
        a = mem_lo;
        while (a < mem_hi) begin
            word = {dut.u_dmem.mem[a+3], dut.u_dmem.mem[a+2],
                    dut.u_dmem.mem[a+1], dut.u_dmem.mem[a]};
            $fwrite(fd, "m%08x %08x\n", a, word);
            a = a + 4;
        end

        $fclose(fd);
        $display("diff_tb: state written to %0s (%0d cycles)", dump_file, cycles);
        $finish;
    end

    // safety net
    initial begin
        #500000;
        $display("ERROR: diff_tb timeout");
        $finish;
    end
endmodule
