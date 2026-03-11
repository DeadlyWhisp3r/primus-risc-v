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

  // Monitor for Pipeline Progress
  initial begin
    $display("Time\tPC\t\tInstr\t\tResult\tRD\tWE");
    $display("------------------------------------------------------------");
    forever begin
      @(posedge clk_i);
      #1; // Wait for signals to settle after clock edge
      if (uut.wb_id_we && uut.wb_rd_addr != 0) begin
        $display("%0t\t%h\t%h\t%h\tx%0d\t%b", 
                 $time, uut.pc, uut.if_ir, uut.wb_data, uut.wb_rd_addr, uut.wb_id_we);
      end
    end
  end

  initial begin
    rst_ni = 0;
    repeat (10) @(posedge clk_i);
    rst_ni = 1;
    $display("--- CPU Reset Released ---");

    // Run long enough to see the instructions execute
    #1000;
    
    $display("--- Simulation End ---");
    $finish;
  end

endmodule
