`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/29 22:24:00
// Design Name: 
// Module Name: IAM (Integer/IEEE754 Array Multiplier)
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 统一的整数和IEEE 754浮点数乘法器
//              mode = 0: 32位整数乘法 (有符号/无符号)
//              mode = 1: IEEE 754单精度浮点乘法
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module IAM(
    input wire clk,              // 时钟信号
    input wire rst_n,            // 复位信号（低电平有效）
    input wire start,            // 开始计算信号
    input wire mode,             // 0: 整数乘法, 1: 浮点乘法
    input wire signed_mode,      // 0: 无符号整数, 1: 有符号整数（仅mode=0时有效）
    input wire [31:0] operand_a, // 操作数A（整数或浮点数）
    input wire [31:0] operand_b, // 操作数B（整数或浮点数）
    output reg [63:0] result,    // 结果（整数64位，浮点32位在低位）
    output reg done,             // 计算完成信号
    output reg overflow,         // 溢出标志
    output reg underflow,        // 下溢标志（浮点）
    output reg invalid           // 无效操作标志（浮点）
);

    // ========== 状态机定义 ==========
    localparam IDLE       = 3'd0;
    localparam INT_MULT   = 3'd1;
    localparam FP_DECODE  = 3'd2;
    localparam FP_MULT    = 3'd3;
    localparam FP_NORM    = 3'd4;
    localparam DONE       = 3'd5;
    
    reg [2:0] state, next_state;
    
    // ========== 整数乘法相关信号 ==========
    reg [31:0] int_a, int_b;
    reg int_sign_a, int_sign_b;
    reg [63:0] int_product;
    
    // ========== 浮点乘法相关信号 ==========
    // IEEE 754 单精度格式: [31] 符号, [30:23] 指数, [22:0] 尾数
    reg fp_sign_a, fp_sign_b, fp_sign_result;
    reg [7:0] fp_exp_a, fp_exp_b;
    reg [22:0] fp_mant_a, fp_mant_b;
    reg [9:0] fp_exp_result;  // 扩展位宽以检测溢出
    reg [47:0] fp_mant_product;  // 24位 × 24位 = 48位
    reg [23:0] fp_mant_normalized;
    reg fp_zero_a, fp_zero_b, fp_inf_a, fp_inf_b, fp_nan_a, fp_nan_b;
    
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
                        next_state = INT_MULT;
                    else
                        next_state = FP_DECODE;
                end
            end
            
            INT_MULT: begin
                next_state = DONE;
            end
            
            FP_DECODE: begin
                next_state = FP_MULT;
            end
            
            FP_MULT: begin
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
    
    // ========== 整数乘法器 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_a <= 32'd0;
            int_b <= 32'd0;
            int_sign_a <= 1'b0;
            int_sign_b <= 1'b0;
            int_product <= 64'd0;
        end
        else if (state == IDLE && start && mode == 1'b0) begin
            // 处理符号
            if (signed_mode) begin
                int_sign_a <= operand_a[31];
                int_sign_b <= operand_b[31];
                int_a <= operand_a[31] ? (~operand_a + 1) : operand_a;
                int_b <= operand_b[31] ? (~operand_b + 1) : operand_b;
            end
            else begin
                int_sign_a <= 1'b0;
                int_sign_b <= 1'b0;
                int_a <= operand_a;
                int_b <= operand_b;
            end
        end
        else if (state == INT_MULT) begin
            // 执行无符号乘法
            int_product <= int_a * int_b;
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
    end
    
    // ========== 浮点数乘法 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp_sign_result <= 1'b0;
            fp_exp_result <= 10'd0;
            fp_mant_product <= 48'd0;
        end
        else if (state == FP_MULT) begin
            // 符号位：异或
            fp_sign_result <= fp_sign_a ^ fp_sign_b;
            
            // 指数：相加并减去偏置(127)
            // 扩展到10位以检测溢出/下溢
            fp_exp_result <= {2'b00, fp_exp_a} + {2'b00, fp_exp_b} - 10'd127;
            
            // 尾数：乘法（添加隐含的1）
            fp_mant_product <= {1'b1, fp_mant_a} * {1'b1, fp_mant_b};
        end
    end
    
    // ========== 浮点数归一化 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp_mant_normalized <= 24'd0;
        end
        else if (state == FP_NORM) begin
            // 检查最高位，如果是1则需要右移并调整指数
            if (fp_mant_product[47]) begin
                fp_mant_normalized <= fp_mant_product[47:24];
                fp_exp_result <= fp_exp_result + 1;
            end
            else begin
                fp_mant_normalized <= fp_mant_product[46:23];
            end
        end
    end
    
    // ========== 输出逻辑 ==========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 64'd0;
            done <= 1'b0;
            overflow <= 1'b0;
            underflow <= 1'b0;
            invalid <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    overflow <= 1'b0;
                    underflow <= 1'b0;
                    invalid <= 1'b0;
                end
                
                DONE: begin
                    done <= 1'b1;
                    
                    if (mode == 1'b0) begin
                        // 整数乘法结果
                        if (signed_mode && (int_sign_a ^ int_sign_b))
                            result <= ~int_product + 1;  // 恢复符号
                        else
                            result <= int_product;
                        
                        // 检查有符号整数溢出
                        if (signed_mode) begin
                            overflow <= (int_sign_a ^ int_sign_b) ? 
                                       (int_product > 64'h8000_0000_0000_0000) :
                                       (int_product > 64'h7FFF_FFFF_FFFF_FFFF);
                        end
                    end
                    else begin
                        // 浮点乘法结果
                        // 处理特殊情况
                        if (fp_nan_a || fp_nan_b || (fp_zero_a && fp_inf_b) || (fp_inf_a && fp_zero_b)) begin
                            // NaN
                            result <= {32'h7FC0_0000, 32'd0};
                            invalid <= 1'b1;
                        end
                        else if (fp_inf_a || fp_inf_b) begin
                            // 无穷大
                            result <= {fp_sign_result, 8'd255, 23'd0, 32'd0};
                        end
                        else if (fp_zero_a || fp_zero_b) begin
                            // 零
                            result <= {fp_sign_result, 31'd0, 32'd0};
                        end
                        else if (fp_exp_result >= 10'd255) begin
                            // 上溢 -> 无穷大
                            result <= {fp_sign_result, 8'd255, 23'd0, 32'd0};
                            overflow <= 1'b1;
                        end
                        else if (fp_exp_result[9] || fp_exp_result == 10'd0) begin
                            // 下溢 -> 零
                            result <= {fp_sign_result, 31'd0, 32'd0};
                            underflow <= 1'b1;
                        end
                        else begin
                            // 正常结果
                            result <= {fp_sign_result, fp_exp_result[7:0], fp_mant_normalized[22:0], 32'd0};
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
