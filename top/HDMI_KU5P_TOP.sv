`timescale 1ns / 1ps

// =============================================================================
// Top-Level Module for AMD / Xilinx Kintex UltraScale+ (KU5P) HDMI Output
// Target Board: KU5P FPGA board with HDMI Type-A connector
// Constraint file: pin.xdc
// Test Pattern: Dynamic Flowing Light (流光溢彩) with 400 Hz Low-Frequency Beep Tone
// =============================================================================

module HDMI_KU5P_TOP #(
    // Video mode: 4 = 1280x720p @ 60Hz, 1 = 640x480p @ 60Hz, 16 = 1920x1080p @ 60Hz
    parameter int  VIDEO_ID_CODE      = 4,
    parameter real VIDEO_REFRESH_RATE = 60.0,
    parameter int  AUDIO_RATE         = 48000,
    parameter int  AUDIO_BIT_WIDTH    = 16,
    parameter bit  DVI_OUTPUT         = 1'b0     // 1'b0: True HDMI (audio+packets), 1'b1: DVI mode
) (
    input  logic       clk_i,        // Pin E18: 50 MHz board reference clock
    input  logic       rst,          // Pin R20: Active-High reset pushbutton
    output logic       HDMI0_OE,     // Pin Y16: HDMI level shifter / buffer enable (active-high)
    output logic       LED,          // Pin D18: Heartbeat diagnostic LED
    output logic [2:0] TMDSp,        // Pin N24, V24, V23: TMDS differential positive data lines
    output logic [2:0] TMDSn,        // Paired differential negative data lines
    output logic       TMDSp_clock,  // Pin T25: TMDS differential positive clock line
    output logic       TMDSn_clock   // Paired differential negative clock line
);

    // 1. Enable board HDMI output level shifter
    assign HDMI0_OE = 1'b1;

    // 2. Clock generation via Xilinx Clocking Wizard (clk_wiz_0)
    //    Input: 50 MHz (clk_i)
    //    Output 1: clk_pixel    (74.25 MHz for 720p)
    //    Output 2: clk_pixel_x5 (371.25 MHz for 5x DDR serialization)
    logic clk_pixel;
    logic clk_pixel_x5;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk_i),
        .clk_out1 (clk_pixel),
        .clk_out2 (clk_pixel_x5)
    );

    // Active-high synchronous reset derived from pushbutton
    logic reset;
    assign reset = rst;

    // 3. Heartbeat LED blinker (driven by pixel clock)
    logic [25:0] led_cnt = 26'd0;
    always_ff @(posedge clk_pixel)
    begin
        led_cnt <= led_cnt + 1'b1;
    end
    assign LED = led_cnt[24];

    // 4. Audio clock & test tone generator (48 kHz)
    //    Divider calculation: 74.25 MHz / 1548 ≈ 47.965 kHz ≈ 48 kHz
    logic clk_audio = 1'b0;
    logic [10:0] audio_div = 11'd0;
    always_ff @(posedge clk_pixel)
    begin
        if (reset)
        begin
            audio_div <= 11'd0;
            clk_audio <= 1'b0;
        end
        else if (audio_div >= 11'd773)
        begin
            audio_div <= 11'd0;
            clk_audio <= ~clk_audio;
        end
        else
        begin
            audio_div <= audio_div + 1'b1;
        end
    end

    // 400 Hz Low-Frequency Tone Generator (48 kHz / 120 = 400 Hz tone)
    // Half-period = 60 samples (1.25 ms)
    logic [6:0] tone_cnt = 7'd0;
    logic       tone_low = 1'b0;
    always_ff @(posedge clk_audio)
    begin
        if (reset)
        begin
            tone_cnt <= 7'd0;
            tone_low <= 1'b0;
        end
        else if (tone_cnt >= 7'd59)
        begin
            tone_cnt <= 7'd0;
            tone_low <= ~tone_low;
        end
        else
        begin
            tone_cnt <= tone_cnt + 1'b1;
        end
    end

    // Beep cadence generator (1.0s cycle = 48,000 samples @ 48 kHz)
    // Rhythmic double-beep pattern ("嘟 嘟" 低音節奏):
    // 0.0s ~ 0.2s: "嘟" (Beep 1, 200ms)
    // 0.2s ~ 0.4s: 停頓 (Gap, 200ms)
    // 0.4s ~ 0.6s: "嘟" (Beep 2, 200ms)
    // 0.6s ~ 1.0s: 靜音 (Pause, 400ms)
    logic [15:0] cadence_cnt = 16'd0;
    logic        beep_enable = 1'b0;
    always_ff @(posedge clk_audio)
    begin
        if (reset)
        begin
            cadence_cnt <= 16'd0;
            beep_enable <= 1'b0;
        end
        else
        begin
            if (cadence_cnt >= 16'd47999)
                cadence_cnt <= 16'd0;
            else
                cadence_cnt <= cadence_cnt + 1'b1;

            beep_enable <= (cadence_cnt < 16'd9600) ||
                           (cadence_cnt >= 16'd19200 && cadence_cnt < 16'd28800);
        end
    end

    // Stereo 16-bit audio sample generation
    localparam signed [AUDIO_BIT_WIDTH-1:0] AUDIO_AMP = 16'sh2000; // ~ -12 dBFS comfortable volume
    logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0] = '{default: '0};

    always_ff @(posedge clk_audio)
    begin
        if (reset || !beep_enable)
        begin
            audio_sample_word[0] <= '0;
            audio_sample_word[1] <= '0;
        end
        else
        begin
            audio_sample_word[0] <= tone_low ? AUDIO_AMP : -AUDIO_AMP;
            audio_sample_word[1] <= tone_low ? AUDIO_AMP : -AUDIO_AMP;
        end
    end

    // 5. Video coordinate ports from HDMI core
    localparam int BIT_WIDTH  = VIDEO_ID_CODE < 4 ? 10 : VIDEO_ID_CODE == 4 ? 11 : 12;
    localparam int BIT_HEIGHT = VIDEO_ID_CODE == 16 ? 11 : 10;

    logic [BIT_WIDTH-1:0]  cx;
    logic [BIT_HEIGHT-1:0] cy;
    logic [BIT_WIDTH-1:0]  screen_width, frame_width;
    logic [BIT_HEIGHT-1:0] screen_height, frame_height;
    logic [23:0]           rgb;

    // =========================================================================
    // Dynamic Flowing Light (流光溢彩) Pattern with Luminous Shimmer
    // =========================================================================
    // Animation frame tick: advances 3 pixels each frame (60 Hz) for smooth movement
    logic [11:0] anim_offset = 12'd0;
    always_ff @(posedge clk_pixel)
    begin
        if (reset)
            anim_offset <= 12'd0;
        else if (cx == 0 && cy == 0)
            anim_offset <= anim_offset + 12'd3;
    end

    // Diagonal coordinate calculation (cx + cy/2) gives a sleek diagonal streaming angle
    logic [12:0] flow_pos;
    assign flow_pos = {1'b0, cx} + {2'b00, cy[BIT_HEIGHT-1:1]} + {1'b0, anim_offset};

    // Color wave transformation: convert 8-bit phase to vibrant saturated rainbow wave
    function automatic [7:0] wave_to_color(input [7:0] p);
        logic [7:0] tri_w;
        tri_w = p[7] ? ~{p[6:0], 1'b0} : {p[6:0], 1'b0}; // Triangle wave 0..255
        if (tri_w <= 8'd64)
            return 8'd0;
        else if (tri_w >= 8'd192)
            return 8'd255;
        else
            return {tri_w - 8'd64, 1'b0}; // Linear transition 0..254
    endfunction

    // 3-phase RGB color streamer (120-degree phase shift = 85 steps)
    logic [7:0] raw_r, raw_g, raw_b;
    assign raw_r = wave_to_color(flow_pos[9:2]);
    assign raw_g = wave_to_color(flow_pos[9:2] + 8'd85);
    assign raw_b = wave_to_color(flow_pos[9:2] + 8'd170);

    // Traveling luminous highlight beam (高光流光束, periodic glistening crest)
    logic [7:0] shimmer;
    always_comb
    begin
        if (flow_pos[8:5] == 4'h0) // 32 pixels wide beam
            shimmer = (flow_pos[4] ? ~flow_pos[3:0] : flow_pos[3:0]) << 4;
        else
            shimmer = 8'd0;
    end

    // 9-bit saturation add to prevent overflow
    logic [8:0] sum_r, sum_g, sum_b;
    always_comb
    begin
        sum_r = {1'b0, raw_r} + {2'b00, shimmer[7:1]};
        sum_g = {1'b0, raw_g} + {2'b00, shimmer[7:1]};
        sum_b = {1'b0, raw_b} + {2'b00, shimmer[7:1]};
    end

    // 24-bit RGB pixel color output (registered for 1-cycle pipeline matching cx)
    always_ff @(posedge clk_pixel)
    begin
        if (reset)
        begin
            rgb <= 24'h00_00_00;
        end
        else
        begin
            rgb[23:16] <= sum_r[8] ? 8'd255 : sum_r[7:0]; // Red
            rgb[15:8]  <= sum_g[8] ? 8'd255 : sum_g[7:0]; // Green
            rgb[7:0]   <= sum_b[8] ? 8'd255 : sum_b[7:0]; // Blue
        end
    end

    // 6. HDMI Core Controller
    logic [2:0] tmds;
    logic       tmds_clock;

    hdmi #(
        .VIDEO_ID_CODE          (VIDEO_ID_CODE),
        .VIDEO_REFRESH_RATE     (VIDEO_REFRESH_RATE),
        .AUDIO_RATE             (AUDIO_RATE),
        .AUDIO_BIT_WIDTH        (AUDIO_BIT_WIDTH),
        .DVI_OUTPUT             (DVI_OUTPUT)
    ) u_hdmi (
        .clk_pixel_x5           (clk_pixel_x5),
        .clk_pixel              (clk_pixel),
        .clk_audio              (clk_audio),
        .reset                  (reset),
        .rgb                    (rgb),
        .audio_sample_word      (audio_sample_word),
        .tmds                   (tmds),
        .tmds_clock             (tmds_clock),
        .cx                     (cx),
        .cy                     (cy),
        .frame_width            (frame_width),
        .frame_height           (frame_height),
        .screen_width           (screen_width),
        .screen_height          (screen_height)
    );

    // 7. Xilinx UltraScale+ Differential Output Buffers (UG974 OBUFDS)
    OBUFDS obufds_b   (.I(tmds[0]),    .O(TMDSp[0]),       .OB(TMDSn[0]));
    OBUFDS obufds_g   (.I(tmds[1]),    .O(TMDSp[1]),       .OB(TMDSn[1]));
    OBUFDS obufds_r   (.I(tmds[2]),    .O(TMDSp[2]),       .OB(TMDSn[2]));
    OBUFDS obufds_clk (.I(tmds_clock), .O(TMDSp_clock),   .OB(TMDSn_clock));

endmodule
