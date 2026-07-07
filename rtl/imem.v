// =============================================================================
// imem.v  —  Harvard instruction memory / I-Cache model (read-only in core)
//
// Combinational fetch: address in, 32-bit instruction out, matching the "one
// instruction per cycle" front-end.  Word-addressed (pc[..2] indexes words).
// Program is loaded from a hex file via $readmemh into the array; if the path
// is empty the memory starts as all-NOP-ish zero (decoded as illegal, treated
// as bubble by the pipeline).
//
// This is a synchronous-storage / async-read model appropriate for a
// single-cycle IF stage in simulation; a real design would pipeline the SRAM.
// =============================================================================
`timescale 1ns / 1ps

module imem #(
    parameter WORDS = 1024,              // 4 KiB instruction store
    parameter INIT_FILE = ""
)(
    input  wire [31:0] addr,             // byte address (PC)
    output wire [31:0] inst
);
    reg [31:0] mem [0:WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h03400000;       // andi r0,r0,0  == NOP
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // word index = addr[ log2(WORDS)+1 : 2 ]
    wire [31:0] word_index = addr >> 2;
    assign inst = mem[word_index[$clog2(WORDS)-1:0]];
endmodule
