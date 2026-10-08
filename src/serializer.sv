`timescale 1ns / 1ps

// =============================================================================
// AMD / Xilinx Kintex UltraScale+ (UG974) Serializer Implementation
// Target Architecture: UltraScale+ (KU5P)
// Uses ODDRE1 primitives combined with 5:1 shift registers to achieve
// 10:1 DDR TMDS serialization.
// =============================================================================

module serializer
#(
    parameter int NUM_CHANNELS = 3,
    parameter real VIDEO_RATE  = 74.25E6
)
(
    input  logic       clk_pixel,
    input  logic       clk_pixel_x5,
    input  logic       reset,
    input  logic [9:0] tmds_internal [NUM_CHANNELS-1:0],
    output logic [2:0] tmds,
    output logic       tmds_clock
);

    // Shift registers for TMDS data channels
    logic [9:0] shift_q [NUM_CHANNELS-1:0] = '{default: 10'd0};

    // TMDS clock pattern: 5 ones, 5 zeros (50% duty cycle pixel clock)
    logic [9:0] shift_clk = 10'b0000011111;

    // Clock domain crossing handshake from clk_pixel to clk_pixel_x5
    logic tmds_toggle = 1'b0;
    always_ff @(posedge clk_pixel)
    begin
        if (reset)
            tmds_toggle <= 1'b0;
        else
            tmds_toggle <= ~tmds_toggle;
    end

    // Dedicated Xilinx ASYNC_REG attribute prevents optimization and places
    // synchronizer flip-flops in the same slice to reduce MTBF
    (* ASYNC_REG = "TRUE" *) logic [2:0] toggle_sync = 3'b0;
    always_ff @(posedge clk_pixel_x5)
    begin
        if (reset)
            toggle_sync <= 3'b0;
        else
            toggle_sync <= {toggle_sync[1:0], tmds_toggle};
    end

    // Pulse generated once every 5 cycles of clk_pixel_x5 (synchronous to clk_pixel)
    logic load;
    assign load = toggle_sync[2] ^ toggle_sync[1];

    // 5:1 DDR shift registers and ODDRE1 instantiations for video channels
    genvar ch;
    generate
        for (ch = 0; ch < NUM_CHANNELS; ch++)
        begin: gen_tmds_ch
            always_ff @(posedge clk_pixel_x5)
            begin
                if (reset)
                    shift_q[ch] <= 10'd0;
                else if (load)
                    shift_q[ch] <= tmds_internal[ch];
                else
                    shift_q[ch] <= {2'b00, shift_q[ch][9:2]}; // Shift out 2 bits per cycle
            end

            // Dedicated DDR output register for UltraScale / UltraScale+ (UG974)
            ODDRE1 #(
                .IS_C_INVERTED(1'b0),
                .IS_D1_INVERTED(1'b0),
                .IS_D2_INVERTED(1'b0),
                .SIM_DEVICE("ULTRASCALE_PLUS"),
                .SRVAL(1'b0)
            ) oddre1_data_inst (
                .Q(tmds[ch]),           // 1-bit serial output to IOB
                .C(clk_pixel_x5),       // High-speed 5x clock
                .D1(shift_q[ch][0]),    // Output on rising edge (bit 0 first)
                .D2(shift_q[ch][1]),    // Output on falling edge (bit 1 second)
                .SR(reset)              // Active-high asynchronous reset
            );
        end
    endgenerate

    // TMDS clock channel serialization
    always_ff @(posedge clk_pixel_x5)
    begin
        if (reset)
            shift_clk <= 10'b0000011111;
        else if (load)
            shift_clk <= 10'b0000011111;
        else
            shift_clk <= {2'b00, shift_clk[9:2]};
    end

    ODDRE1 #(
        .IS_C_INVERTED(1'b0),
        .IS_D1_INVERTED(1'b0),
        .IS_D2_INVERTED(1'b0),
        .SIM_DEVICE("ULTRASCALE_PLUS"),
        .SRVAL(1'b0)
    ) oddre1_clk_inst (
        .Q(tmds_clock),         // 1-bit clock output to IOB
        .C(clk_pixel_x5),       // High-speed 5x clock
        .D1(shift_clk[0]),      // Output on rising edge
        .D2(shift_clk[1]),      // Output on falling edge
        .SR(reset)              // Active-high asynchronous reset
    );

endmodule
