/*This is a Round Robin arbitrator module. This was intended to be used instead of AXIS
interconnect. The arbitration works well. But the when batching the Zynq and Corundum requests,
the arbitration doesn't work as expected. This can be further improved and can replace the 
AXIS interconnect. */

/*Need to test if this modules improves the throughput compared to Xilinx's AXIS interconnect.*/
`resetall
`timescale 1ns / 1ps
`default_nettype none

module pri_encoder(
  input wire [3:0] req,
  output wire [3:0] grant
  
);
  
  wire [3:0] high_pri_req;
  
  assign high_pri_req[3:1] = high_pri_req[2:0] | req[2:0];
  assign high_pri_req[0] = 1'b0;
  assign grant[3:0] = req[3:0] & ~(high_pri_req[3:0]);
 
endmodule

module rr (
  input wire clk,
  input wire rst,
  input wire[3:0] req,
  output reg[3:0] grant
  
);
  //localparam MAX = 512;
  
  wire [7:0] double_reg;
  wire [3:0] rot_req;
  wire [3:0] grant_temp;
  reg [1:0] pointer_req;
  //reg [9:0] cnt = 'b0;
  
  always @ (posedge clk) begin 
    if (!rst) pointer_req <= 2'd0;
    
    case(1'b1) // & cnt >= MAX) 
      grant[0]: begin 
            pointer_req <= 2'd1;
            //cnt <= 'b0;
      end
      grant[1]: begin 
            pointer_req <= 2'd2;
            //cnt <= 'b0;
      end
      grant[2]: begin 
            pointer_req <= 2'd3;
            //cnt <= 'b0;
      end
      grant[3]: begin 
            pointer_req <= 2'd0;
            //cnt <= 'b0;
      end
    endcase

  end
  
  assign double_reg = {req, req} >> pointer_req;
  assign rot_req = double_reg[3:0];
  
  pri_encoder inst(.req(rot_req), .grant(grant_temp));
  
  
  always @(posedge clk) begin 
    if (!rst) grant = 4'd0;
    //else if(cnt == 0)
    grant <= grant_temp << pointer_req;
    //else 
    //    cnt <= |req ? cnt + 1 : cnt; 
  end  
endmodule

module taxis_arb (
    input wire clk, 
    input wire rst,
    
    input wire [511:0] s0_axis_tdata, 
    input wire         s0_axis_tlast, 
    input wire         s0_axis_tvalid,
    output wire        s0_axis_tready,
    input wire [63:0]  s0_axis_tkeep,
    input wire [136:0] s0_axis_tuser,
    
    input wire [511:0] s1_axis_tdata, 
    input wire         s1_axis_tlast, 
    input wire         s1_axis_tvalid,
    output wire        s1_axis_tready,
    input wire [63:0]  s1_axis_tkeep,
    input wire [136:0] s1_axis_tuser,
    
    input wire [511:0] s2_axis_tdata, 
    input wire         s2_axis_tlast, 
    input wire         s2_axis_tvalid,
    output wire        s2_axis_tready,
    input wire [63:0]  s2_axis_tkeep,
    input wire [136:0] s2_axis_tuser,
    
    output wire [511:0] m0_axis_tdata, 
    output wire         m0_axis_tlast, 
    output wire         m0_axis_tvalid,
    input  wire         m0_axis_tready,
    output wire [63:0]  m0_axis_tkeep,
    output wire [136:0] m0_axis_tuser
);

wire [3:0] grant;
reg [511:0]  m0_axis_tdata_reg;
reg          m0_axis_tlast_reg;
reg          m0_axis_tvalid_reg;
reg [63:0]   m0_axis_tkeep_reg;
reg [136:0]  m0_axis_tuser_reg;

rr inst(.clk(clk), .rst(rst), .req({s0_axis_tvalid, s1_axis_tvalid, s2_axis_tvalid, 'b0}), .grant(grant));

always @(posedge clk or negedge rst) begin
    if(!rst) begin
        m0_axis_tdata_reg  <= 'b0;
        m0_axis_tlast_reg  <= 'b0;
        m0_axis_tvalid_reg <= 'b0;
        m0_axis_tkeep_reg  <= 'b0;
        m0_axis_tuser_reg  <= 'b0;
    end
    else if(grant[0]) begin 
        m0_axis_tdata_reg  <= s0_axis_tdata;
        m0_axis_tlast_reg  <= s0_axis_tlast;
        m0_axis_tvalid_reg <= s0_axis_tvalid;
        m0_axis_tkeep_reg  <= s0_axis_tkeep;
        m0_axis_tuser_reg  <= s0_axis_tuser;
    end
    else if(grant[1]) begin 
        m0_axis_tdata_reg  <= s1_axis_tdata;
        m0_axis_tlast_reg  <= s1_axis_tlast;
        m0_axis_tvalid_reg <= s1_axis_tvalid;
        m0_axis_tkeep_reg  <= s1_axis_tkeep;
        m0_axis_tuser_reg  <= s1_axis_tuser;
    end
    else if(grant[2]) begin 
        m0_axis_tdata_reg  <= s2_axis_tdata;
        m0_axis_tlast_reg  <= s2_axis_tlast;
        m0_axis_tvalid_reg <= s2_axis_tvalid;
        m0_axis_tkeep_reg  <= s2_axis_tkeep;
        m0_axis_tuser_reg  <= s2_axis_tuser;
    end 
    else if(grant[3]) begin 
        m0_axis_tdata_reg  <= 'b0;
        m0_axis_tlast_reg  <= 'b0;
        m0_axis_tvalid_reg <= 'b0;
        m0_axis_tkeep_reg  <= 'b0;
        m0_axis_tuser_reg  <= 'b0;
    end
end

assign m0_axis_tdata    = m0_axis_tdata_reg;
assign m0_axis_tlast    = m0_axis_tlast_reg;
assign m0_axis_tvalid   = m0_axis_tvalid_reg;
assign m0_axis_tkeep    = m0_axis_tkeep_reg;
assign m0_axis_tuser    = m0_axis_tuser_reg;

assign s0_axis_tready = m0_axis_tready & grant[0];
assign s1_axis_tready = m0_axis_tready & grant[1];
assign s2_axis_tready = m0_axis_tready & grant[2];

endmodule
  