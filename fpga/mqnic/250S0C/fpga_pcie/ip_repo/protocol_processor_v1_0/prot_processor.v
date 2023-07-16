`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/26/2021 12:24:33 PM
// Design Name: 
// Module Name: prot_processor
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


module prot_processor #
(
parameter res = 3'b000,
parameter seek = 3'b001,
parameter spin = 3'b010,
parameter idle = 3'b011,
parameter recv = 3'b100,
parameter send_remote = 3'b101,
parameter send_origin = 3'b110,
parameter forward_packet = 3'b111,

parameter np = 8,
parameter send_np = 2,
parameter mode_ind = 6,
parameter page_ind = 4,

parameter rpr_mode = 'h0ADDBEEF,
parameter inval_mode = 'hDEADBEEF,
parameter prot_proc_request = 'h0ADDBEEFDEADBEEF,
parameter filler_packet = 'hABCDEF,
parameter INVALIDATED = 'hFFFF,
parameter MODIFIED = 'hAAAA,
parameter SHARED = 'hBBBB,
parameter un_nid = 'hF,
parameter grant_nid = 'hA,

parameter FAULT_FLAG_WRITE = 1 << 0
)
(
    input 	  CLK,
    input 	  RST,    
    
    //Required Page Info
    input [31:0]   nid,
    input [63:0]  dma_addr,
    input [63:0]  virt_addr,
    input [63:0] fault_flags,
    input [63:0] p_key,
    input [31:0] vm_result,
    input [63:0] instr_addr, 
    input [31:0] ws_id,
    input [31:0] remote_pid,
    input [31:0] origin_pid,
    input [31:0] my_nid,
    input [31:0] resp_type,
    output reg [63:0] result,
    output reg [31:0] own_res,
    output reg [31:0] dec_res,
    
    //Reg File to store the Page Info 
    output reg [63:0]  page_key,
    output reg [31:0]   onid,
    output reg [63:0]  daddr,
    output reg [63:0]  vaddr,
    output reg [63:0] fflags,
    output reg [63:0] iaddr, 
    output reg [31:0] wid,
    output reg[31:0] rpid,
    output reg [31:0] opid,
    output reg [31:0] page_mode,
    output reg [31:0] vm_res,
    output reg [31:0] out,
    
    //Input Signals
    input proc_start,
    input send_resp,
    input tsk_remote,
    input proc_reset,
    input fault_mask,
    input rpr_mask,
    input in_mask,
        
    //AXIS Input Ports 
    input wire [511:0]  s_axis_tdata,
    input wire s_axis_tlast,
    input wire s_axis_tvalid,
    input wire [63:0] s_axis_tkeep,
    input wire s_axis_tuser,
    output wire s_axis_tready, 
    
    //AXIS Output Ports 
    output wire [511:0] m00_axis_tdata,
    output wire	  m00_axis_tlast,
    output wire	  m00_axis_tvalid,
    output wire [63:0] m00_axis_tkeep,
    output wire m00_axis_tuser,
    input m00_axis_tready,
    
    output wire [511:0] m_axis_tdata,
    output wire	  m_axis_tlast,
    output wire	  m_axis_tvalid,
    output wire [63:0] m_axis_tkeep,
    output wire m_axis_tuser,
    input m_axis_tready,
    
    // Output interrupts ,
    output reg fault_intr
    
    );
    
//Misc. regs

reg [2:0] state;
integer pause = 4;
integer cnt = 0;

reg [3:0] packet_cnt;
reg [3:0] wr_ptr = 0;
reg [3:0] forward_ptr = 0;
reg [511:0] m_axis_tdata_pipe [0:1];
reg [511:0] m00_axis_tdata_pipe [0:7];
reg [511:0] s_axis_tdata_pipe [0:7];
reg [63:0] s_axis_tkeep_reg;
reg s_axis_tready_reg;
reg [63:0] test_fflags;

reg [511:0] m_axis_tdata_reg;
reg	  m_axis_tlast_reg;
reg	  m_axis_tvalid_reg;
reg [63:0] m_axis_tkeep_reg;
reg m_axis_tuser_reg;

reg [511:0] m00_axis_tdata_reg;
reg	  m00_axis_tlast_reg;
reg	  m00_axis_tvalid_reg;
reg [63:0] m00_axis_tkeep_reg;
reg m00_axis_tuser_reg;
    
/* Data Array Access Functions */

/*
--- Code for Invalidation - 0xDEADBEEF
--- Code for Remote Page Request - 0x0ADDBEEF
--- Code for Modified Page - 0x0000AAAA
--- Code for Invalidated Page - 0x0000FFFF
--- Code for Shared Page - 0x0000BBBB
--- Code for Origin Node - 0x0000DADA
--- Code for Remote Node - 0x0000CADA
 */
 
 /* Fault Flags Check */
 
 function fault_for_write(input [63:0] flags);
    begin
        fault_for_write = (flags & FAULT_FLAG_WRITE);
        out = (flags & FAULT_FLAG_WRITE);
    end
endfunction //fault_for_write
 
/* Function only called in origin node */

function [31:0] decode_pkey(input [63:0] page_key);
    begin
        if((page_key[19:4] == MODIFIED) && (page_key[3:0] == grant_nid)) begin
            //The remote node owns the page - Claim the remote page
            decode_pkey = 0;
        end
        else if((page_key[19:4] == SHARED) && (page_key[3:0] == grant_nid)) begin
            //I own the page - Claim the local page
            decode_pkey = 1;
        end
    end
endfunction //decode_pkey

/* Handle Remotefault at origin/Handle Remotefault at remote */

function [3:0] recv_dec(input [63:0] page_key);
    begin
        /* Invalidate the page in the receiving node/ Wr Fault*/
        if((page_key[19:4] == MODIFIED) && (page_key[3:0] == un_nid)) begin
            recv_dec = 'hC;
        end
        /* Protect it from writing the receiving node/ Rd Fault */
        else if((page_key[19:4] == SHARED) && (page_key[3:0] == un_nid)) begin
            recv_dec = 'hB;
        end
        /* If the sending node already has the up-to date copy */
        else if((page_key[19:4] == SHARED) && (page_key[3:0] == grant_nid)) begin
            recv_dec = 'hA;
        end
        /* Origin is claiming back the page with wr_fault*/
        else if((page_key[19:4] == MODIFIED) && (page_key[3:0] != grant_nid) && (page_key[3:0] != my_nid)) begin
            recv_dec = 'hD;
        end
        /* Origin is claiming back the page with rd_fault*/
        else if((page_key[19:4] == SHARED) && (page_key[3:0] != grant_nid) && (page_key[3:0] != my_nid)) begin
            recv_dec = 'hE;
        end        
        /* Remote is asking the page again */
        else if((page_key[3:0] == my_nid)) begin
            recv_dec = 'hF;
        end
        /* Page Key is invalid */
        else begin
            recv_dec = 0;
        end
    end
endfunction //decode_pkey

/* PKEY Format - Total 64 bits -
[63:48] - VADDR 
[47:32] - IADDR
[31:26] - RPID
[25:20] - OPID
[19:4] - STATUS
[3:0] - NID
*/
function [63:0] encode_pkey(input [31:0] pmode, input [63:0] pvaddr, input [31:0] pnid, input [31:0] prpid, input [31:0] popid, input [63:0] piaddr, input [63:0] pfflags, input [31:0] pmy_nid, input recv);
    begin
        if(recv) begin
            if(pmode == rpr_mode) begin                       
                if(fault_for_write(pfflags)) begin
                    encode_pkey = {pvaddr[15:0], piaddr[15:0], prpid[5:0], popid[5:0], INVALIDATED[15:0], un_nid[3:0]};
                end
                else begin
                    encode_pkey = {pvaddr[15:0], piaddr[15:0], prpid[5:0], popid[5:0], SHARED[15:0], pmy_nid[3:0]};
                end
            end
            else begin
                encode_pkey = {pvaddr[15:0], piaddr[15:0], prpid[5:0], popid[5:0], INVALIDATED[15:0], un_nid[3:0]};
            end
        end
        else begin            
            if(pmode == rpr_mode) begin                       
                if(fault_for_write(pfflags)) begin
                    encode_pkey = {pvaddr[15:0], piaddr[15:0], prpid[5:0], popid[5:0], MODIFIED[15:0], un_nid[3:0]};
                end
                else begin
                    encode_pkey = {pvaddr[15:0], piaddr[15:0], prpid[5:0], popid[5:0], SHARED[15:0], un_nid[3:0]};
                end
            end
            else begin
                //Claiming back the remote page and owning it with a wr_fault
                if(fault_for_write(pfflags)) begin
                    encode_pkey = {pvaddr[15:0], piaddr[15:0], prpid[5:0], popid[5:0], MODIFIED[15:0], pmy_nid[3:0]};
                end
                //Claiming it back but with a rd_fault/ Remote node still owns the page
                else begin
                    encode_pkey = {pvaddr[15:0], piaddr[15:0], prpid[5:0], popid[5:0], SHARED[15:0], pmy_nid[3:0]};
                end
            end  
        end
    end
endfunction //encode_pkey

assign m_axis_tdata = m_axis_tdata_reg;
assign m_axis_tuser = m_axis_tuser_reg;
assign m_axis_tlast = m_axis_tlast_reg;
assign m_axis_tkeep = m_axis_tkeep_reg;
assign m_axis_tvalid = m_axis_tvalid_reg;

assign m00_axis_tdata = m00_axis_tdata_reg;
assign m00_axis_tuser = m00_axis_tuser_reg;
assign m00_axis_tlast = m00_axis_tlast_reg;
assign m00_axis_tkeep = m00_axis_tkeep_reg;
assign m00_axis_tvalid = m00_axis_tvalid_reg;

assign s_axis_tready = s_axis_tready_reg;

always @(posedge CLK) begin 

    m00_axis_tdata_pipe[1] = prot_proc_request;
    m00_axis_tdata_pipe[2] = prot_proc_request;
    m00_axis_tdata_pipe[3] = prot_proc_request;
    m00_axis_tdata_pipe[4] = prot_proc_request;
    m00_axis_tdata_pipe[5] = prot_proc_request;
    m00_axis_tdata_pipe[6] = prot_proc_request;
    m00_axis_tdata_pipe[7] = prot_proc_request;
    
    m_axis_tdata_pipe[1] = prot_proc_request;
       
end

/* FSM Core */

always @(posedge CLK) begin
    if(RST == 0) begin
            state = res;
    end
    else begin 
        case(state)
        
        /* Reset */
        res: begin
            if(pause == 0) begin
                pause = 4;
                state <= seek;
            end
            else begin
                pause = pause - 1;
            end 
        end
        
        /* Packet processing and data forwarding state */        
        recv: begin
            s_axis_tdata_pipe[wr_ptr] <= s_axis_tdata;
            s_axis_tkeep_reg <= s_axis_tkeep;
            wr_ptr <= wr_ptr + 1; 
            page_key = s_axis_tdata_pipe[0][191:128];
            iaddr <= s_axis_tdata_pipe[0][255:192];
            vaddr <= s_axis_tdata_pipe[0][383:320];
            fflags <= s_axis_tdata_pipe[0][479:416];
            wid <= s_axis_tdata_pipe[0][127:96];
            onid <= s_axis_tdata_pipe[0][95:64];
            
            rpid <= s_axis_tdata_pipe[0][319:288];
            opid <= s_axis_tdata_pipe[0][287:256];
            
            if(s_axis_tdata_pipe[0][415:384] == inval_mode) begin
                page_mode = 'hFFFF;
            end
            else if(s_axis_tdata_pipe[0][415:384] == rpr_mode) begin
                dec_res = recv_dec(s_axis_tdata_pipe[0][191:128]);
                if(dec_res) begin
                /* Remote Fault Handlers at Origin */
                    if(dec_res == 'hA) begin
                        page_mode = 'hAAAA;
                        page_key[19:4] = MODIFIED;
                    end
                    else if(dec_res == 'hB) begin
                        page_mode = 'hBBBB;
                        page_key[3:0] = grant_nid;
                    end
                    else if(dec_res == 'hC) begin
                        page_mode = 'hCCCC;
                        page_key[3:0] = grant_nid;
                    end
                    /* Remote Fault Handlers at Remote */
                    else if(dec_res == 'hD) begin
                        page_mode = 'hCCCC;
                        //page_key[3:0] = grant_nid;
                    end
                    else if(dec_res == 'hE) begin
                        page_mode = 'hBBBB;
                        page_key[3:0] = grant_nid;
                    end
                    /* Remote requesting the page again*/
                    else begin
                        if(fault_for_write(s_axis_tdata_pipe[0][479:416])) begin
                            page_mode = 'hCCCC;
                            page_key[3:0] = grant_nid;   
                            page_key[19:4] = MODIFIED;                                 
                        end
                        else begin
                            page_mode = 'hBBBB;
                            page_key[3:0] = grant_nid;
                            page_key[19:4] = SHARED;
                        end
                    end
                end
                else begin
                    fault_intr <= 1;
                end
            end
            
            /* Packet Forwarding Logic */
            if(m00_axis_tready) begin
                m00_axis_tdata_pipe[0] = {s_axis_tdata_pipe[0][255:192], s_axis_tdata_pipe[0][383:320], s_axis_tdata_pipe[0][479:416], page_mode[31:0], s_axis_tdata_pipe[0][127:96], s_axis_tdata_pipe[0][95:64], 
                                          s_axis_tdata_pipe[0][319:288], s_axis_tdata_pipe[0][287:256], page_key[63:0]};
                m00_axis_tdata_reg <= m00_axis_tdata_pipe[packet_cnt];
                m00_axis_tvalid_reg <= 1;
                m00_axis_tuser_reg <= 0;
                m00_axis_tkeep_reg <= 'hFFFFFFFFFFFFFFFF;
                packet_cnt <= packet_cnt + 1;
                
                if(packet_cnt == np) begin
                    m00_axis_tdata_reg <= {prot_proc_request[63:0]};
                    m00_axis_tlast_reg <= 1;
                    s_axis_tready_reg <= 0;
                    m00_axis_tkeep_reg <= 'hFFFFFFFFFFFFFFFF;
                    state <= seek;                    
                    packet_cnt <= 0;
                    wr_ptr <= 0;
                 end      
            end
            else begin
                m00_axis_tdata_reg <= 0;
                m00_axis_tvalid_reg <= 0;
                m00_axis_tuser_reg <= 0;
                m00_axis_tkeep_reg <= 0;
                m00_axis_tlast_reg <= 0;
            end   
        end
        
        idle: begin
            m_axis_tlast_reg <= 0;
            m_axis_tdata_reg <= 0;
            m_axis_tvalid_reg <= 0;
            if(proc_start) begin
                cnt = cnt + 1;    
            end
            else begin
                state <= seek;
                cnt = 0;
            end
        end
        
        /* Handle Localfault at Remote Function */  
        send_remote: begin                     
            /* Remote Page request function - Fetch_Page_from_Origin */            
            if(p_key != 'h0) begin
                if(!(fault_for_write(fault_flags)) && (p_key[3:0] == grant_nid)) begin
                    // Read Fault from the owner ?? 
                    fault_intr <= 1;
                    state <= idle;
                end
                else begin
                    m_axis_tdata_pipe[0] = {fault_flags[63:0], rpr_mode[31:0], virt_addr[63:0], remote_pid[31:0], origin_pid[31:0], 
                    instr_addr[63:0], p_key[63:0], ws_id[31:0], nid[31:0], prot_proc_request[63:0]}; 
                end  
            end
            else begin
                result = encode_pkey(rpr_mode, virt_addr, nid, remote_pid, origin_pid, instr_addr, fault_flags, my_nid, 1'b0);
                m_axis_tdata_pipe[0] = {fault_flags[63:0], rpr_mode[31:0], virt_addr[63:0], remote_pid[31:0], origin_pid[31:0], 
                instr_addr[63:0], result[63:0], ws_id[31:0], nid[31:0], prot_proc_request[63:0]};  
            end
            m_axis_tdata_reg <= m_axis_tdata_pipe[packet_cnt];
            m_axis_tvalid_reg <= 1;
            m_axis_tuser_reg <= 0;
            m_axis_tkeep_reg <= 'hFFFFFFFFFFFFFFFF;
            packet_cnt <= packet_cnt + 1;
            
            if(packet_cnt == send_np) begin
                m_axis_tdata_reg <= {prot_proc_request[63:0]};
                m_axis_tlast_reg <= 1;
                m_axis_tkeep_reg <= 'hFFFFFFFFFFFFFFFF;
                packet_cnt <= 0;
                state <= idle;                        
             end                                                    
        end
        
        /* Handle Localfault at Origin Function */
        send_origin: begin
        
            page_key = encode_pkey(inval_mode, virt_addr, nid, remote_pid, origin_pid, instr_addr, fault_flags, my_nid, 1'b0);           
            own_res = decode_pkey(p_key);
            if(own_res) begin
                /* Claim Local Page - Invalidate/Revoke Page Ownership */ 
                m_axis_tdata_pipe[0] = {fault_flags[63:0], inval_mode[31:0], virt_addr[63:0], remote_pid[31:0], origin_pid[31:0], 
                instr_addr[63:0], page_key[63:0], ws_id[31:0], nid[31:0], prot_proc_request[63:0]};
                m_axis_tdata_reg <= m_axis_tdata_pipe[packet_cnt];
                m_axis_tvalid_reg <= 1;
                m_axis_tuser_reg <= 0;
                m_axis_tkeep_reg <= 'hFFFFFFFFFFFFFFFF;                        
                packet_cnt <= packet_cnt + 1;
                if(packet_cnt == send_np) begin
                    m_axis_tdata_reg <= {prot_proc_request[63:0]};  
                    m_axis_tlast_reg <= 1;
                    m_axis_tkeep_reg <= 'hFFFFFFFFFFFFFFFF;
                    packet_cnt <= 0;
                    state <= idle;
                end                                            
            end
            else begin
                /* Claim Remote Page - Request remote page */ 
                m_axis_tdata_pipe[0] = {fault_flags[63:0], rpr_mode[31:0], virt_addr[63:0], remote_pid[31:0], origin_pid[31:0], 
                instr_addr[63:0], page_key[63:0], ws_id[31:0], nid[31:0], prot_proc_request[63:0]};
                m_axis_tdata_reg <= m_axis_tdata_pipe[packet_cnt];
                m_axis_tvalid_reg <= 1;
                m_axis_tuser_reg <= 0;
                m_axis_tkeep_reg <= 'hFFFFFFFFFFFFFFFF;                   
                packet_cnt <= packet_cnt + 1;
                if(packet_cnt == send_np) begin
                    m_axis_tdata_reg <= {prot_proc_request[63:0]};   
                    m_axis_tlast_reg <= 1;
                    m_axis_tkeep_reg <= 'hFFFFFFFFFFFFFFFF;
                    packet_cnt <= 0;
                    state <= idle;
                end
            end
        end
        
        seek: begin
            s_axis_tready_reg <= 1;
            m00_axis_tdata_reg <= 0;
            m00_axis_tlast_reg <= 0;
            m00_axis_tkeep_reg <= 0;
            m00_axis_tvalid_reg <= 0;
            result = 0;
            
            /* Masking Interrupts */ 
            if(fault_mask) begin
                fault_intr <= 0;
            end 
        
            /* Frame Reception logic */
            else if(s_axis_tvalid) begin
                state <= recv;
                s_axis_tdata_pipe[wr_ptr] <= s_axis_tdata;
                s_axis_tkeep_reg <= s_axis_tkeep;
                wr_ptr <= wr_ptr + 1;                     
            end
            
            else if(proc_start && tsk_remote) begin
                state <= send_remote;
            end
            else if(proc_start) begin
                state <= send_origin;
            end
            else begin 
                state <= seek;
            end        
        end
    
        default: begin
            state <= seek;
            packet_cnt <= 0;
        end   
        endcase       
    end
    
end //always block for FSM_Core
    
endmodule //prot_processor
