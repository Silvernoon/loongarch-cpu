// =============================================================================
// div_unit.v  —  32-bit sequential restoring divider (signed/unsigned)
//
// One restoring-division step per clock: 32 iterations, then a fixup cycle
// for signs, matching LoongArch DIV.W/DIV.WU/MOD.W/MOD.WU semantics:
//   - quotient  truncates toward zero
//   - remainder takes the sign of the dividend
//
// The subtraction inside each step uses the structural adder32, so the trial
// subtraction is real gate hardware.  A busy/done handshake lets the pipeline
// stall in EX while the divider runs.
//
// LoongArch DIV/MOD by zero and INT_MIN/-1 overflow are architecturally
// UNPREDICTABLE (no trap); we return a defined value (quotient=-1 or dividend
// on /0, INT_MIN on overflow) so simulation is deterministic.
// =============================================================================
`timescale 1ns / 1ps

module div_unit(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,       // pulse 1 cycle to begin
    input  wire        is_signed,   // 1: signed, 0: unsigned
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    output reg  [31:0] quotient,
    output reg  [31:0] remainder,
    output reg         busy,
    output reg         done         // high for 1 cycle when result valid
);
    localparam S_IDLE = 2'd0;
    localparam S_CALC = 2'd1;
    localparam S_FIX  = 2'd2;
    localparam S_DONE = 2'd3;

    reg [1:0]  state;
    reg [5:0]  count;            // 0..32
    reg [31:0] q;                // quotient being shifted in
    reg [31:0] rem;              // running remainder (P register)
    reg [31:0] d;                // absolute divisor
    reg [31:0] dvd;              // absolute dividend (shifts left into rem)
    reg        sign_q, sign_r;   // desired result signs
    reg        div0;
    reg [31:0] dvd_orig;         // original signed dividend (for div0 result)

    // ---- structural trial subtraction : {rem,dvd} top - divisor ------------
    // At each step we shift the (rem:dvd) pair left by 1, then try rem - d.
    wire [31:0] rem_shl = {rem[30:0], dvd[31]};
    wire [31:0] trial;
    wire        tr_cout, tr_ov;
    adder32 sub_step(.a(rem_shl), .b(d), .sub(1'b1),
                     .sum(trial), .cout(tr_cout), .overflow(tr_ov));
    // rem_shl >= d  <=>  no borrow  <=>  cout == 1 (subtract carry convention)
    wire ge = tr_cout;

    // ---- magnitudes of the operands ----------------------------------------
    wire [31:0] dvd_neg, dsr_neg;
    wire c0,o0,c1,o1;
    adder32 nd(.a(32'd0), .b(dividend), .sub(1'b1), .sum(dvd_neg), .cout(c0), .overflow(o0));
    adder32 ns(.a(32'd0), .b(divisor),  .sub(1'b1), .sum(dsr_neg), .cout(c1), .overflow(o1));

    // ---- sign fixups on quotient / remainder -------------------------------
    wire [31:0] q_neg, r_neg;
    wire c2,o2,c3,o3;
    adder32 nq(.a(32'd0), .b(q),   .sub(1'b1), .sum(q_neg), .cout(c2), .overflow(o2));
    adder32 nr(.a(32'd0), .b(rem), .sub(1'b1), .sum(r_neg), .cout(c3), .overflow(o3));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; busy <= 1'b0; done <= 1'b0;
            quotient <= 32'd0; remainder <= 32'd0;
            count <= 6'd0; q <= 32'd0; rem <= 32'd0; d <= 32'd0; dvd <= 32'd0;
            sign_q <= 1'b0; sign_r <= 1'b0; div0 <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        div0   <= (divisor == 32'd0);
                        sign_q <= is_signed & (dividend[31] ^ divisor[31]);
                        sign_r <= is_signed &  dividend[31];
                        d      <= (is_signed & divisor[31])  ? dsr_neg : divisor;
                        dvd    <= (is_signed & dividend[31]) ? dvd_neg : dividend;
                        dvd_orig <= dividend;
                        rem    <= 32'd0;
                        q      <= 32'd0;
                        count  <= 6'd0;
                        busy   <= 1'b1;
                        state  <= S_CALC;
                    end
                end

                S_CALC: begin
                    // shift dividend into the pair, shift quotient bit in
                    dvd <= {dvd[30:0], 1'b0};
                    if (ge) begin
                        rem <= trial;              // keep subtraction
                        q   <= {q[30:0], 1'b1};
                    end else begin
                        rem <= rem_shl;            // restore
                        q   <= {q[30:0], 1'b0};
                    end
                    count <= count + 6'd1;
                    if (count == 6'd31)
                        state <= S_FIX;
                end

                S_FIX: begin
                    if (div0) begin
                        // architecturally undefined; give deterministic values
                        quotient  <= 32'hFFFFFFFF;
                        remainder <= dvd_orig;          // original signed dividend
                    end else begin
                        quotient  <= sign_q ? q_neg : q;
                        remainder <= sign_r ? r_neg : rem;
                    end
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
