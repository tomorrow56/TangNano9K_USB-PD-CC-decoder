`default_nettype none
// Eight-record queue. Drop newest on full; cumulative drops travel with records.
module record_tx #(parameter UART_DIV=29)(input wire clk,input wire reset,
 input wire event_valid,input wire [2:0] event_kind,input wire [7:0] event_flags,
 input wire [5:0] event_len,input wire [31:0] event_time,input wire [271:0] event_data,
 output wire tx,output reg [31:0] dropped);
 reg [383:0] fifo[0:7]; reg [2:0] wr,rd;reg [3:0] used;
 reg [15:0] seq;
 reg sending; reg [383:0] record;reg [5:0] index;
 reg [15:0] crc;
 wire ready;
 wire pop=(!sending && used!=0);
 wire push=(event_valid && (used<8 || pop));
 reg [7:0] octet;
 always @* begin
  if(index==0) octet=8'ha5;
  else if(index==1) octet=8'h5a;
  else if(index==50) octet=crc[7:0];
  else if(index==51) octet=crc[15:8];
  else octet=record[(index-2)*8 +: 8];
 end
 function [15:0] crc_byte;
 input [15:0] c;input [7:0] d;reg [15:0] x;integer j;
 begin x=c^{d,8'd0};for(j=0;j<8;j=j+1) x=x[15] ? (x<<1)^16'h1021:x<<1;crc_byte=x;end
 endfunction
 uart_tx #(.DIV(UART_DIV)) u_uart(clk,reset,sending,octet,ready,tx);
 always @(posedge clk) begin
  if(reset) begin wr<=0;rd<=0;used<=0;seq<=0;sending<=0;record<=0;index<=0;crc<=16'hffff;dropped<=0;end
  else begin
   if(event_valid) begin
    seq<=seq+1'b1;
    if(!push) dropped<=dropped+1'b1;
   end
   if(push) begin
    fifo[wr]<={event_data,dropped,event_time,seq,{2'b00,event_len},event_flags,{5'd0,event_kind},8'h01};
    wr<=wr+1'b1;
   end
   if(pop) begin record<=fifo[rd];rd<=rd+1'b1;sending<=1;index<=0;crc<=16'hffff;end
   case({push,pop}) 2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:begin end endcase
   if(sending && ready) begin
    if(index>=2 && index<50) crc<=crc_byte(crc,octet);
    if(index==51) sending<=0;
    else index<=index+1'b1;
   end
  end
 end
endmodule
`default_nettype wire
