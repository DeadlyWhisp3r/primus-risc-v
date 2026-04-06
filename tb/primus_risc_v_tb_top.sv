`timescale 1ns / 1ps

module primus_risc_v_tb();

  logic clk_i = 0;
  logic rst_ni;

  // Clock generation
  always #5 clk_i = ~clk_i;

  // Instantiate Top Level
  primus_risc_v_top uut (
    .clk_i  (clk_i),
    .rst_ni (rst_ni)
  );

  initial begin
    rst_ni = 0;
    repeat (10) @(posedge clk_i);
    rst_ni = 1;
    $display("--- CPU Reset Released ---");

    // Wait for program to complete — 200 cycles is enough for 10 Fibonacci iterations
    repeat (200) @(posedge clk_i);

    // --- Register file dump ---
    $display("--- Register File State ---");
    $display("x1  = %0d", uut.a_id_stage.a_id_regfile.x_reg_q[1]);
    $display("x2  = %0d", uut.a_id_stage.a_id_regfile.x_reg_q[2]);
    $display("x3  = %0d", uut.a_id_stage.a_id_regfile.x_reg_q[3]);
    $display("x5  = %0d", uut.a_id_stage.a_id_regfile.x_reg_q[5]);
    $display("x10 = %0d", uut.a_id_stage.a_id_regfile.x_reg_q[10]);

    // --- Register file assertions ---
    // Expected state after 10 Fibonacci iterations:
    //   x1=55, x2=89, x3=89, x5=40, x10=0
    assert (uut.a_id_stage.a_id_regfile.x_reg_q[1]  == 32'd55)
      else $error("FAIL x1:  expected 55,  got %0d", uut.a_id_stage.a_id_regfile.x_reg_q[1]);
    assert (uut.a_id_stage.a_id_regfile.x_reg_q[2]  == 32'd89)
      else $error("FAIL x2:  expected 89,  got %0d", uut.a_id_stage.a_id_regfile.x_reg_q[2]);
    assert (uut.a_id_stage.a_id_regfile.x_reg_q[3]  == 32'd89)
      else $error("FAIL x3:  expected 89,  got %0d", uut.a_id_stage.a_id_regfile.x_reg_q[3]);
    assert (uut.a_id_stage.a_id_regfile.x_reg_q[5]  == 32'd40)
      else $error("FAIL x5:  expected 40,  got %0d", uut.a_id_stage.a_id_regfile.x_reg_q[5]);
    assert (uut.a_id_stage.a_id_regfile.x_reg_q[10] == 32'd0)
      else $error("FAIL x10: expected 0,   got %0d", uut.a_id_stage.a_id_regfile.x_reg_q[10]);

    $display("--- All assertions passed ---");
    $display("--- Simulation End ---");
    $finish;
  end

endmodule
