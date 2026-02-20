module primus_instruction_fetch(
  input           clk_i,
  input           rst_ni,              // Active low reset
  input  [31:0]   pc_i,                // Program counter

  // writer interface
  output logic [31:0]      ir_o,          // Instruction register
  output logic [31:0]      npc_o          // Next program counter

);

  logic pc_d, pc_q, ir_d, ir_q;

  // Instantiate module instruction memory
  instruction_memory a_inst_mem (
    .clk_i  (clk_i),
    .rst_i  (rst_ni),
    .addr_i (pc_q),
    .inst_o (ir_q)
  );

  // input assignments
  assign pc_d    = pc_i;

  // output assignments
  assign ir_o    = ir_d;
  assign npc_o   = npc_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q <= '0;
      ir_q <= '0;
    end else begin
      pc_q <= pc_d;
      ir_q <= ir_d;
    end
  end

  always_comb begin
    pc_q = pc_d + 4; // Progress to next PC
  end

endmodule 
