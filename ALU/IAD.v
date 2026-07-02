`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/30 10:30:00
// Design Name: 
// Module Name: IAD (Integer/IEEE754 Array Divider)
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 统一的整数和IEEE 754浮点数除法器
//              mode = 0: 32位整数除法 (有符号/无符号)
//              mode = 1: IEEE 754单精度浮点除法
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module IAD(
    input wire clk,              // 时钟信号
    input wire rst_n,            // 复位信号（低电平有效）
    input wire start,            // 开始计算信号
    input wire mode,             // 0: 整数除法, 1: 浮点除法
    input wire signed_mode,      // 0: 无符号整数, 1: 有符号整数（仅mode=0时有效）
    input wire [31:0] operand_a, // 被除数/操作数A
    input wire [31:0] operand_b, // 除数/操作数B
    output reg [31:0] quotient,  // 商
    output reg [31:0] remainder, // 余数（仅整数模式）
    output reg done,             // 计算完成信号
    output reg overflow,         // 溢出标志
    output reg underflow,        // 下溢标志（浮点）
    output reg invalid,          // 无效操作标志（除零或浮点NaN）
    output reg div_by_zero       // 除零标志
);

    // ========== 状态机定义 ==========
    localparam IDLE       = 3'd0;
    localparam INT_INIT   = 3'd1;
    localparam INT_DIV    = 3'd2;
    localparam INT_DONE   = 3'd3;
    localparam FP_DECODE  = 3'd4;
    localparam FP_DIV     = 3'd5;
    localparam FP_NORM    = 3'd6;
    localparam DONE       = 3'd7;
    
    reg [2:0] state, next_state;
    
    // ========== 整数除法相关信号 ==========
    reg [31:0] int_dividend, int_divisor;
    reg int_sign_dividend, int_sign_divisor;
    reg [31:0] int_quotient, int_remainder;
    reg [63:0] int_temp;
    reg [5:0] int_count;  // 循环计数器 (0-32)
    
    // ========== 浮点除法相关信号 ==========
    // IEEE 754 单精度格式: [31] 符号, [30:23] 指数, [22:0] 尾数
    reg fp_sign_a, fp_sign_b, fp_sign_result;
    reg [7:0] fp_exp_a, fp_exp_b;
    reg [22:0] fp_mant_a, fp_mant_b;
    reg [9:0] fp_exp_result;  // 扩展位宽以检测溢出
    reg [47:0] fp_mant_dividend;  // 扩展尾数用于除法
    reg [23:0] fp_mant_divisor;
    reg [23:0] fp_mant_quotient;
    reg fp_zero_a, fp_zero_b, fp_inf_a, fp_inf_b, fp_nan_a, fp_nan_b;
    reg [5:0] fp_count;  // 浮点除法计数器
    
    // ========== 状态机 - 时序逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // ========== 状态机 - 组合逻辑 ==========
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    if (mode == 1'b0)
                        next_state = INT_INIT;
                    else
                        next_state = FP_DECODE;
                end
            end
            
            INT_INIT: begin
                next_state = INT_DIV;
            end
            
            INT_DIV: begin
                if (int_count == 6'd32)
                    next_state = INT_DONE;
            end
            
            INT_DONE: begin
                next_state = DONE;
            end
            
            FP_DECODE: begin
                next_state = FP_DIV;
            end
            
            FP_DIV: begin
                if (fp_count == 6'd24)
                    next_state = FP_NORM;
            end
            
            FP_NORM: begin
                next_state = DONE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // ========== 整数除法器初始化 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_dividend <= 32'd0;
            int_divisor <= 32'd0;
            int_sign_dividend <= 1'b0;
            int_sign_divisor <= 1'b0;
            int_quotient <= 32'd0;
            int_remainder <= 32'd0;
            int_temp <= 64'd0;
            int_count <= 6'd0;
        end
        else if (state == IDLE && start && mode == 1'b0) begin
            // 处理符号
            if (signed_mode) begin
                int_sign_dividend <= operand_a[31];
                int_sign_divisor <= operand_b[31];
                int_dividend <= operand_a[31] ? (~operand_a + 1) : operand_a;
                int_divisor <= operand_b[31] ? (~operand_b + 1) : operand_b;
            end
            else begin
                int_sign_dividend <= 1'b0;
                int_sign_divisor <= 1'b0;
                int_dividend <= operand_a;
                int_divisor <= operand_b;
            end
            int_count <= 6'd0;
        end
        else if (state == INT_INIT) begin
            // 初始化除法
            int_temp <= {32'd0, int_dividend};
            int_quotient <= 32'd0;
            int_count <= 6'd0;
        end
        else if (state == INT_DIV) begin
            // 恢复余数除法算法
            int_temp <= {int_temp[62:0], 1'b0};  // 左移
            
            if (int_temp[63:32] >= int_divisor) begin
                int_temp[63:32] <= int_temp[63:32] - int_divisor;
                int_quotient <= {int_quotient[30:0], 1'b1};
            end
            else begin
                int_quotient <= {int_quotient[30:0], 1'b0};
            end
            
            int_count <= int_count + 1;
        end
        else if (state == INT_DONE) begin
            int_remainder <= int_temp[63:32];
        end
    end
    
    // ========== 浮点数解码 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp_sign_a <= 1'b0;
            fp_sign_b <= 1'b0;
            fp_exp_a <= 8'd0;
            fp_exp_b <= 8'd0;
            fp_mant_a <= 23'd0;
            fp_mant_b <= 23'd0;
            fp_zero_a <= 1'b0;
            fp_zero_b <= 1'b0;
            fp_inf_a <= 1'b0;
            fp_inf_b <= 1'b0;
            fp_nan_a <= 1'b0;
            fp_nan_b <= 1'b0;
        end
        else if (state == IDLE && start && mode == 1'b1) begin
            // 提取符号位
            fp_sign_a <= operand_a[31];
            fp_sign_b <= operand_b[31];
            
            // 提取指数和尾数
            fp_exp_a <= operand_a[30:23];
            fp_exp_b <= operand_b[30:23];
            fp_mant_a <= operand_a[22:0];
            fp_mant_b <= operand_b[22:0];
            
            // 检测特殊值
            fp_zero_a <= (operand_a[30:23] == 8'd0) && (operand_a[22:0] == 23'd0);
            fp_zero_b <= (operand_b[30:23] == 8'd0) && (operand_b[22:0] == 23'd0);
            fp_inf_a <= (operand_a[30:23] == 8'd255) && (operand_a[22:0] == 23'd0);
            fp_inf_b <= (operand_b[30:23] == 8'd255) && (operand_b[22:0] == 23'd0);
            fp_nan_a <= (operand_a[30:23] == 8'd255) && (operand_a[22:0] != 23'd0);
            fp_nan_b <= (operand_b[30:23] == 8'd255) && (operand_b[22:0] != 23'd0);
        end
        else if (state == FP_DECODE) begin
            // 初始化浮点除法
            fp_sign_result <= fp_sign_a ^ fp_sign_b;
            fp_exp_result <= {2'b00, fp_exp_a} - {2'b00, fp_exp_b} + 10'd127;
            fp_mant_dividend <= {1'b1, fp_mant_a, 24'd0};  // 被除数左移24位
            fp_mant_divisor <= {1'b1, fp_mant_b};
            fp_mant_quotient <= 24'd0;
            fp_count <= 6'd0;
        end
    end
    
    // ========== 浮点数除法 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp_count <= 6'd0;
        end
        else if (state == FP_DIV) begin
            // 类似整数除法的恢复余数算法
            if (fp_mant_dividend[47:24] >= fp_mant_divisor) begin
                fp_mant_dividend[47:24] <= fp_mant_dividend[47:24] - fp_mant_divisor;
                fp_mant_quotient <= {fp_mant_quotient[22:0], 1'b1};
            end
            else begin
                fp_mant_quotient <= {fp_mant_quotient[22:0], 1'b0};
            end
            
            fp_mant_dividend <= {fp_mant_dividend[46:0], 1'b0};  // 左移
            fp_count <= fp_count + 1;
        end
    end
    
    // ========== 浮点数归一化 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 归一化在DONE状态处理
        end
        else if (state == FP_NORM) begin
            // 检查最高位
            if (fp_mant_quotient[23]) begin
                // 已经归一化
            end
            else if (fp_mant_quotient[22]) begin
                // 左移1位
                fp_mant_quotient <= {fp_mant_quotient[22:0], 1'b0};
                fp_exp_result <= fp_exp_result - 1;
            end
            else if (fp_mant_quotient[21]) begin
                // 左移2位
                fp_mant_quotient <= {fp_mant_quotient[21:0], 2'b0};
                fp_exp_result <= fp_exp_result - 2;
            end
            else begin
                // 需要更多左移（简化处理）
                fp_mant_quotient <= {fp_mant_quotient[20:0], 3'b0};
                fp_exp_result <= fp_exp_result - 3;
            end
        end
    end
    
    // ========== 输出逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            quotient <= 32'd0;
            remainder <= 32'd0;
            done <= 1'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            invalid <= 1'b0;
            div_by_zero <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    overflow <= 1'b0;
                    underflow <= 1'b0;
                    invalid <= 1'b0;
                    div_by_zero <= 1'b0;
                end
                
                DONE: begin
                    done <= 1'b1;
                    
                    if (mode == 1'b0) begin
                        // 整数除法结果
                        // 检查除零
                        if (int_divisor == 32'd0) begin
                            quotient <= 32'hFFFFFFFF;
                            remainder <= int_dividend;
                            div_by_zero <= 1'b1;
                            invalid <= 1'b1;
                        end
                        else begin
                            // 恢复符号
                            if (signed_mode && (int_sign_dividend ^ int_sign_divisor)) begin
                                quotient <= ~int_quotient + 1;
                            end
                            else begin
                                quotient <= int_quotient;
                            end
                            
                            if (signed_mode && int_sign_dividend) begin
                                remainder <= ~int_remainder + 1;
                            end
                            else begin
                                remainder <= int_remainder;
                            end
                            
                            // 检查溢出（有符号除法特殊情况）
                            if (signed_mode && 
                                (int_dividend == 32'h80000000) && 
                                (int_divisor == 32'h00000001) &&
                                int_sign_divisor) begin
                                overflow <= 1'b1;
                            end
                        end
                    end
                    else begin
                        // 浮点除法结果
                        remainder <= 32'd0;  // 浮点模式下余数无意义
                        
                        // 处理特殊情况
                        if (fp_nan_a || fp_nan_b) begin
                            // NaN
                            quotient <= 32'h7FC00000;
                            invalid <= 1'b1;
                        end
                        else if (fp_zero_b) begin
                            // 除零
                            if (fp_zero_a) begin
                                // 0/0 = NaN
                                quotient <= 32'h7FC00000;
                                invalid <= 1'b1;
                            end
                            else if (fp_inf_a) begin
                                // Inf/0 = Inf
                                quotient <= {fp_sign_result, 8'd255, 23'd0};
                            end
                            else begin
                                // x/0 = Inf
                                quotient <= {fp_sign_result, 8'd255, 23'd0};
                                div_by_zero <= 1'b1;
                            end
                        end
                        else if (fp_zero_a) begin
                            // 0/x = 0
                            quotient <= {fp_sign_result, 31'd0};
                        end
                        else if (fp_inf_a && fp_inf_b) begin
                            // Inf/Inf = NaN
                            quotient <= 32'h7FC00000;
                            invalid <= 1'b1;
                        end
                        else if (fp_inf_a) begin
                            // Inf/x = Inf
                            quotient <= {fp_sign_result, 8'd255, 23'd0};
                        end
                        else if (fp_inf_b) begin
                            // x/Inf = 0
                            quotient <= {fp_sign_result, 31'd0};
                        end
                        else if (fp_exp_result >= 10'd255) begin
                            // 上溢 -> 无穷大
                            quotient <= {fp_sign_result, 8'd255, 23'd0};
                            overflow <= 1'b1;
                        end
                        else if (fp_exp_result[9] || fp_exp_result == 10'd0) begin
                            // 下溢 -> 零
                            quotient <= {fp_sign_result, 31'd0};
                            underflow <= 1'b1;
                        end
                        else begin
                            // 正常结果
                            quotient <= {fp_sign_result, fp_exp_result[7:0], fp_mant_quotient[22:0]};
                        end
                    end
                end
                
                default: begin
                    done <= 1'b0;
                end
            endcase
        end
    end

endmodule
