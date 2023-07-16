`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/10/2021 12:21:16 PM
// Design Name: 
// Module Name: stream_monitor
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


module axis_switch # 
(
    parameter prot_proc_request = 'h0ADDBEEFDEADBEEF,
    parameter to_fifo = 2'b00,
    parameter to_proc = 2'b01
)
(
    input CLK,
    input RST,
    
    //AXIS Input Ports
    input wire [511:0]  s00_axis_tdata,
    input wire          s00_axis_tlast,
    input wire          s00_axis_tvalid,
    input wire [63:0]   s00_axis_tkeep,
    input wire [136:0]  s00_axis_tuser,
    output reg          s00_axis_tready, 
    
    input wire [511:0]  s01_axis_tdata,
    input wire          s01_axis_tlast,
    input wire          s01_axis_tvalid,
    input wire [63:0]   s01_axis_tkeep,
    input wire [136:0]  s01_axis_tuser,
    output reg          s01_axis_tready,
    
    //AXIS Output Ports 
    
    output wire [511:0] m00_axis_tdata,
    output wire	        m00_axis_tlast,
    output wire	        m00_axis_tvalid,
    output wire [63:0]  m00_axis_tkeep,
    output wire [136:0] m00_axis_tuser,
    input               m00_axis_tready
        
    );
    
reg [1:0] state;

reg         m0_axis_tlast_reg;
reg [511:0] m0_axis_tdata_reg;
reg [63:0]  m0_axis_tkeep_reg;
reg         m0_axis_tvalid_reg;
reg [136:0] m0_axis_tuser_reg;

assign m00_axis_tdata = m0_axis_tdata_reg;
assign m00_axis_tlast = m0_axis_tlast_reg;
assign m00_axis_tkeep = m0_axis_tkeep_reg;
assign m00_axis_tvalid = m0_axis_tvalid_reg;
assign m00_axis_tuser = m0_axis_tuser_reg;

 
always @(posedge CLK) begin
    if(RST == 0) begin
        s00_axis_tready     <= 'b0;
        s01_axis_tready     <= 'b0;
        m0_axis_tlast_reg   <= 'b0;
        m0_axis_tvalid_reg  <= 'b0; 
        m0_axis_tdata_reg   <= 'b0;
        m0_axis_tkeep_reg   <= 'b0;
        m0_axis_tuser_reg   <= 'b0;
    
    end
    else begin
        s00_axis_tready <= 1;
        s01_axis_tready <= 1;
        if (s00_axis_tvalid == 1) begin
            m0_axis_tdata_reg  <= s00_axis_tdata;
            m0_axis_tvalid_reg <= s00_axis_tvalid;
            m0_axis_tkeep_reg  <= s00_axis_tkeep;
            m0_axis_tuser_reg  <= s00_axis_tuser;
            m0_axis_tlast_reg  <= s00_axis_tlast;
        end
        else if (s01_axis_tvalid == 1) begin
            m0_axis_tdata_reg  <= s01_axis_tdata;
            m0_axis_tvalid_reg <= s01_axis_tvalid;
            m0_axis_tkeep_reg  <= s01_axis_tkeep;
            m0_axis_tuser_reg  <= s01_axis_tuser;
            m0_axis_tlast_reg  <= s01_axis_tlast;
        end
        else begin
            m0_axis_tlast_reg  <= 'b0;
            m0_axis_tvalid_reg <= 'b0; 
            m0_axis_tdata_reg  <= 'b0;
            m0_axis_tkeep_reg  <= 'b0;
            m0_axis_tuser_reg  <= 'b0;
        end
    end
end
    
endmodule //axis_switch
