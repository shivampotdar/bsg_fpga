/**
 *  bp_stream_mmio.v
 *
 */

`include "bp_common_defines.svh"
`include "bp_be_defines.svh"
`include "bp_me_defines.svh"


module bp_stream_mmio

  import bp_common_pkg::*;
  import bp_be_pkg::*;
  import bp_me_pkg::*;

 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
  `declare_bp_proc_params(bp_params_p)
  `declare_bp_bedrock_mem_if_widths(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p, cce)
  
  ,parameter stream_data_width_p = 32
  )

  (input  clk_i
  ,input  reset_i
  
  ,input  [cce_mem_msg_width_lp-1:0]        io_cmd_i
  ,input                                    io_cmd_v_i
  ,output                                   io_cmd_yumi_o
  
  ,output [cce_mem_msg_width_lp-1:0]        io_resp_o
  ,output                                   io_resp_v_o
  ,input                                    io_resp_ready_i
  
  ,input                                    stream_v_i
  ,input  [stream_data_width_p-1:0]         stream_data_i
  ,output                                   stream_ready_o
  
  ,output                                   stream_v_o
  ,output [stream_data_width_p-1:0]         stream_data_o
  ,input                                    stream_yumi_i
  );

  `declare_bp_bedrock_mem_if(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p, cce);
  
  // Temporarily support cce_data_size less than stream_data_width_p only
  // Temporarily support response of 64-bits data only
  bp_bedrock_cce_mem_msg_s io_cmd, io_resp;
  assign io_cmd = io_cmd_i;
  
  // streaming out fifo
  logic out_fifo_v_li, out_fifo_ready_lo;
  logic [stream_data_width_p-1:0] out_fifo_data_li;
  
  bsg_two_fifo
 #(.width_p(stream_data_width_p)
  ) out_fifo
  (.clk_i  (clk_i)
  ,.reset_i(reset_i)
  ,.data_i (out_fifo_data_li)
  ,.v_i    (out_fifo_v_li)
  ,.ready_o(out_fifo_ready_lo)
  ,.data_o (stream_data_o)
  ,.v_o    (stream_v_o)
  ,.yumi_i (stream_yumi_i)
  );
  
  // cmd_queue fifo
  logic queue_fifo_v_li, queue_fifo_ready_lo;
  logic queue_fifo_v_lo, queue_fifo_yumi_li;
  
  bsg_fifo_1r1w_small
 #(.width_p(cce_mem_msg_width_lp - cce_block_width_p)
  ,.els_p  (16)
  ) queue_fifo
  (.clk_i  (clk_i)
  ,.reset_i(reset_i)
  ,.data_i (io_cmd.header)
  ,.v_i    (queue_fifo_v_li)
  ,.ready_o(queue_fifo_ready_lo)
  ,.data_o (io_resp.header)
  ,.v_o    (queue_fifo_v_lo)
  ,.yumi_i (queue_fifo_yumi_li)
  );
  
  logic [1:0] state_r, state_n;
  
  always_ff @(posedge clk_i)
    if (reset_i)
      begin
        state_r <= '0;
      end
    else
      begin
        state_r <= state_n;
      end
  
  logic io_cmd_yumi_lo;
  assign io_cmd_yumi_o = io_cmd_yumi_lo;
  
  always_comb
  begin
    state_n = state_r;
    io_cmd_yumi_lo = 1'b0;
    queue_fifo_v_li = 1'b0;
    out_fifo_v_li = 1'b0;
    out_fifo_data_li = io_cmd.data;
    
    if (state_r == 0)
      begin
        if (io_cmd_v_i & out_fifo_ready_lo & queue_fifo_ready_lo)
          begin
            out_fifo_v_li = 1'b1;
            out_fifo_data_li = io_cmd.header.addr;
            state_n = 1;
          end
      end
    else if (state_r == 1)
      begin
        if (io_cmd_v_i & out_fifo_ready_lo & queue_fifo_ready_lo)
          begin
            out_fifo_v_li = 1'b1;
            io_cmd_yumi_lo = 1'b1;
            queue_fifo_v_li = 1'b1;
            state_n = 0;
          end
      end
  end
  
  // resp fifo
  logic io_resp_v_li, io_resp_ready_lo;

  bsg_two_fifo
 #(.width_p(cce_mem_msg_width_lp)
  ) resp_fifo
  (.clk_i  (clk_i)
  ,.reset_i(reset_i)
  ,.data_i (io_resp)
  ,.v_i    (io_resp_v_li)
  ,.ready_o(io_resp_ready_lo)
  ,.data_o (io_resp_o)
  ,.v_o    (io_resp_v_o)
  ,.yumi_i (io_resp_ready_i & io_resp_v_o)
  );
  
  logic sipo_v_lo, sipo_yumi_li;
  logic [dword_width_gp-1:0] sipo_data_lo;;
  
  bsg_serial_in_parallel_out_full
 #(.width_p(stream_data_width_p)
  ,.els_p  (dword_width_gp/stream_data_width_p)
  ) sipo
  (.clk_i  (clk_i)
  ,.reset_i(reset_i)
  ,.v_i    (stream_v_i)
  ,.ready_o(stream_ready_o)
  ,.data_i (stream_data_i)
  ,.data_o (sipo_data_lo)
  ,.v_o    (sipo_v_lo)
  ,.yumi_i (sipo_yumi_li)
  );
  
  always_comb
  begin
    io_resp_v_li = 1'b0;
    queue_fifo_yumi_li = 1'b0;
    sipo_yumi_li = 1'b0;
    io_resp.data = '0;
    if (queue_fifo_v_lo & io_resp_ready_lo)
      begin
        case (io_resp.header.msg_type)
          e_bedrock_mem_rd
          ,e_bedrock_mem_uc_rd:
          begin
            if (sipo_v_lo)
              begin
                io_resp.data = sipo_data_lo;
                io_resp_v_li = 1'b1;
                queue_fifo_yumi_li = 1'b1;
                sipo_yumi_li = 1'b1;
              end
          end
          e_bedrock_mem_uc_wr
          ,e_bedrock_mem_wr   :
          begin
            io_resp_v_li = 1'b1;
            queue_fifo_yumi_li = 1'b1;
          end
          default: begin
          end
        endcase
      end
  end

endmodule
