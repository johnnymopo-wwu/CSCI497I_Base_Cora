
module duty50 #(parameter ON_BITS=16,  // ON_BITS is number of bits for on and off time
		parameter PORT_BITS=3) // PORT_BITS is bus width
   (
    input		       clk,

    input [PORT_BITS-1:0]      sig_in,
    output reg [PORT_BITS-1:0] sig_out
    );

   reg [ON_BITS:0] cntr=0;
 
   always @(posedge clk) begin
      cntr <= cntr + 1;
      sig_out <= sig_in & {PORT_BITS{cntr[ON_BITS]}};
   end

endmodule

   
      
