
module main
  (
   inout [14:0] DDR_addr,
   inout [2:0] 	DDR_ba,
   inout 	DDR_cas_n,
   inout 	DDR_ck_n,
   inout 	DDR_ck_p,
   inout 	DDR_cke,
   inout 	DDR_cs_n,
   inout [3:0] 	DDR_dm,
   inout [31:0] DDR_dq,
   inout [3:0] 	DDR_dqs_n,
   inout [3:0] 	DDR_dqs_p,
   inout 	DDR_odt,
   inout 	DDR_ras_n,
   inout 	DDR_reset_n,
   inout 	DDR_we_n,
   inout 	FIXED_IO_ddr_vrn,
   inout 	FIXED_IO_ddr_vrp,
   inout [53:0] FIXED_IO_mio,
   inout 	FIXED_IO_ps_clk,
   inout 	FIXED_IO_ps_porb,
   inout 	FIXED_IO_ps_srstb,

   output 	led0_r,
   output 	led0_g,
   output 	led0_b,
   output 	led1_r,
   output 	led1_g,
   output 	led1_b
   );

   assign led0_r = 0;
   assign led0_g = 0;
   assign led0_b = 0;
   //assign led1_r = 0;
   //assign led1_g = 0;
   //assign led1_b = 0;
         
   wire clk_50MHz;
   
   wire [255:0] regs_in;
   wire [255:0] regs_out;
   wire [2:0] rgb_sel;
   
   assign regs_in = regs_out;
   assign rgb_sel = regs_out[34:32];
      
   duty50 duty50_inst
    (
        .clk(clk_50MHz),
        .sig_in(rgb_sel),
        .sig_out({led1_r, led1_g, led1_b})
    );
   
   design_main design_main_inst
     (
      .DDR_addr(DDR_addr),
      .DDR_ba(DDR_ba),
      .DDR_cas_n(DDR_cas_n),
      .DDR_ck_n(DDR_ck_n),
      .DDR_ck_p(DDR_ck_p),
      .DDR_cke(DDR_cke),
      .DDR_cs_n(DDR_cs_n),
      .DDR_dm(DDR_dm),
      .DDR_dq(DDR_dq),
      .DDR_dqs_n(DDR_dqs_n),
      .DDR_dqs_p(DDR_dqs_p),
      .DDR_odt(DDR_odt),
      .DDR_ras_n(DDR_ras_n),
      .DDR_reset_n(DDR_reset_n),
      .DDR_we_n(DDR_we_n),
      .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
      .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
      .FIXED_IO_mio(FIXED_IO_mio),
      .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
      .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
      .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),

      .clk_50MHz(clk_50MHz),
      .rstn_50MHz(),
      
      .regs_out(regs_out),
      .regs_in(regs_in)
      );
   
endmodule

   
