// =============================================================================
// cache_tb.v  --  directed cache smoke test for the CPU memory models
//
// The test checks three externally visible behaviours:
//   1. I-cache can find sim/prog.hex from Vivado/XSim's generated run directory.
//   2. First access to an invalid direct-mapped line stalls, then hits.
//   3. D-cache preserves data through a direct-mapped conflict by refilling from
//      the backing byte memory.
// =============================================================================
`timescale 1ns / 1ps
`include "defines.vh"

module cache_tb;
    reg clk = 0;
    reg rst_n = 0;
    integer errors = 0;
    integer n;

    always #5 clk = ~clk;

    reg  [31:0] iaddr = 32'd0;
    wire [31:0] inst;
    wire        istall;

    imem #(
        .WORDS(1024),
        .INIT_FILE("sim/prog.hex"),
        .LINES(4),
        .MISS_PENALTY(2)
    ) u_imem (
        .clk(clk),
        .rst_n(rst_n),
        .addr(iaddr),
        .inst(inst),
        .stall(istall)
    );

    reg  [31:0] daddr = 32'h0000_0020;
    reg         dwe = 1'b0;
    reg         dre = 1'b0;
    reg  [1:0]  dwidth = `MEM_W;
    reg         dunsigned = 1'b0;
    reg  [31:0] dwdata = 32'd0;
    wire [31:0] drdata;
    wire        dstall;

    dmem #(
        .BYTES(4096),
        .LINES(4),
        .MISS_PENALTY(2)
    ) u_dmem (
        .clk(clk),
        .rst_n(rst_n),
        .addr(daddr),
        .we(dwe),
        .re(dre),
        .width(dwidth),
        .load_unsigned(dunsigned),
        .wdata(dwdata),
        .rdata(drdata),
        .stall(dstall)
    );

    task fail;
        input [8*96-1:0] msg;
        begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    task wait_istall_clear;
        begin
            for (n = 0; n < 20 && istall; n = n + 1) begin
                @(posedge clk);
                #1;
            end
            if (istall) fail("I-cache did not clear miss stall");
        end
    endtask

    task wait_dstall_clear;
        begin
            for (n = 0; n < 20 && dstall; n = n + 1) begin
                @(posedge clk);
                #1;
            end
            if (dstall) fail("D-cache did not clear miss stall");
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        #1;

        if (istall !== 1'b1)
            fail("first I-cache access should miss");
        wait_istall_clear();
        if (inst !== 32'h02802801)
            fail("I-cache did not load first instruction from sim/prog.hex");

        iaddr = 32'h0000_0000;
        #1;
        if (istall !== 1'b0)
            fail("repeated I-cache access should hit");

        iaddr = 32'h0000_0040;
        #1;
        if (istall !== 1'b1)
            fail("conflicting I-cache line should miss");
        wait_istall_clear();

        dre = 1'b1;
        daddr = 32'h0000_0020;
        #1;
        if (dstall !== 1'b1)
            fail("first D-cache load should miss");
        wait_dstall_clear();
        if (drdata !== 32'h0000_0000)
            fail("fresh D-cache backing memory should read zero");

        dre = 1'b0;
        dwe = 1'b1;
        dwdata = 32'hdead_beef;
        daddr = 32'h0000_0020;
        #1;
        if (dstall !== 1'b0)
            fail("D-cache store to resident line should hit");
        @(posedge clk);
        #1;

        dwe = 1'b0;
        dre = 1'b1;
        #1;
        if (dstall !== 1'b0 || drdata !== 32'hdead_beef)
            fail("D-cache hit load should return stored word");

        daddr = 32'h0000_0030;
        #1;
        if (dstall !== 1'b1)
            fail("D-cache conflicting line should miss");
        wait_dstall_clear();

        daddr = 32'h0000_0020;
        #1;
        if (dstall !== 1'b1)
            fail("D-cache evicted line should miss on revisit");
        wait_dstall_clear();
        if (drdata !== 32'hdead_beef)
            fail("D-cache refill should recover word from backing memory");

        if (errors == 0) begin
            $display("ALL CACHE CHECKS PASSED");
        end else begin
            $display("%0d CACHE CHECK(S) FAILED", errors);
        end
        $finish;
    end

    initial begin
        #100000;
        $display("ERROR: cache_tb timeout");
        $finish;
    end
endmodule
