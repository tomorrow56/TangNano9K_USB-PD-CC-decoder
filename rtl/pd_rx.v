`default_nettype none
// One passive CC channel. Event data includes header, payload and received CRC32.
module pd_rx (
    input wire clk,
    input wire reset,
    input wire bit_valid,
    input wire bit_data,
    input wire lost,
    input wire [31:0] ticks,
    output reg event_valid,
    output reg [2:0] event_kind,
    output reg [7:0] event_flags,
    output reg [5:0] event_len,
    output reg [31:0] event_time,
    output reg [271:0] event_data
);
    // 4個の5bit symbolを、bit境界をずらしながら探索する。
    reg [19:0] window;
    wire [19:0] next_window = {bit_data, window[19:1]};
    reg [6:0] qualify;
    reg active, high_nibble;
    reg [2:0] bit_count;
    reg [4:0] symbol;
    wire [4:0] next_symbol = {bit_data, symbol[4:1]};
    reg [3:0] low_nibble;
    reg [5:0] count;
    reg [271:0] data;
    reg [31:0] crc, start_time;
    reg [2:0] kind;
    reg [7:0] flags;
    reg [3:0] nibble;
    reg is_data;
    wire [7:0] new_byte = {nibble, low_nibble};
    // ヘッダ2byte + NDO×4byte + CRC32の4byte。
    wire [5:0] expected_len = 6'd6 + {data[14:12], 2'b00};

    // USB PDの反射CRC32。受信CRCも含めて更新し、EOP時にresidueを照合。
    function [31:0] crc_byte;
        input [31:0] c;
        input [7:0] d;
        reg [31:0] x;
        integer i;
        begin
            x = c ^ {24'd0, d};
            for (i = 0; i < 8; i = i + 1) x = x[0] ? (x >> 1) ^ 32'hedb88320 : x >> 1;
            crc_byte = x;
        end
    endfunction

    // K-code（SOP/EOP等）は通常の4bitデータとして扱わない。
    always @* begin
        is_data = 1;
        case (next_symbol)
            5'h1e: nibble = 0;
            5'h09: nibble = 1;
            5'h14: nibble = 2;
            5'h15: nibble = 3;
            5'h0a: nibble = 4;
            5'h0b: nibble = 5;
            5'h0e: nibble = 6;
            5'h0f: nibble = 7;
            5'h12: nibble = 8;
            5'h13: nibble = 9;
            5'h16: nibble = 10;
            5'h17: nibble = 11;
            5'h1a: nibble = 12;
            5'h1b: nibble = 13;
            5'h1c: nibble = 14;
            5'h1d: nibble = 15;
            default: begin
                nibble = 0;
                is_data = 0;
            end
        endcase
    end
    reg found;
    reg [2:0] found_kind;

    // LSB-firstでシフトするため、定数の右端が最初のsymbolに対応する。
    // kind: 0=SOP, 1/2=prime/double-prime, 3/4=Debug, 5/6=Reset。
    always @* begin
        found = 1;
        found_kind = 0;
        case (next_window)
            {5'h11, 5'h18, 5'h18, 5'h18}: found_kind = 0;
            {5'h06, 5'h06, 5'h18, 5'h18}: found_kind = 1;
            {5'h06, 5'h18, 5'h06, 5'h18}: found_kind = 2;
            {5'h06, 5'h19, 5'h19, 5'h18}: found_kind = 3;
            {5'h11, 5'h06, 5'h19, 5'h18}: found_kind = 4;
            {5'h19, 5'h07, 5'h07, 5'h07}: found_kind = 5;
            {5'h06, 5'h07, 5'h18, 5'h07}: found_kind = 6;
            default: found = 0;
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            window <= 0;
            qualify <= 0;
            active <= 0;
            high_nibble <= 0;
            bit_count <= 0;
            symbol <= 0;
            low_nibble <= 0;
            count <= 0;
            data <= 0;
            crc <= 32'hffffffff;
            start_time <= 0;
            kind <= 0;
            flags <= 0;
            event_valid <= 0;
            event_kind <= 0;
            event_flags <= 0;
            event_len <= 0;
            event_time <= 0;
            event_data <= 0;
        end else begin
            event_valid <= 0;
            // 波形が途切れた場合も、取得済みのbyteをエラー付きで残す。
            if (lost) begin
                window <= 0;
                qualify <= 0;
                if (active) begin
                    event_valid <= 1;
                    event_kind <= kind;
                    event_flags <= flags | 8'h04;
                    event_len <= count;
                    event_time <= start_time;
                    event_data <= data;
                end
                active <= 0;
                bit_count <= 0;
                high_nibble <= 0;
            end else if (bit_valid) begin
                window <= next_window;
                if (qualify < 127) qualify <= qualify + 1'b1;
                if (!active) begin
                    // 最低32bitの履歴を要求する簡易同期（厳密なプリアンブル検証ではない）。
                    if (found && qualify >= 32) begin
                        kind <= found_kind;
                        start_time <= ticks;
                        count <= 0;
                        data <= 0;
                        flags <= 0;
                        crc <= 32'hffffffff;
                        bit_count <= 0;
                        symbol <= 0;
                        high_nibble <= 0;
                        // Resetはordered setだけで完結し、ヘッダやCRCを持たない。
                        if (found_kind >= 5) begin
                            event_valid <= 1;
                            event_kind <= found_kind;
                            event_flags <= 0;
                            event_len <= 0;
                            event_time <= ticks;
                            event_data <= 0;
                            qualify <= 0;
                            window <= 0;
                        end else
                            active <= 1;
                    end
                end else begin
                    symbol <= next_symbol;
                    if (bit_count == 4) begin
                        bit_count <= 0;
                        // EOPでCRCと長さを確定して、1件のイベントを出力する。
                        if (next_symbol == 5'h0d) begin
                            event_valid <= 1;
                            event_kind <= kind;
                            // flags: bit0=CRC一致、bit3=長さ/半byte不一致。
                            event_flags <= flags
                                | ((count >= 6 && crc == 32'hdebb20e3) ? 8'h01 : 8'h00)
                                | ((high_nibble || count != expected_len) ? 8'h08 : 8'h00);
                            event_len <= count;
                            event_time <= start_time;
                            event_data <= data;
                            active <= 0;
                            qualify <= 0;
                            window <= 0;
                        end else if (!is_data || count == 34) begin
                            event_valid <= 1;
                            event_kind <= kind;
                            event_flags <= flags | 8'h02;
                            event_len <= count;
                            event_time <= start_time;
                            event_data <= data;
                            active <= 0;
                            qualify <= 0;
                            window <= 0;
                        end else if (!high_nibble) begin
                            // 各byteは下位nibble、上位nibbleの順に受信する。
                            low_nibble <= nibble;
                            high_nibble <= 1;
                        end else begin
                            data[count * 8 +: 8] <= new_byte;
                            count <= count + 1'b1;
                            crc <= crc_byte(crc, new_byte);
                            high_nibble <= 0;
                        end
                    end else
                        bit_count <= bit_count + 1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
