`timescale 1ns/1ps
module fifo_tb;
    reg clk = 0;

    always #5 clk = ~clk;
    reg reset = 1, ev = 0;
    reg [31:0] stamp = 0;
    wire tx;
    wire [31:0] drop;

    record_tx #(.UART_DIV(2)) dut(clk, reset, ev, 3'd5, 8'd0, 6'd0, stamp, 272'd0, tx, drop);
    integer i, n = 0, fd, j;
    reg [7:0] b;
    // UART波形をbyteに戻し、JS側で照合するバイナリログを作る。
    initial begin
        fd = $fopen("overflow.bin", "wb");
        forever begin
            @(negedge tx);
            @(posedge clk);
            for (j = 0; j < 8; j = j + 1) begin
                repeat (2) @(posedge clk);
                b[j] = tx;
            end
            repeat (2) @(posedge clk);
            if (tx !== 1) $fatal;
            $fwrite(fd, "%c", b);
            n = n + 1;
        end
    end
    initial begin
        repeat (10) @(negedge clk);
        reset = 0;
        // 20件を連続投入し、送信中1件＋FIFO8件を超える11件を落とす。
        for (i = 0; i < 20; i = i + 1) begin
            ev = 1;
            stamp = i;
            @(negedge clk);
        end
        ev = 0;
        repeat (12000) @(negedge clk);
        if (drop !== 11) begin
            $display("drop=%0d", drop);
            $fatal;
        end
        // FIFO排出後に再送し、欠落数とsequenceが引き継がれることを確認。
        ev = 1;
        stamp = 20;
        @(negedge clk);
        ev = 0;
        repeat (1500) @(negedge clk);
        if (n != 520) begin
            $display("bytes=%0d", n);
            $fatal;
        end
        $fclose(fd);
        $display("PASS FIFO overflow, drain and recovery");
        $finish;
    end
endmodule
