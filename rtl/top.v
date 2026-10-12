`default_nettype none
module top (
    input wire clk,
    input wire cc_bmc,
    output wire uart_tx
);
    // Gowin supports register power-up initialization. No external reset needed.
    reg [9:0] por = 0;
    wire reset = !(&por);

    always @(posedge clk)
        if (reset) por <= por + 1'b1;

    // SOP認識時刻用のフリーランカウンタ（27MHz、約159秒で周回）。
    reg [31:0] ticks;

    always @(posedge clk)
        if (reset) ticks <= 0;
        else ticks <= ticks + 1'b1;

    wire bv, bd, lost, ev;
    wire [2:0] kind;
    wire [7:0] flags;
    wire [5:0] len;
    wire [31:0] stamp, dropped;
    wire [271:0] data;

    // デジタルBMC → bit列 → PDパケット → UARTレコード。
    bmc_rx bmc(
        clk, reset, cc_bmc, bv, bd, lost
    );

    pd_rx pd(
        clk, reset, bv, bd, lost, ticks,
        ev, kind, flags, len, stamp, data
    );

    record_tx records(
        clk, reset, ev, kind, flags, len, stamp, data,
        uart_tx, dropped
    );
endmodule
`default_nettype wire
