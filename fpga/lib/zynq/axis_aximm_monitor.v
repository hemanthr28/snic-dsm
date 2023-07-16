`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 02/03/2023 10:54:22 AM
// Design Name: 
// Module Name: axis_aximm_monitor
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module axis_aximm_monitor #(
    parameter proc_req_id = 32'h70747072 //hex of 'ptpr' - protocol processor. Used to identify prot proc messages.
 )

(    
    input wire clk, 
    input wire rst,
    
    /*Input from the CQ interface*/
    input  wire [511:0]s_axis_tdata,
    input  wire        s_axis_tvalid,  
    input  wire [63:0] s_axis_tkeep, 
    input  wire        s_axis_tlast,
    input  wire [182:0]s_axis_tuser,
    output wire        s_axis_tready,

    /*Output passthrough for CQ*/
    output  wire [511:0]m0_axis_tdata,
    output  wire        m0_axis_tvalid,  
    output  wire [63:0] m0_axis_tkeep, 
    output  wire        m0_axis_tlast,
    output  wire [182:0]m0_axis_tuser,
    input   wire        m0_axis_tready,

    /*Output to be sent over CC interface for memory read's to the host (recived from aximm)*/
    output  wire [511:0]m_axis_tdata,
    output  wire        m_axis_tvalid,  
    output  wire [63:0] m_axis_tkeep, 
    output  wire        m_axis_tlast,
    output  wire [80:0]m_axis_tuser,
    input wire          m_axis_tready,
    
    /*Output to the axi-mm of protocol processor*/
    output wire [7:0] m_axi_awaddr,
    output wire       m_axi_awvalid,
    output wire [2:0] m_axi_awprot,
    input  wire       m_axi_awready,
    
    output wire [31:0]m_axi_wdata,
    output wire [3:0] m_axi_wstrb,	
    output wire       m_axi_wvalid,	
    input  wire       m_axi_wready,
    
    input  wire [1:0] m_axi_bresp,
    input  wire       m_axi_bvalid,	
    output wire       m_axi_bready,
    
    output wire [7:0] m_axi_araddr,
    output wire [2:0] m_axi_arprot,
    output wire       m_axi_arvalid,
    input  wire       m_axi_arready,
    
    input  wire [31:0]m_axi_rdata,
    input  wire [1:0] m_axi_rresp,	
    input  wire       m_axi_rvalid,	
    output wire       m_axi_rready
    
    );
    
  wire [31:0] dw1_header_32;
  wire [31:0] dw2_header_32;
  wire [31:0] dw3_header_32;
  
  wire [6:0]  tag_mang_lower_addr_rd;
  wire [15:0] tag_mang_requester_id_rd;
  wire [2:0]  tag_mang_attr_rd;
  wire [2:0]  tag_mang_tc_rd;
  wire [7:0]  tag_mang_tag_rd;
  wire tag_mang_write_en;
  wire tag_mang_read_en;

     tag_manager tag_man_inst(.clk(clk), .reset_n(rst), .tag_mang_write_en(), .tag_mang_tc_wr(s_axis_tdata[123:121]), .tag_mang_attr_wr(s_axis_tdata[126:124]), 
                              .tag_mang_requester_id_wr(s_axis_tdata[95:80]), .tag_mang_lower_addr_wr(s_axis_tdata[6:0]), .tag_mang_completer_func_wr(s_axis_tdata[104]),
                              .tag_mang_tag_wr(s_axis_tdata[103:96]), .tag_mang_first_be_wr({s_axis_tuser[3:0], s_axis_tuser[11:8]}), 
                              .tag_mang_read_en(), .tag_mang_tc_rd(tag_mang_tc_rd), .tag_mang_attr_rd(tag_mang_attr_rd), .tag_mang_requester_id_rd(tag_mang_requester_id_rd), .tag_mang_lower_addr_rd(tag_mang_lower_addr_rd), 
                              .tag_mang_completer_func_rd(), .tag_mang_tag_rd(tag_mang_tag_rd), .tag_mang_first_be_rd());

    /*Internal registers to hold incoming values*/    
     reg [7:0]  m_axi_awaddr_reg;
     reg        m_axi_awvalid_reg;

     reg [31:0] m_axi_wdata_reg;
     reg [3:0]  m_axi_wstrb_reg;
     reg        m_axi_wvalid_reg;

     reg        m_axi_bready_reg;

     reg [7:0]  m_axi_araddr_reg;
     reg [2:0]  m_axi_arprot_reg;
     reg        m_axi_arvalid_reg;

     reg        m_axi_rready_reg;

     reg [511:0] m_axis_tdata_reg;
     reg         m_axis_tvalid_reg;
     reg [63:0]  m_axis_tkeep_reg;
     reg         m_axis_tlast_reg;
     reg [160:0] m_axis_tuser_reg;

     reg [511:0] m0_axis_tdata_reg;
     reg         m0_axis_tvalid_reg;
     reg [63:0]  m0_axis_tkeep_reg;
     reg         m0_axis_tlast_reg;
     reg [182:0] m0_axis_tuser_reg;
     
    always @(posedge clk) begin 
        if(!rst) begin
            m_axi_awaddr_reg     <= 'b0;
            m_axi_awvalid_reg    <= 'b0;
            m_axi_wdata_reg      <= 'b0;
            m_axi_wstrb_reg      <= 'b0;
            m_axi_wvalid_reg     <= 'b0;
            m_axi_bready_reg     <= 'b0;
            m_axi_araddr_reg     <= 'b0;
            m_axi_arvalid_reg    <= 'b0;
            m_axi_rready_reg     <= 'b0;
            
            m0_axis_tdata_reg    <= 'b0; 
            m0_axis_tvalid_reg   <= 'b0;
            m0_axis_tkeep_reg    <= 'b0;
            m0_axis_tlast_reg    <= 'b0;
            m0_axis_tuser_reg    <= 'b0;
            
        end
        else begin 
            if(m_axi_awvalid & m_axi_wvalid & (m_axi_wready | m_axi_bvalid)) begin 
                m_axi_awvalid_reg <= 'b0;
                m_axi_wvalid_reg  <= 'b0;
            end 

            if(m_axi_arready | m_axi_rvalid) begin 
                m_axi_arvalid_reg <='b0;
            end 

            /*Used only for writing to the axi registers*/
            if(s_axis_tvalid & (s_axis_tdata[159:128] == proc_req_id) & (s_axis_tdata[78:75] == 4'b0001) & s_axis_tdata[23]) begin /*Write request*/
            
                m0_axis_tvalid_reg   <= 'b0;

                m_axi_awaddr_reg     <= s_axis_tdata[9:2]; //63:2 are address bits in cq axis
                m_axi_awvalid_reg    <= s_axis_tvalid;                
                m_axi_wdata_reg      <= s_axis_tdata[191:160];
                m_axi_wstrb_reg      <= {4{s_axis_tkeep[5]}}; //6th Dowrd is the write data
                m_axi_wvalid_reg     <= s_axis_tvalid;
                m_axi_bready_reg     <= s_axis_tlast; //If tlast is set then get ready to get the response from slave
            end
            
            /*Used only for reading from the axi registers*/
            else if(s_axis_tvalid & (s_axis_tdata[78:75] == 4'b0000) & s_axis_tdata[23]) begin //Read request and using only 23rd bit of tdata to distinguish between protocol processor req and Zynq memory read request.
            /*The host must always send the request with the 23rd address bit set for the protocol requester to perform a read operation.*/
              
                m0_axis_tvalid_reg   <= 'b0;
                
                m_axi_araddr_reg     <= s_axis_tdata[9:2];
                m_axi_arvalid_reg    <= s_axis_tvalid;
                m_axi_rready_reg     <= m_axis_tready;
            end
            
            else if (s_axis_tvalid)begin 
                m_axi_awvalid_reg    <= 'b0;
                m_axi_wvalid_reg     <= 'b0;
                m_axi_arvalid_reg    <= 'b0;
                
                m0_axis_tdata_reg    <= s_axis_tdata;
                m0_axis_tvalid_reg   <= s_axis_tvalid;
                m0_axis_tkeep_reg    <= s_axis_tkeep;
                m0_axis_tlast_reg    <= s_axis_tlast;
                m0_axis_tuser_reg    <= s_axis_tuser;
            end

            else begin 
                m0_axis_tvalid_reg   <= 'b0;
            end 
        end 
    end

    /*Read request must reach the host through CC interface*/
    always @(posedge clk) begin 
        if (!rst) begin
            m_axis_tdata_reg  <= 'b0;
            m_axis_tvalid_reg <= 'b0;
            m_axis_tkeep_reg  <= 'b0;
            m_axis_tlast_reg  <= 'b0;
            m_axis_tuser_reg  <= 'b0;
        end 
        else if (m_axi_rvalid) begin 
            m_axis_tdata_reg  <= {256'b0, m_axi_rdata, dw3_header_32, dw2_header_32, dw1_header_32};
            m_axis_tvalid_reg <= m_axi_rvalid;
            m_axis_tkeep_reg  <= {48'b0, 16'h1f}; //Update if needed
            m_axis_tlast_reg  <= m_axi_rvalid; //Update if needed
            m_axis_tuser_reg  <= 'b0; //Update as per the CC interface requirements
        end
        else begin
            m_axis_tdata_reg  <= 'b0;
            m_axis_tvalid_reg <= 'b0;
            m_axis_tkeep_reg  <= 'b0;
            m_axis_tlast_reg  <= 'b0;
            m_axis_tuser_reg  <= 'b0;
        end
    end 

    assign m_axi_awaddr  = m_axi_awaddr_reg;
    assign m_axi_awvalid = m_axi_awvalid_reg;

    assign m_axi_wdata   = m_axi_wdata_reg;
    assign m_axi_wstrb   = m_axi_wstrb_reg;
    assign m_axi_wvalid  = m_axi_wvalid_reg; 
    assign m_axi_bready  = m_axi_bready_reg;
    assign m_axi_araddr  = m_axi_araddr_reg;
    assign m_axi_arvalid = m_axi_arvalid_reg;    

    assign m_axi_rready  = m_axi_rready_reg;
    
    assign dw1_header_32           = { 12'd0 ,4'd8 , 9'd0, tag_mang_lower_addr_rd };
    assign dw2_header_32           = { tag_mang_requester_id_rd, 2'b0, 3'b000, 11'd2 };
    assign dw3_header_32           = { 1'b0, tag_mang_attr_rd, tag_mang_tc_rd, 1'd0, 16'd0, tag_mang_tag_rd };
    assign tag_mang_write_en       = (s_axis_tdata[10+64:0+64] == 11'd2 || s_axis_tdata[10+64:0+64] == 11'd1);
    assign tag_mang_read_en        = m_axi_rvalid & m_axis_tready;
    
    /*AXIS for read data*/
    assign m_axis_tdata  = m_axis_tdata_reg;
    assign m_axis_tvalid = m_axis_tvalid_reg;
    assign m_axis_tkeep  = m_axis_tkeep_reg;
    assign m_axis_tlast  = m_axis_tlast_reg;
    assign m_axis_tuser  = m_axis_tuser_reg;
    
    /*Pass through for CQ*/
    assign m0_axis_tdata  = m0_axis_tdata_reg; 
    assign m0_axis_tvalid = m0_axis_tvalid_reg;
    assign m0_axis_tkeep  = m0_axis_tkeep_reg;
    assign m0_axis_tlast  = m0_axis_tlast_reg;
    assign m0_axis_tuser  = m0_axis_tuser_reg;
    assign s_axis_tready  = m0_axis_tready;

endmodule

module tag_manager # (
  parameter TCQ           = 1,
  parameter RAM_ADDR_BITS = 5
)(
  input                     clk,
  input                     reset_n,
  
  input                     tag_mang_write_en,
  
  input [2:0]               tag_mang_tc_wr,             //[15:0]
  input [2:0]               tag_mang_attr_wr,           //[15:0]
  input [15:0]              tag_mang_requester_id_wr,   //[15:0]
  input [6:0]               tag_mang_lower_addr_wr,     //[6:0]
  input                     tag_mang_completer_func_wr, //[0:0]
  input [7:0]               tag_mang_tag_wr,            //[7:0]
  input [3:0]               tag_mang_first_be_wr,       //[2:0]
     
  input                     tag_mang_read_en,         
       
  output [2:0]              tag_mang_tc_rd,   //[15:0]
  output [2:0]              tag_mang_attr_rd,   //[15:0]
  output [15:0]             tag_mang_requester_id_rd,   //[15:0]
  output [6:0]              tag_mang_lower_addr_rd,     //[6:0]
  output                    tag_mang_completer_func_rd, //[0:0]
  output [7:0]              tag_mang_tag_rd,            //[7:0]
  output [3:0]              tag_mang_first_be_rd      //[2:0]
    );

    
  reg [RAM_ADDR_BITS-1:0] tag_mang_write_id;      
  reg [RAM_ADDR_BITS-1:0] tag_mang_read_id;        

  always @( posedge clk )
    if  ( !reset_n ) 
      tag_mang_write_id <= #TCQ 1;
    else if ( tag_mang_write_en ) 
      tag_mang_write_id <= #TCQ tag_mang_write_id + 1;   
      
  always @( posedge clk )
    if  ( !reset_n ) 
      tag_mang_read_id <= #TCQ 0;
    else if ( tag_mang_read_en ) 
      tag_mang_read_id <= #TCQ tag_mang_read_id + 1;
            
            
   localparam RAM_WIDTH = 42;

   (* RAM_STYLE="distributed" *)
   reg [RAM_WIDTH-1:0] tag_storage [(2**RAM_ADDR_BITS)-1:0];

   wire [RAM_WIDTH-1:0] completion_data;

   always @(posedge clk)
      if (tag_mang_write_en)
         tag_storage[tag_mang_write_id] <= #TCQ { tag_mang_attr_wr, tag_mang_tc_wr, tag_mang_requester_id_wr, tag_mang_lower_addr_wr, tag_mang_completer_func_wr, tag_mang_tag_wr, tag_mang_first_be_wr};

   assign completion_data = tag_storage[tag_mang_read_id];
   
   assign tag_mang_attr_rd           = completion_data[41:39];
   assign tag_mang_tc_rd             = completion_data[38:36];
   assign tag_mang_requester_id_rd   = completion_data[35:20];     //[15:0]
   assign tag_mang_lower_addr_rd     = completion_data[19:13];     //[6:0]
   assign tag_mang_completer_func_rd = completion_data[12];        //[0:0]
   assign tag_mang_tag_rd            = completion_data[11:4];      //[7:0]
   assign tag_mang_first_be_rd       = completion_data[3:0];       //[2:0]        



    
endmodule


