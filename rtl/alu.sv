module primus_alu (
  input        clk_i,
  input        rst_ni,              // Active low reset

  // Operands for arithemtic operation
  input [15:0] rs1_data_q_i,
  input        b_i,
  output       ready_o,

  // bi-directional bus
  inout [7:0]  driver_io,         // Bi directional signal

  // Differential pair output
  output       lvds_po,           // Positive part of the differential signal
  output       lvds_no            // Negative part of the differential signal
);

  logic valid_d, valid_q, valid_q2, valid_q3;
  assign valid_d = valid_i; // next state assignment

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q  <= '0;
      valid_q2 <= '0;
      valid_q3 <= '0;
    end else begin
      valid_q  <= valid_d;
      valid_q2 <= valid_q;
      valid_q3 <= valid_q2;
    end
  end

  assign ready_o = valid_q3; // three clock cycles delay

endmodule // simple
