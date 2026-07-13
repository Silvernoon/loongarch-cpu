// =============================================================================
// dome_short_tb.v -- ?????? Vivado/XSim testbench
// =============================================================================
`timescale 1ns / 1ps

module dome_short_tb;
    reg clk = 0, rst_n = 0;
    wire [31:0] dbg_pc, dbg_wb_data;
    wire        dbg_wb_we;
    wire [4:0]  dbg_wb_rd;

    integer fd, i, a;
    reg [31:0] word;

    cpu #(
        .INIT_FILE("sim/dome_short.hex"),
        .RESET_VECTOR(32'h0000_3000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .dbg_pc(dbg_pc),
        .dbg_wb_we(dbg_wb_we),
        .dbg_wb_rd(dbg_wb_rd),
        .dbg_wb_data(dbg_wb_data)
    );

    always #5 clk = ~clk;

    initial begin
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;

        // ?????????Cache miss ???????????????????
        repeat (600) @(posedge clk);

        // XSim uses a deep project run directory in GUI mode, while the
        // standalone command-line run starts at the repository root.
        // Try both layouts so the same testbench works in both environments.
        fd = $fopen("sim/dome_short_cpu_state.txt", "w");
        if (fd == 0) fd = $fopen("../sim/dome_short_cpu_state.txt", "w");
        if (fd == 0) fd = $fopen("../../sim/dome_short_cpu_state.txt", "w");
        if (fd == 0) fd = $fopen("../../../sim/dome_short_cpu_state.txt", "w");
        if (fd == 0) fd = $fopen("../../../../sim/dome_short_cpu_state.txt", "w");
        if (fd == 0) fd = $fopen("../../../../../sim/dome_short_cpu_state.txt", "w");
        if (fd == 0) begin
            $display("ERROR: cannot open dome_short_cpu_state.txt");
            $finish;
        end

        for (i = 0; i < 32; i = i + 1) begin
            if (i == 0) $fwrite(fd, "r%0d %08x\n", i, 32'd0);
            else        $fwrite(fd, "r%0d %08x\n", i, dut.u_rf.regs[i]);
        end

        for (a = 32'h300; a < 32'h30c; a = a + 4) begin
            word = {dut.u_dmem.mem[a+3], dut.u_dmem.mem[a+2],
                    dut.u_dmem.mem[a+1], dut.u_dmem.mem[a]};
            $fwrite(fd, "m%08x %08x\n", a, word);
        end

        $fclose(fd);
        $display("DOME_SHORT_DONE state=sim/dome_short_cpu_state.txt");
        $finish;
    end

    initial begin
        #100000;
        $display("ERROR: dome_short_tb timeout");
        $finish;
    end
endmodule
