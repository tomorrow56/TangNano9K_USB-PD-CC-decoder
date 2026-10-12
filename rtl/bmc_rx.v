`default_nettype none
// 27 MHz, nominal 300 kbit/s: half UI = 45 clocks. Edge polarity independent.
module bmc_rx (
    input wire clk,
    input wire reset,
    input wire cc,
    output reg bit_valid,
    output reg bit_data,
    output reg lost
);
    // 非同期のBMC入力を3段同期してからエッジを検出する。
    reg [2:0] sync;
    reg last, seen, half_pending;
    reg [8:0] age;

    always @(posedge clk) begin
        if (reset) begin
            sync <= 0;
            last <= 0;
            seen <= 0;
            half_pending <= 0;
            age <= 0;
            bit_valid <= 0;
            bit_data <= 0;
            lost <= 0;
        end else begin
            sync <= {sync[1:0], cc};
            last <= sync[2];

            // 有効bitと信号中断は、後段へ1クロックのパルスで通知する。
            bit_valid <= 0;
            lost <= 0;
            if (age < 9'd200) age <= age + 1'b1;
            if (sync[2] != last) begin
                age <= 0;
                if (!seen) begin
                    seen <= 1;
                    half_pending <= 0;
                end else if (age >= 27 && age <= 65) begin
                    // 半UI間隔のエッジを2回受けるとデータ1になる。
                    if (half_pending) begin
                        bit_valid <= 1;
                        bit_data <= 1;
                        half_pending <= 0;
                    end else
                        half_pending <= 1;
                end else if (age >= 66 && age <= 119) begin
                    // A full interval is a zero and also restores boundary alignment.
                    bit_valid <= 1;
                    bit_data <= 0;
                    half_pending <= 0;
                end else begin
                    lost <= 1;
                    half_pending <= 0;
                    seen <= 1;
                end
            end else if (age == 179 && seen) begin
                // 約6.7usの無遷移で、途中パケットを打ち切る。
                seen <= 0;
                half_pending <= 0;
                lost <= 1;
            end
        end
    end
endmodule
`default_nettype wire
