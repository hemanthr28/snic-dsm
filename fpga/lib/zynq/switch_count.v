module switch_count(
    input wire clk, 
    input wire rst, 
    
    input wire [511:0] s0_axis_tdata,
    input wire s0_axis_tvalid,
    input wire [63:0] s0_axis_tkeep,
    output wire s0_axis_tready,
    input wire [136:0] s0_axis_tuser,
    input wire s0_axis_tlast,
    
    input wire [511:0] s1_axis_tdata,
    input wire s1_axis_tvalid,
    input wire [63:0] s1_axis_tkeep,
    output wire s1_axis_tready,
    input wire [80:0] s1_axis_tuser,
    input wire s1_axis_tlast,
    
    output wire [511:0] m0_axis_tdata,
    output wire m0_axis_tvalid,
    input wire m0_axis_tready,
    output wire [63:0] m0_axis_tkeep,
    output wire[136:0] m0_axis_tuser,
    output wire m0_axis_tlast,
    
    output wire [511:0] m1_axis_tdata,
    output wire m1_axis_tvalid,
    input wire m1_axis_tready,
    output wire [63:0] m1_axis_tkeep,
    output wire[80:0] m1_axis_tuser,
    output wire m1_axis_tlast,
    
    output wire [31:0] switch_cnt_rq,
    output wire [31:0] switch_cnt_cc
);
    reg [31:0] switch_cnt_reg_rq;
    reg [31:0] switch_cnt_reg_cc;
    
    always @(posedge clk) begin 
        if(!rst) begin
            switch_cnt_reg_rq = 'b0;
            switch_cnt_reg_cc = 'b0;
        end
        else begin 
            if(s0_axis_tvalid && m0_axis_tready) begin
                switch_cnt_reg_rq = switch_cnt_reg_rq+1;
            end
            if(s1_axis_tvalid && m1_axis_tready) begin
                switch_cnt_reg_cc = switch_cnt_reg_cc+1;                
            end
        end
    end
    
    assign switch_cnt_rq = switch_cnt_reg_rq/1024;
    assign switch_cnt_cc = switch_cnt_reg_cc/1024;
    
    assign m0_axis_tdata = s0_axis_tdata;
    assign m0_axis_tvalid = s0_axis_tvalid;
    assign s0_axis_tready = m0_axis_tready;
    assign m0_axis_tkeep = s0_axis_tkeep;
    assign m0_axis_tuser = s0_axis_tuser;
    assign m0_axis_tlast = s0_axis_tlast;
    
    assign m1_axis_tdata = s1_axis_tdata;
    assign m1_axis_tvalid = s1_axis_tvalid;
    assign s1_axis_tready = m1_axis_tready;
    assign m1_axis_tkeep = s1_axis_tkeep;
    assign m1_axis_tuser = s1_axis_tuser;
    assign m1_axis_tlast = s1_axis_tlast;
    
endmodule