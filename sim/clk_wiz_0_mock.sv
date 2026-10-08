`timescale 1ns / 1ps

// =============================================================================
// Behavioral mock of Xilinx Clocking Wizard (clk_wiz_0)
// For functional simulation when Vivado IP output products are not pre-compiled.
// Generates:
//   clk_out1: 74.25 MHz (pixel clock for 720p@60Hz)
//   clk_out2: 371.25 MHz (5x serial DDR clock)
// =============================================================================

module clk_wiz_0 (
    input  logic clk_in1,
    output logic clk_out1,
    output logic clk_out2
);

    initial begin
        clk_out1 = 1'b0;
        clk_out2 = 1'b0;
    end

    // 74.25 MHz period ≈ 13.468013 ns (half-period ≈ 6.734007 ns)
    always #6.734ns clk_out1 = ~clk_out1;

    // 371.25 MHz period ≈ 2.693603 ns (half-period ≈ 1.346801 ns)
    always #1.3468ns clk_out2 = ~clk_out2;

endmodule
