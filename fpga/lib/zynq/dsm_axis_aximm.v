`resetall
`timescale 1ns / 1ps
`default_nettype none

module dsm_axis_aximm(

	input wire		  clk,
	input wire		  rst,

	input  wire[511:0] s_axis_dsm_tdata,
	input  wire        s_axis_dsm_tvalid,
	input  wire        s_axis_dsm_tkeep,
	input  wire        s_axis_dsm_tuser,
	output wire        s_axis_dsm_tready,
	input  wire        s_axis_dsm_tlast,

	output wire[63:0]  m_axi_dsm_wdata,
	output wire		   m_axi_dsm_wvalid,
	input wire		   m_axi_dsm_wready,
	output wire[7:0]   m_axi_dsm_wstrb,

	output wire[48:0]  m_axi_dsm_awaddr,
	output wire		   m_axi_dsm_awvalid,
	input wire		   m_axi_dsm_awready,
	output wire[2:0]   m_axi_dsm_awprot,

	input wire         m_axi_dsm_bvalid,
	input wire[1:0]    m_axi_dsm_bresp,
	output wire		   m_axi_dsm_bready,

	input wire[63:0]   m_axi_dsm_rdata,
	input wire		   m_axi_dsm_rvalid,
	output wire		   m_axi_dsm_rready,
	input wire [1:0]   m_axi_dsm_rresp,

	output wire[48:0]  m_axi_dsm_araddr,
	output wire		   m_axi_dsm_arvalid,
	input wire		   m_axi_dsm_arready,
	output wire[2:0]   m_axi_dsm_arprot,
	
	input wire[48:0]   phy_addr
	);
	
	localparam DEEP = 128;
	localparam DATA_WIDTH = 512;
	localparam ADDR = $clog2(DEEP);

	reg [DATA_WIDTH-1:0] dsm_data_fifo [DEEP-1:0];
	reg [ADDR:0] wr_ptr, wr_ptr_nxt;
	reg [ADDR:0] rd_ptr, rd_ptr_nxt;
	reg valid_reg;
	reg [DATA_WIDTH-1:0] tdata_reg;
	reg[2:0]  i_nxt, i;
	reg[48:0] addr_cnt, addr_cnt_nxt;
	wire full_flg = (wr_ptr == (rd_ptr ^ {1'b1, {ADDR-1{1'b0}}}));
    wire empty_flg = (wr_ptr == rd_ptr);
    
	always @(posedge clk) begin
		if(valid_reg) begin
			dsm_data_fifo[wr_ptr[ADDR-1:0]] <= tdata_reg;
		end
	end

	always @(posedge clk) begin
		if(!rst) begin
			valid_reg <= 'b0;
			tdata_reg <= 'b0;
			wr_ptr    <= 'b0;
			rd_ptr    <= 'b0;
			i         <= 'b0;
			addr_cnt  <= 'b0;
		end
		else begin
			valid_reg <= s_axis_dsm_tvalid;
			tdata_reg <= s_axis_dsm_tdata;
			wr_ptr    <= wr_ptr_nxt;
			rd_ptr    <= rd_ptr_nxt;
			i         <= i_nxt;
			if(rd_ptr == wr_ptr)
                addr_cnt <= 'b0;
            else
                addr_cnt <= addr_cnt_nxt;
		end
	end 

	reg[63:0] wdata_reg;
	reg       wvalid_reg;
	reg[48:0] awaddr_reg;
	reg 	  awvalid_reg;
	reg[1:0]  bresp_reg;
	reg       bvalid_reg;
	reg [7:0] wstrb_reg;
 
	always @(*) begin
		wr_ptr_nxt = wr_ptr;
		rd_ptr_nxt = rd_ptr;
		i_nxt      = i;
		addr_cnt_nxt = addr_cnt;
		
		if(valid_reg) begin 
			wr_ptr_nxt = wr_ptr+1;
		end

		if(m_axi_dsm_awready && m_axi_dsm_wready && rd_ptr!=wr_ptr) begin
			rd_ptr_nxt  = i==7?(rd_ptr+1):rd_ptr;
			awvalid_reg = 1'b1;
			awaddr_reg  = phy_addr + addr_cnt;
			wvalid_reg  = 1'b1;
			wdata_reg   = dsm_data_fifo[rd_ptr[ADDR-1:0]][i*64+:64];
			wstrb_reg   = 8'hFF;
			addr_cnt_nxt= addr_cnt+8;
			i_nxt 		= i+1; 
		end
		else begin
		    awvalid_reg = 'b0; 
		    wvalid_reg  = 'b0;
		    wstrb_reg   = 'b0;
		end
	end

	assign m_axi_dsm_awvalid = awvalid_reg;
	assign m_axi_dsm_awaddr  = awaddr_reg;
	assign m_axi_dsm_wvalid  = wvalid_reg;
	assign m_axi_dsm_wdata   = wdata_reg;
	assign m_axi_dsm_bready  = 'b1;
	assign s_axis_dsm_tready = !full_flg;
	assign m_axi_dsm_wstrb   = wstrb_reg;
	assign m_axi_dsm_awprot  = 0;

endmodule : dsm_axis_aximm