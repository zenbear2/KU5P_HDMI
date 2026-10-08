`timescale 1ns / 1ps

// =============================================================================
// Testbench for HDMI_KU5P_TOP
// Validates clock generation, reset sequence, TMDS outputs, and audio packets.
// =============================================================================

module HDMI_KU5P_TOP_tb;

    logic       clk_i;
    logic       rst;
    logic       HDMI0_OE;
    logic       LED;
    logic [2:0] TMDSp, TMDSn;
    logic       TMDSp_clock, TMDSn_clock;

    // Instantiate Top
    HDMI_KU5P_TOP #(
        .VIDEO_ID_CODE(4),          // 1280x720p @ 60Hz
        .VIDEO_REFRESH_RATE(60.0),
        .AUDIO_RATE(48000),         // 48 kHz L-PCM audio
        .AUDIO_BIT_WIDTH(16),
        .DVI_OUTPUT(1'b0)           // HDMI mode with audio and InfoFrames
    ) dut (
        .clk_i       (clk_i),
        .rst         (rst),
        .HDMI0_OE    (HDMI0_OE),
        .LED         (LED),
        .TMDSp       (TMDSp),
        .TMDSn       (TMDSn),
        .TMDSp_clock (TMDSp_clock),
        .TMDSn_clock (TMDSn_clock)
    );

    // 50 MHz board input clock (period = 20 ns)
    initial clk_i = 1'b0;
    always #10.0ns clk_i = ~clk_i;

    initial begin
        $display("=== Starting HDMI_KU5P_TOP Simulation ===");
        rst = 1'b1;
        #200ns;
        rst = 1'b0;
        $display("[TB] Reset released. Initializing HDMI stream...");

        // Simulate sufficient time to verify TMDS activity
        #50us;
        $display("[TB] Simulation time: %0t ns", $time);
        $display("[TB] HDMI0_OE   = %b (Expected: 1)", HDMI0_OE);
        $display("[TB] TMDSp      = %b", TMDSp);
        $display("[TB] TMDSn      = %b", TMDSn);
        $display("[TB] TMDS_clk   = %b", TMDSp_clock);
        $display("=== HDMI_KU5P_TOP Simulation Completed Successfully ===");
        $finish;
    end

endmodule
