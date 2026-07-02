`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/06/29 22:30:00
// Design Name: 
// Module Name: IAM_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: IAM模块的测试平台
// 
//////////////////////////////////////////////////////////////////////////////////

module IAM_tb;

    // 时钟和复位
    reg clk;
    reg rst_n;
    
    // 输入信号
    reg start;
    reg mode;
    reg signed_mode;
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    
    // 输出信号
    wire [63:0] result;
    wire done;
    wire overflow;
    wire underflow;
    wire invalid;
    
    // 实例化被测试模块
    IAM uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .mode(mode),
        .signed_mode(signed_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(result),
        .done(done),
        .overflow(overflow),
        .underflow(underflow),
        .invalid(invalid)
    );
    
    // 时钟生成：50MHz (20ns周期)
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    
    // 用于浮点数测试的函数
    function [31:0] float_to_bits;
        input real value;
        real temp;
        integer exp;
        integer mant;
        reg sign;
        begin
            if (value == 0.0) begin
                float_to_bits = 32'h00000000;
            end
            else begin
                sign = (value < 0);
                temp = (value < 0) ? -value : value;
                
                // 简化版本，仅供测试使用
                // 实际应用中建议使用$realtobits系统函数
                float_to_bits = $realtobits(value);
            end
        end
    endfunction
    
    // 测试任务
    task test_integer_mult;
        input [31:0] a;
        input [31:0] b;
        input is_signed;
        input [79:0] description;
        reg [63:0] expected;
        begin
            @(posedge clk);
            mode = 1'b0;
            signed_mode = is_signed;
            operand_a = a;
            operand_b = b;
            start = 1'b1;
            
            @(posedge clk);
            start = 1'b0;
            
            // 等待完成
            wait(done);
            @(posedge clk);
            
            // 计算期望值
            if (is_signed) begin
                expected = $signed(a) * $signed(b);
            end
            else begin
                expected = a * b;
            end
            
            // 显示结果
            $display("----------------------------------------");
            $display("Test: %s", description);
            $display("Mode: Integer %s", is_signed ? "Signed" : "Unsigned");
            $display("A = 0x%h (%d)", a, $signed(a));
            $display("B = 0x%h (%d)", b, $signed(b));
            $display("Result   = 0x%h (%d)", result, $signed(result));
            $display("Expected = 0x%h (%d)", expected, $signed(expected));
            $display("Overflow = %b", overflow);
            
            if (result == expected)
                $display("✓ PASS");
            else
                $display("✗ FAIL");
        end
    endtask
    
    task test_float_mult;
        input real a;
        input real b;
        input [79:0] description;
        reg [31:0] a_bits, b_bits;
        real result_real;
        real expected;
        begin
            @(posedge clk);
            mode = 1'b1;
            signed_mode = 1'b0;  // 在浮点模式下不使用
            
            a_bits = $realtobits(a);
            b_bits = $realtobits(b);
            
            operand_a = a_bits;
            operand_b = b_bits;
            start = 1'b1;
            
            @(posedge clk);
            start = 1'b0;
            
            // 等待完成
            wait(done);
            @(posedge clk);
            
            expected = a * b;
            result_real = $bitstoreal(result[63:32]);
            
            // 显示结果
            $display("----------------------------------------");
            $display("Test: %s", description);
            $display("Mode: IEEE 754 Float");
            $display("A = %f (0x%h)", a, a_bits);
            $display("B = %f (0x%h)", b, b_bits);
            $display("Result   = %f (0x%h)", result_real, result[63:32]);
            $display("Expected = %f", expected);
            $display("Overflow  = %b", overflow);
            $display("Underflow = %b", underflow);
            $display("Invalid   = %b", invalid);
            
            // 简单的相对误差检查（1%容差）
            if (invalid) begin
                $display("! Invalid operation detected");
            end
            else if (overflow || underflow) begin
                $display("! Overflow/Underflow detected");
            end
            else if ((result_real - expected) / expected < 0.01 && 
                     (result_real - expected) / expected > -0.01) begin
                $display("✓ PASS (within tolerance)");
            end
            else begin
                $display("✗ FAIL (error too large)");
            end
        end
    endtask
    
    // 主测试序列
    initial begin
        $display("========================================");
        $display("IAM (Integer/IEEE754 Array Multiplier) Test");
        $display("========================================");
        
        // 初始化
        rst_n = 0;
        start = 0;
        mode = 0;
        signed_mode = 0;
        operand_a = 0;
        operand_b = 0;
        
        // 复位
        #50;
        rst_n = 1;
        #20;
        
        // ========== 整数乘法测试 ==========
        $display("\n========== 无符号整数乘法测试 ==========");
        
        test_integer_mult(32'd15, 32'd20, 0, "Small numbers");
        test_integer_mult(32'd255, 32'd256, 0, "Medium numbers");
        test_integer_mult(32'hFFFF, 32'hFFFF, 0, "16-bit max");
        test_integer_mult(32'hFFFFFFFF, 32'd2, 0, "Large number");
        
        $display("\n========== 有符号整数乘法测试 ==========");
        
        test_integer_mult(32'd15, 32'd20, 1, "Positive × Positive");
        test_integer_mult(-32'd15, 32'd20, 1, "Negative × Positive");
        test_integer_mult(32'd15, -32'd20, 1, "Positive × Negative");
        test_integer_mult(-32'd15, -32'd20, 1, "Negative × Negative");
        test_integer_mult(32'h80000000, 32'd2, 1, "Most negative × 2");
        
        // ========== 浮点乘法测试 ==========
        $display("\n========== IEEE 754 浮点乘法测试 ==========");
        
        test_float_mult(3.5, 2.0, "Simple float");
        test_float_mult(1.5, 4.25, "Decimal float");
        test_float_mult(-2.5, 3.0, "Negative × Positive");
        test_float_mult(-1.5, -2.0, "Negative × Negative");
        test_float_mult(0.0, 5.5, "Zero × Number");
        test_float_mult(123.456, 7.89, "Larger numbers");
        test_float_mult(0.001, 0.002, "Small numbers");
        
        // 特殊值测试
        $display("\n========== 浮点特殊值测试 ==========");
        
        // 注意：需要直接设置位模式来测试特殊值
        @(posedge clk);
        mode = 1'b1;
        operand_a = 32'h7F800000; // +Infinity
        operand_b = 32'h40000000; // 2.0
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        wait(done);
        @(posedge clk);
        $display("Inf × 2.0 = 0x%h (should be Inf: 0x7F800000), Invalid=%b", 
                 result[63:32], invalid);
        
        @(posedge clk);
        operand_a = 32'h7F800000; // +Infinity
        operand_b = 32'h00000000; // 0.0
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        wait(done);
        @(posedge clk);
        $display("Inf × 0.0 = 0x%h (should be NaN: 0x7FC00000), Invalid=%b", 
                 result[63:32], invalid);
        
        @(posedge clk);
        operand_a = 32'h7FC00000; // NaN
        operand_b = 32'h40000000; // 2.0
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        wait(done);
        @(posedge clk);
        $display("NaN × 2.0 = 0x%h (should be NaN: 0x7FC00000), Invalid=%b", 
                 result[63:32], invalid);
        
        // 完成测试
        #100;
        $display("\n========================================");
        $display("Test completed!");
        $display("========================================");
        $finish;
    end
    
    // 超时保护
    initial begin
        #100000;
        $display("ERROR: Test timeout!");
        $finish;
    end
    
endmodule
