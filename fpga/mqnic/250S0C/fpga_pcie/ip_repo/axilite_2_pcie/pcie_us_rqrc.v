/*

This file is adopted from Corundum NIC library and modified to accomodate SNIC-DSM needs. 

Copyright (c) 2021 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001 

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * Xilinx UltraScale PCIe interface adapter (Requester reQuest)
 */
module pcie_us_rqrc #
(
    parameter AXIS_PCIE_DATA_WIDTH = 512,
    parameter AXIS_PCIE_KEEP_WIDTH = (AXIS_PCIE_DATA_WIDTH/32), //16
    parameter AXIS_PCIE_RQ_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 60 : 137,
    parameter AXIS_PCIE_RC_USER_WIDTH = AXIS_PCIE_DATA_WIDTH < 512 ? 75 : 161,
    parameter TLP_SEG_COUNT = 1,
    parameter TLP_SEG_DATA_WIDTH = AXIS_PCIE_DATA_WIDTH/TLP_SEG_COUNT,
    parameter TLP_SEG_HDR_WIDTH = 128,
    parameter AXI_MM_DATA_WIDTH = 64

)
(
    input  wire                                          clk,
    input  wire                                          rst,

    /*
     * AXI output (RQ)
     */
    output wire [AXIS_PCIE_DATA_WIDTH-1:0]               m_axis_rq_tdata,
    output wire [63 : 0]                                 m_axis_rq_tkeep,
    output wire                                          m_axis_rq_tvalid,
    input  wire                                          m_axis_rq_tready,
    output wire                                          m_axis_rq_tlast,
    output wire [AXIS_PCIE_RQ_USER_WIDTH-1:0]            m_axis_rq_tuser,

    input wire [AXIS_PCIE_DATA_WIDTH-1:0]               s_axis_rc_tdata,
    input wire [AXIS_PCIE_KEEP_WIDTH-1:0]               s_axis_rc_tkeep,
    input wire                                          s_axis_rc_tvalid,
    output wire                                         s_axis_rc_tready,
    input wire                                          s_axis_rc_tlast,
    input wire [AXIS_PCIE_RC_USER_WIDTH-1:0]            s_axis_rc_tuser,
    
    /*Read address channel*/
    input wire [39:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    input wire [2:0] s_axi_arprot,
    
    /*Read data channel*/
    output wire [AXI_MM_DATA_WIDTH-1:0] s_axi_rdata,
    output wire s_axi_rvalid,
    output wire[1:0] s_axi_rresp,
    input wire s_axi_rready,
    
    /*Write data channel*/
    input wire[AXI_MM_DATA_WIDTH-1:0] s_axi_wdata, 
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    input wire [15:0] s_axi_wstrb,
    
    /*Write address channel*/
    input wire[39:0] s_axi_awaddr,
    input wire[2:0] s_axi_awprot,
    input wire s_axi_awvalid, 
    output wire s_axi_awready,
    
    /*Write response channel*/
    output wire [1 : 0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    
    input wire [511:0] cq_tdata_in,
    input wire         cq_actv,
    output wire [511:0] rq_data_out,
    output wire         rq_actv,
    
    /*Data from Prot proc to host to be sent over RQ interface*/
    input  wire [AXIS_PCIE_DATA_WIDTH-1:0]               s1_axis_tdata,
    input  wire [63:0]                                   s1_axis_tkeep,
    input  wire                                          s1_axis_tvalid,
    output wire                                          s1_axis_tready,
    input  wire                                          s1_axis_tlast,
    input  wire                                          s1_axis_tuser
    
);

localparam OUTPUT_FIFO_ADDR_WIDTH = 5;
localparam [3:0]
    REQ_MEM_READ = 4'b0000,
    REQ_MEM_WRITE = 4'b0001;
localparam [1:0]
    TLP_OUTPUT_STATE_IDLE = 2'd0,
    TLP_OUTPUT_STATE_RD_HEADER = 2'd1,
    TLP_OUTPUT_STATE_WR_HEADER = 2'd2,
    TLP_OUTPUT_STATE_WR_PAYLOAD = 2'd3;
    
reg tx_rd_req_tlp_ready_cmb;
reg tx_wr_req_tlp_ready_cmb;
reg [1:0] tlp_output_state_reg = TLP_OUTPUT_STATE_IDLE, tlp_output_state_next;
reg [TLP_SEG_COUNT*TLP_SEG_DATA_WIDTH-1:0] out_tlp_data_reg = 0, out_tlp_data_next;
reg [TLP_SEG_COUNT-1:0] out_tlp_eop_reg = 0, out_tlp_eop_next;
reg [127:0] tlp_header_data_rd;
reg [AXIS_PCIE_RQ_USER_WIDTH-1:0] tlp_tuser_rd = 0;
reg [127:0] tlp_header_data_wr;
reg [AXIS_PCIE_RQ_USER_WIDTH-1:0] tlp_tuser_wr = 0;
reg  [AXIS_PCIE_DATA_WIDTH-1:0]    m_axis_rq_tdata_int = 0;
reg  [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_rq_tkeep_int = 0;
reg                                m_axis_rq_tvalid_int = 0;
wire                               m_axis_rq_tready_int;
reg                                m_axis_rq_tlast_int = 0;
reg [AXIS_PCIE_RQ_USER_WIDTH-1:0]  m_axis_rq_tuser_int = 0;
reg [1:0]axi_bresp = 0;
reg axi_awready;
reg axi_bvalid = 0;
reg axi_wready;
reg [39:0] axi_awaddr;
wire slv_reg_wren;
reg axi_arready;
reg [39:0] axi_araddr;
reg [3:0] tag_data = 0;
reg cnt = 1'b0;
reg [63:0] phy_addr = 64'd0;
reg [2:0] i=0, i_nxt = 0;

assign s_axi_arready = tx_rd_req_tlp_ready_cmb;
assign s_axi_wready = tx_wr_req_tlp_ready_cmb;
assign s_axi_awready = tx_wr_req_tlp_ready_cmb;

always @(posedge clk) begin
    if(!rst) begin
        phy_addr[63:0] <= 'b0;
            cnt <= 'b0;
   end
    if(cq_actv && cq_tdata_in[191:128] != 64'hfefefefe && cnt != 1'b1) begin //&& cq_tdata_in[63:2] == 'h6000000000 
            phy_addr[63:0] <= cq_tdata_in[191:128];
            cnt <= 1'b1;
    end
    else if(cq_actv && cq_tdata_in[191:128] == 64'hfefefefe) begin // && cnt == 1'b1 //&& cq_tdata_in[63:2] == 'h6000000000 
            cnt <= 1'b0;
    end
end

/*Sync FIFO implementation for DSM processor data*/
localparam WIDE = 512;
localparam DEEP = 128;
localparam ADDR_WIDTH = $clog2(DEEP);

(* ram_style = "distributed" *)
reg [WIDE-1:0]    in_fifo_tdata_tval[DEEP-1:0];
reg [ADDR_WIDTH:0] wr_ptr;
reg [ADDR_WIDTH:0] rd_ptr='b0;
reg [ADDR_WIDTH:0] wr_ptr_nxt;
reg [ADDR_WIDTH:0] rd_ptr_nxt;
reg valid_reg;
reg [511:0] tdata_reg;
wire full_flg = (wr_ptr == (rd_ptr ^ {1'b1, {ADDR_WIDTH-1{1'b0}}}));
wire empty_flg = (wr_ptr == rd_ptr);
reg [63:0] phy_addr_cur, phy_addr_nxt; 

always @(posedge clk) begin
   if(valid_reg) begin
        in_fifo_tdata_tval[wr_ptr[ADDR_WIDTH-1:0]] <= tdata_reg;
   end 
end

always @(posedge clk) begin 
    if(!rst) begin
        wr_ptr <= {ADDR_WIDTH+1{1'b0}};
        rd_ptr <= {ADDR_WIDTH+1{1'b0}};
        valid_reg <= 'b0;
        i <= 0;
        tdata_reg <= 'b0;
        phy_addr_cur <= 'b0;
    end
    else begin 
        wr_ptr <= wr_ptr_nxt;
        rd_ptr <= rd_ptr_nxt;
        i <= i_nxt;
        valid_reg <= s1_axis_tvalid;
        tdata_reg <= s1_axis_tdata;
        if(rd_ptr == wr_ptr)
            phy_addr_cur <= 'b0;
        else
            phy_addr_cur <= phy_addr_nxt;
    end

end

always @* begin
    
    wr_ptr_nxt = wr_ptr;
    rd_ptr_nxt = rd_ptr; 
    i_nxt = i; 
    phy_addr_nxt = phy_addr_cur;
    tx_rd_req_tlp_ready_cmb = 1'b0;
    tx_wr_req_tlp_ready_cmb = 1'b0;
   
    /*Memory Read TLP header*/
    tlp_header_data_rd[63:0] =  phy_addr + s_axi_araddr[23:0]; //read memory address
    tlp_header_data_rd[74:64] = 11'h002; // DWORD count
    tlp_header_data_rd[78:75] = REQ_MEM_READ; // request type - memory read
    tlp_header_data_rd[79] = 1'b0; // poisoned request
    tlp_header_data_rd[95:80] = {8'd0, 5'd0, 3'd0}; // requester ID
    tlp_header_data_rd[103:96] = {4'hF, tag_data}; // tag //redefine
    tlp_header_data_rd[119:104] = 16'd0; // completer ID
    tlp_header_data_rd[120] = 1'b0; // requester ID enable
    tlp_header_data_rd[123:121] = 3'd0; // traffic class
    tlp_header_data_rd[126:124] = 3'd0; // attr
    tlp_header_data_rd[127] = 1'b0; // force ECRC

    if (AXIS_PCIE_DATA_WIDTH == 512) begin
        tlp_tuser_rd[3:0] = 4'hf; // first BE 0
        tlp_tuser_rd[7:4] = 4'h0; // first BE 1
        tlp_tuser_rd[11:8] = 4'hf;// last BE 0
        tlp_tuser_rd[15:12] = 4'h0; // last BE 1
        tlp_tuser_rd[19:16] = 3'd0; // addr_offset
        tlp_tuser_rd[21:20] = 2'b01; // is_sop //was 01
        tlp_tuser_rd[23:22] = 2'd0; // is_sop0_ptr
        tlp_tuser_rd[25:24] = 2'd0; // is_sop1_ptr
        tlp_tuser_rd[27:26] = 2'b01; // is_eop //was 01
        tlp_tuser_rd[31:28]  = 4'd3; // is_eop0_ptr//4
        tlp_tuser_rd[35:32] = 4'd0; // is_eop1_ptr
        tlp_tuser_rd[36] = 1'b0; // discontinue
        tlp_tuser_rd[38:37] = 2'b00; // tph_present
        tlp_tuser_rd[42:39] = 4'b0000; // tph_type
        tlp_tuser_rd[44:43] = 2'b00; // tph_indirect_tag_en
        tlp_tuser_rd[60:45] = 16'd0; // tph_st_tag
        tlp_tuser_rd[66:61] = 6'd0; // seq_num0
        tlp_tuser_rd[72:67] = 6'd0; // seq_num1
        tlp_tuser_rd[136:73] = 64'd0; // parity
    end
    else begin
        tlp_tuser_rd = 'b0;
    end
    
    /*Memory write TLP header*/
    tlp_header_data_wr[63:0] = phy_addr + s_axi_awaddr[23:0]; //write memory address
    tlp_header_data_wr[74:64] = 11'h002; // DWORD count
    tlp_header_data_wr[78:75] = REQ_MEM_WRITE; // request type - memory write
    tlp_header_data_wr[79] = 1'b0; // poisoned request
    tlp_header_data_wr[95:80] = {8'h00, 5'b00000, 3'b000}; // requester ID
    tlp_header_data_wr[103:96] = 8'd0; // tag
    tlp_header_data_wr[119:104] = 16'd0; // completer ID
    tlp_header_data_wr[120] = 1'b0; // requester ID enable
    tlp_header_data_wr[123:121] = 3'd0; // traffic class
    tlp_header_data_wr[126:124] = 3'd0;// attr
    tlp_header_data_wr[127] = 1'b0; // force ECRC

    if (AXIS_PCIE_DATA_WIDTH == 512) begin
        tlp_tuser_wr[3:0] = 4'hf;// first BE 0
        tlp_tuser_wr[7:4] = 4'h0; // first BE 1
        tlp_tuser_wr[11:8] = 4'hf; // last BE 0
        tlp_tuser_wr[15:12] = 4'h0; // last BE 1
        tlp_tuser_wr[19:16] = 3'd0; // addr_offset
        tlp_tuser_wr[21:20] = 2'b01; // is_sop
        tlp_tuser_wr[23:22] = 2'd0; // is_sop0_ptr
        tlp_tuser_wr[25:24] = 2'd0; // is_sop1_ptr
        tlp_tuser_wr[27:26] = 2'b01; // is_eop
        tlp_tuser_wr[31:28]  = 4'd5; // is_eop0_ptr//5
        tlp_tuser_wr[35:32] = 4'd0; // is_eop1_ptr
        tlp_tuser_wr[36] = 1'b0; // discontinue
        tlp_tuser_wr[38:37] = 2'b00; // tph_present
        tlp_tuser_wr[42:39] = 4'b0000; // tph_type
        tlp_tuser_wr[44:43] = 2'b00; // tph_indirect_tag_en
        tlp_tuser_wr[60:45] = 16'd0; // tph_st_tag
        tlp_tuser_wr[66:61] = 6'd0; // seq_num0
        tlp_tuser_wr[72:67] = 6'd0; // seq_num1
        tlp_tuser_wr[136:73] = 64'd0; // parity
    end
    else begin 
        tlp_tuser_wr = 'b0;
    end
    
    /*Logic to for data packets for transmission to the host*/
          if(!full_flg && valid_reg && m_axis_rq_tready_int) begin
                    wr_ptr_nxt = wr_ptr + {{ADDR_WIDTH{1'b0}}, 1'b1};
          end
            
          if(!empty_flg && m_axis_rq_tready_int && (rd_ptr != wr_ptr)) begin 
                    rd_ptr_nxt = (i==7)?(rd_ptr+1):rd_ptr;
                    m_axis_rq_tdata_int = {320'b0, in_fifo_tdata_tval[rd_ptr[ADDR_WIDTH-1:0]][(i*64) +: 64], tlp_header_data_wr[127:64], phy_addr+phy_addr_cur};
                    m_axis_rq_tkeep_int = 16'h003F;
                    m_axis_rq_tvalid_int = 1'b1;
                    m_axis_rq_tlast_int = 1'b1;
                    m_axis_rq_tuser_int = tlp_tuser_wr;
                    tx_wr_req_tlp_ready_cmb = 1'b1;
                    phy_addr_nxt = phy_addr_cur+8;
                    i_nxt = i+1;
           end
         
           else if (s_axi_arvalid && m_axis_rq_tready_int) begin
                    // wider interface, send complete header (read request)
                    m_axis_rq_tdata_int = tlp_header_data_rd;
                    m_axis_rq_tkeep_int = 16'h000F;
                    m_axis_rq_tvalid_int = 1'b1;
                    m_axis_rq_tlast_int = 1'b1;
                    m_axis_rq_tuser_int = tlp_tuser_rd;
                    if (tag_data == 15) begin
                        tag_data = 4'd0;
                    end 
                    else begin 
                        tag_data = tag_data + 1;
                    end 
                    tx_rd_req_tlp_ready_cmb = 1'b1;
            end 
            else if (s_axi_awvalid && s_axi_wvalid && m_axis_rq_tready_int) begin
                    // wider interface, send header and start of payload (write request)
                    m_axis_rq_tdata_int = {s_axi_wdata, tlp_header_data_wr};
                    m_axis_rq_tkeep_int = 16'h003F;
                    m_axis_rq_tvalid_int = 1'b1;
                    m_axis_rq_tlast_int = 1'b1;
                    m_axis_rq_tuser_int = tlp_tuser_wr;
                    tx_wr_req_tlp_ready_cmb = 1'b1;
            end 
            else begin 
                // TLP output
                m_axis_rq_tdata_int  = 'b0;
                m_axis_rq_tkeep_int  = 'b0;
                m_axis_rq_tvalid_int = 'b0;
                m_axis_rq_tlast_int  = 'b0;
                m_axis_rq_tuser_int  = 'b0;
            end
end

// output datapath logic (PCIe TLP)
reg [AXIS_PCIE_DATA_WIDTH-1:0]    m_axis_rq_tdata_reg = {AXIS_PCIE_DATA_WIDTH{1'b0}};
reg [AXIS_PCIE_KEEP_WIDTH-1:0]    m_axis_rq_tkeep_reg = {AXIS_PCIE_KEEP_WIDTH{1'b0}};
reg                               m_axis_rq_tvalid_reg = 1'b0, m_axis_rq_tvalid_next;
reg                               m_axis_rq_tlast_reg = 1'b0;
reg [AXIS_PCIE_RQ_USER_WIDTH-1:0] m_axis_rq_tuser_reg = {AXIS_PCIE_RQ_USER_WIDTH{1'b0}};
reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_wr_ptr_reg = 0;
reg [OUTPUT_FIFO_ADDR_WIDTH+1-1:0] out_fifo_rd_ptr_reg = 0;
reg out_fifo_half_full_reg = 1'b0;

wire out_fifo_full = out_fifo_wr_ptr_reg == (out_fifo_rd_ptr_reg ^ {1'b1, {OUTPUT_FIFO_ADDR_WIDTH{1'b0}}});
wire out_fifo_empty = out_fifo_wr_ptr_reg == out_fifo_rd_ptr_reg;

(* ram_style = "distributed" *)
reg [AXIS_PCIE_DATA_WIDTH-1:0]    out_fifo_tdata[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed" *)
reg [AXIS_PCIE_KEEP_WIDTH-1:0]    out_fifo_tkeep[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed" *)
reg                               out_fifo_tlast[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];
(* ram_style = "distributed" *)
reg [AXIS_PCIE_RQ_USER_WIDTH-1:0] out_fifo_tuser[2**OUTPUT_FIFO_ADDR_WIDTH-1:0];

assign m_axis_rq_tready_int = !out_fifo_half_full_reg;
assign s1_axis_tready = m_axis_rq_tready;
assign m_axis_rq_tdata = m_axis_rq_tdata_reg;
assign m_axis_rq_tkeep = {48'd0, m_axis_rq_tkeep_reg};
assign m_axis_rq_tvalid = m_axis_rq_tvalid_reg;
assign m_axis_rq_tlast = m_axis_rq_tlast_reg;
assign m_axis_rq_tuser = m_axis_rq_tuser_reg;
assign s_axi_bvalid = axi_bvalid;
assign s_axi_bresp = axi_bresp;
assign rq_data_out = m_axis_rq_tdata;
assign rq_actv = m_axis_rq_tvalid;

always @(posedge clk) begin
    m_axis_rq_tvalid_reg <= m_axis_rq_tvalid_reg && !m_axis_rq_tready;
    axi_bvalid <= axi_bvalid && !m_axis_rq_tready;

    out_fifo_half_full_reg <= $unsigned(out_fifo_wr_ptr_reg - out_fifo_rd_ptr_reg) >= 2**(OUTPUT_FIFO_ADDR_WIDTH-1);

    if (!out_fifo_full && m_axis_rq_tvalid_int) begin
        out_fifo_tdata[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_rq_tdata_int;
        out_fifo_tkeep[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_rq_tkeep_int;
        out_fifo_tlast[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_rq_tlast_int;
        out_fifo_tuser[out_fifo_wr_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]] <= m_axis_rq_tuser_int;
        out_fifo_wr_ptr_reg <= out_fifo_wr_ptr_reg + 1;
    end

    if (!out_fifo_empty && (!m_axis_rq_tvalid_reg || m_axis_rq_tready)) begin
        m_axis_rq_tdata_reg <= out_fifo_tdata[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_rq_tkeep_reg <= out_fifo_tkeep[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_rq_tvalid_reg <= 1'b1;
        m_axis_rq_tlast_reg <= out_fifo_tlast[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        m_axis_rq_tuser_reg <= out_fifo_tuser[out_fifo_rd_ptr_reg[OUTPUT_FIFO_ADDR_WIDTH-1:0]];
        out_fifo_rd_ptr_reg <= out_fifo_rd_ptr_reg + 1;
        axi_bvalid <= 1'b1;
        axi_bresp <= 2'b0;
    end
    
    if (!rst) begin
        out_fifo_wr_ptr_reg <= 0;
        out_fifo_rd_ptr_reg <= 0;
        m_axis_rq_tvalid_reg <= 1'b0;
        axi_bvalid <= 1'b0;
        axi_bresp <= 2'b0;
    end
end

reg [AXI_MM_DATA_WIDTH-1 : 0] 	  axi_rdata;
reg [1 : 0] 	                  axi_rresp;
reg  	                          axi_rlast;
reg  	                          axi_rvalid;

/*Read logic implementation*/
assign s_axi_rdata	= axi_rdata;
assign s_axi_rresp	= axi_rresp;
assign s_axi_rvalid	= axi_rvalid;
assign s_axis_rc_tready = s_axi_rready;

always @(posedge clk or negedge rst) begin 
    if(!rst) begin 
        axi_rdata <= 64'd0;
        axi_rvalid = 1'b0;
        axi_rresp = 1'b0;
    end
    else if(s_axis_rc_tvalid && ~axi_rvalid) begin
        axi_rdata <= s_axis_rc_tdata[159:96]; 
        axi_rvalid = 1'b1;
        axi_rresp = 1'b0;
    end
    else begin
        axi_rvalid = 1'b0;
        axi_rresp = 1'b0; 
    end
end
endmodule

`resetall