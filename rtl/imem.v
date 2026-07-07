// =============================================================================
// imem.v  --  Harvard instruction memory with a tiny direct-mapped I-cache
//
// The backing store is still the program image loaded by $readmemh, but the
// CPU now fetches through a one-word-line direct-mapped cache.  An invalid or
// conflicting line asserts stall for MISS_PENALTY cycles, then fills from the
// backing store.  Hits return the instruction combinationally.
//
// The loader tries INIT_FILE directly and through common Vivado/XSim generated
// run-directory prefixes, so a testbench can keep using "sim/prog.hex" whether
// it is run from the repository root or from <project>.sim/.../xsim.
// =============================================================================
`timescale 1ns / 1ps

module imem #(
    parameter WORDS = 1024,              // 4 KiB instruction store
    parameter INIT_FILE = "",
    parameter LINES = 16,                // one 32-bit word per cache line
    parameter MISS_PENALTY = 2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] addr,             // byte address (PC)
    output wire [31:0] inst,
    output wire        stall
);
    reg [31:0] mem [0:WORDS-1];
    reg [31:0] cache_data [0:LINES-1];
    reg [31:0] cache_tag  [0:LINES-1];
    reg        cache_valid[0:LINES-1];

    integer i;
    integer loaded;

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 32'h03400000;       // andi r0,r0,0  == NOP
        for (i = 0; i < LINES; i = i + 1) begin
            cache_data[i]  = 32'h03400000;
            cache_tag[i]   = 32'd0;
            cache_valid[i] = 1'b0;
        end

        loaded = 0;
        if (INIT_FILE != "") begin
            try_readmemh(INIT_FILE, loaded);
            if (!loaded) try_readmemh({"../", INIT_FILE}, loaded);
            if (!loaded) try_readmemh({"../../", INIT_FILE}, loaded);
            if (!loaded) try_readmemh({"../../../", INIT_FILE}, loaded);
            if (!loaded) try_readmemh({"../../../../", INIT_FILE}, loaded);
            if (!loaded) try_readmemh({"../../../../../", INIT_FILE}, loaded);
            if (!loaded) try_readmemh({"../../../../../../", INIT_FILE}, loaded);
            if (!loaded)
                $display("WARNING: imem could not open %0s; using NOP image", INIT_FILE);
        end
    end

    task try_readmemh;
        input [1023:0] path;
        output integer ok;
        integer fd;
        begin
            ok = 0;
            fd = $fopen(path, "r");
            if (fd != 0) begin
                $fclose(fd);
                $readmemh(path, mem);
                $display("imem: loaded %0s", path);
                ok = 1;
            end
        end
    endtask

    localparam INDEX_BITS = (LINES <= 1) ? 1 : $clog2(LINES);
    localparam WORD_INDEX_BITS = (WORDS <= 1) ? 1 : $clog2(WORDS);
    localparam PENALTY = (MISS_PENALTY < 1) ? 1 : MISS_PENALTY;

    reg        busy;
    reg [7:0]  miss_count;
    reg [31:0] miss_word_index;
    reg [INDEX_BITS-1:0] miss_index;
    reg [31:0] miss_tag;

    wire [31:0] word_index = addr >> 2;
    wire [INDEX_BITS-1:0] index = word_index[INDEX_BITS-1:0];
    wire [31:0] tag = word_index >> INDEX_BITS;

    wire hit = cache_valid[index] && (cache_tag[index] == tag);
    wire miss = rst_n && !hit && !busy;

    assign stall = rst_n && (busy || miss);
    assign inst  = !rst_n ? 32'h03400000 :
                   hit    ? cache_data[index] :
                            mem[word_index[WORD_INDEX_BITS-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            miss_count <= 8'd0;
            miss_word_index <= 32'd0;
            miss_index <= {INDEX_BITS{1'b0}};
            miss_tag <= 32'd0;
            for (i = 0; i < LINES; i = i + 1)
                cache_valid[i] <= 1'b0;
        end else if (busy) begin
            if (miss_count >= PENALTY - 1) begin
                cache_data[miss_index] <= mem[miss_word_index[WORD_INDEX_BITS-1:0]];
                cache_tag[miss_index] <= miss_tag;
                cache_valid[miss_index] <= 1'b1;
                busy <= 1'b0;
            end else begin
                miss_count <= miss_count + 8'd1;
            end
        end else if (miss) begin
            busy <= 1'b1;
            miss_count <= 8'd0;
            miss_word_index <= word_index;
            miss_index <= index;
            miss_tag <= tag;
        end
    end
endmodule
