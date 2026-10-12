`default_nettype none
module uart_tx #(parameter DIV=29)(input wire clk,input wire reset,
 input wire valid,input wire [7:0] data,output wire ready,output wire tx);
 reg [9:0] shift; reg [3:0] left; reg [15:0] timer;
 assign ready=(left==0); assign tx=left==0 ? 1'b1:shift[0];
 always @(posedge clk) begin
  if(reset) begin shift<=10'h3ff;left<=0;timer<=0;end
  else if(left==0) begin
   if(valid) begin shift<={1'b1,data,1'b0};left<=10;timer<=DIV-1;end
  end else if(timer==0) begin shift<={1'b1,shift[9:1]};left<=left-1'b1;timer<=DIV-1;end
  else timer<=timer-1'b1;
 end
endmodule
`default_nettype wire
