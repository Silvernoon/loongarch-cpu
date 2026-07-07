// =============================================================================
// regfile.v  —  LoongArch 32x32 general-purpose register file
//
// Two asynchronous read ports (rj, rk) and one synchronous write port, as
// drawn in the datapath ("Dual-port Register File", ports A0/A1 read, AW write).
//   - r0 is hardwired to zero: writes to it are dropped, reads return 0.
//   - Write-first bypass: a read in the same cycle as a write to the same
//     register returns the new value.  This lets the classic "write in first
//     half, read in second half" pipeline resolve WB->ID without a stall.
// =============================================================================
`timescale 1ns / 1ps

module regfile(
    input  wire        clk,
    input  wire        rst_n,
    // read port A (rj)
    input  wire [4:0]  ra_addr,
    output wire [31:0] ra_data,
    // read port B (rk / rd for stores)
    input  wire [4:0]  rb_addr,
    output wire [31:0] rb_data,
    // write port (rd)
    input  wire        we,
    input  wire [4:0]  wa_addr,
    input  wire [31:0] wa_data
);
    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (we && wa_addr != 5'd0) begin
            regs[wa_addr] <= wa_data;
        end
    end

    // r0 reads as zero; write-first bypass on port collisions.
    wire a_is_wr = we && (wa_addr != 5'd0) && (wa_addr == ra_addr);
    wire b_is_wr = we && (wa_addr != 5'd0) && (wa_addr == rb_addr);

    assign ra_data = (ra_addr == 5'd0) ? 32'd0 :
                     a_is_wr           ? wa_data : regs[ra_addr];
    assign rb_data = (rb_addr == 5'd0) ? 32'd0 :
                     b_is_wr           ? wa_data : regs[rb_addr];
endmodule
