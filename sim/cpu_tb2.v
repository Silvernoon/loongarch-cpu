// =============================================================================
// cpu_tb.v  —  top-level testbench for the LA32 pipelined core
//
// Loads sim/prog2.hex into instruction memory, runs the pipeline for enough
// cycles to drain, then checks the architectural register file and a data
// memory location against values computed by an independent Python model.
// =============================================================================
`timescale 1ns / 1ps

module cpu_tb2;
    reg clk = 0, rst_n = 0;
    wire [31:0] dbg_pc, dbg_wb_data;
    wire        dbg_wb_we;
    wire [4:0]  dbg_wb_rd;

    integer errors = 0;

    cpu #(.INIT_FILE("sim/prog2.hex")) dut(
        .clk(clk), .rst_n(rst_n),
        .dbg_pc(dbg_pc), .dbg_wb_we(dbg_wb_we),
        .dbg_wb_rd(dbg_wb_rd), .dbg_wb_data(dbg_wb_data)
    );

    always #5 clk = ~clk;

    task check;
        input [4:0]  idx;
        input [31:0] expv;
        reg   [31:0] got;
        begin
            got = dut.u_rf.regs[idx];
            if (idx == 5'd0) got = 32'd0;
            if (got !== expv) begin
                $display("FAIL r%0d = 0x%08x, expected 0x%08x", idx, got, expv);
                errors = errors + 1;
            end else
                $display("ok   r%0d = 0x%08x", idx, got);
        end
    endtask

    task check_mem;
        input [31:0] addr;
        input [31:0] expv;
        reg   [31:0] got;
        begin
            got = {dut.u_dmem.mem[addr+3], dut.u_dmem.mem[addr+2],
                   dut.u_dmem.mem[addr+1], dut.u_dmem.mem[addr]};
            if (got !== expv) begin
                $display("FAIL mem[0x%08x] = 0x%08x, expected 0x%08x", addr, got, expv);
                errors = errors + 1;
            end else
                $display("ok   mem[0x%08x] = 0x%08x", addr, got);
        end
    endtask

    task check_mem_h;
        input [31:0] addr;
        input [15:0] expv;
        reg   [15:0] got;
        begin
            got = {dut.u_dmem.mem[addr+1], dut.u_dmem.mem[addr]};
            if (got !== expv) begin
                $display("FAIL mem_h[0x%08x] = 0x%04x, expected 0x%04x", addr, got, expv);
                errors = errors + 1;
            end else
                $display("ok   mem_h[0x%08x] = 0x%04x", addr, got);
        end
    endtask

    initial begin
        $dumpfile("sim/cpu2.vcd");
        $dumpvars(0, cpu_tb2);

        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // run long enough to execute + drain (divides take ~34 cycles each)
        repeat (300) @(posedge clk);

        $display("========================================");
        $display("Register / memory checks");
        $display("========================================");
`include "checks2.vh"

        $display("========================================");
        if (errors == 0) $display("ALL CHECKS PASSED");
        else             $display("%0d CHECK(S) FAILED", errors);
        $display("========================================");
        $finish;
    end

    initial begin
        #100000;
        $display("ERROR: timeout");
        $finish;
    end
endmodule
