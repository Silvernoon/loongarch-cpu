// =============================================================================
// if_id_reg.v  —  IF/ID pipeline register
//
// Latches the fetched instruction and its PC for the decode stage.
//   stall : hold current contents (load-use / divide bubble upstream)
//   flush : replace with a NOP bubble (branch mispredict / squash)
// flush dominates stall.  The bubble instruction is andi r0,r0,0 (a true NOP)
// so the decoder produces an all-zero control set.
// =============================================================================
`timescale 1ns / 1ps

module if_id_reg(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] pc_in,
    input  wire [31:0] pc4_in,
    input  wire [31:0] inst_in,
    output reg  [31:0] pc_out,
    output reg  [31:0] pc4_out,
    output reg  [31:0] inst_out
);
    localparam [31:0] NOP = 32'h03400000;   // andi r0,r0,0

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out   <= 32'd0;
            pc4_out  <= 32'd0;
            inst_out <= NOP;
        end else if (flush) begin
            pc_out   <= 32'd0;
            pc4_out  <= 32'd0;
            inst_out <= NOP;
        end else if (!stall) begin
            pc_out   <= pc_in;
            pc4_out  <= pc4_in;
            inst_out <= inst_in;
        end
        // stall && !flush : hold
    end
endmodule
