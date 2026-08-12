`timescale 1ns / 1ps
`default_nettype none

//======================================================================
// Testbench for axis_stat_counter
// 
//
// iverilog -g2012 -Wall -o tb/tb.vvp rtl/axis_stat_counter.v tb/axis_stat_counter_tb.v
// vvp tb/tb.vvp
// gtkwave axis_stat_counter_tb.vcd
//======================================================================


module axis_stat_counter_tb;

    localparam CLK_PERIOD = 10;
    localparam NUM_FRAMES = 100;
    localparam TIMEOUT_NS = 500000;

    localparam DATA_WIDTH = 32;
    localparam KEEP_WIDTH = ((DATA_WIDTH+7)/8);
    localparam TAG_ENABLE = 0;
    localparam TAG_WIDTH = 16;
    localparam TICK_COUNT_WIDTH  = 32;
    localparam BYTE_COUNT_WIDTH  = 32;
    localparam FRAME_COUNT_WIDTH = 32;

    integer error_counter = 0;
    integer i;
    integer frame_len;

    //------------------------------------------------------------------
    // DUT signals
    //   reg  = driven by the testbench  (these are DUT inputs)
    //   wire = driven by the DUT        (these are DUT outputs)
    //------------------------------------------------------------------

    reg clk;
    reg rst;

    // AXI Monitor
    reg [KEEP_WIDTH-1:0]  monitor_axis_tkeep;
    reg                   monitor_axis_tvalid;
    reg                   monitor_axis_tready;
    reg                   monitor_axis_tlast;

    // AXI Status Data Output
    reg                   m_axis_tready;
    wire [7:0]            m_axis_tdata;
    wire                  m_axis_tvalid;
    wire                  m_axis_tlast;  
    wire                  m_axis_tuser;   

    // Configuration
    reg [TAG_WIDTH-1:0]   tag;
    reg                   trigger;

    //Status
    wire                           busy;  
    wire [TICK_COUNT_WIDTH-1:0]    tick_count;
    wire [BYTE_COUNT_WIDTH-1:0]    byte_count;
    wire [FRAME_COUNT_WIDTH-1:0]   frame_count;

    // DUT Instance
    axis_stat_counter
        #(
            .DATA_WIDTH       (DATA_WIDTH),
            .KEEP_WIDTH       (KEEP_WIDTH),
            .TAG_ENABLE       (TAG_ENABLE),
            .TAG_WIDTH        (TAG_WIDTH),
            .TICK_COUNT_WIDTH (TICK_COUNT_WIDTH),
            .BYTE_COUNT_WIDTH (BYTE_COUNT_WIDTH),
            .FRAME_COUNT_WIDTH(FRAME_COUNT_WIDTH)
        ) dut(
        .clk                (clk),
        .rst                (rst),

        .monitor_axis_tkeep (monitor_axis_tkeep),
        .monitor_axis_tvalid(monitor_axis_tvalid),
        .monitor_axis_tready(monitor_axis_tready),
        .monitor_axis_tlast (monitor_axis_tlast),

        .m_axis_tready      (m_axis_tready),
        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tlast       (m_axis_tlast),
        .m_axis_tuser       (m_axis_tuser),

        .tag                (tag),
        .trigger            (trigger),

        .busy               (busy),
        .tick_count         (tick_count),
        .byte_count         (byte_count),
        .frame_count        (frame_count)
    );

    // Clock Generator
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Watchdog
    initial begin
        #TIMEOUT_NS;
        $display("");
        $display("*** TIMEOUT ***");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("axis_stat_counter_tb.vcd");
        $dumpvars(0, axis_stat_counter_tb);
    end


    // Test Sequence
    initial begin
        // --- 1. initialise every stimulus reg ---
        rst                 = 1'b1;               
        monitor_axis_tkeep  = {KEEP_WIDTH{1'b0}};
        monitor_axis_tvalid = 1'b0;
        monitor_axis_tlast  = 1'b0;
        monitor_axis_tready = 1'b1;                
        m_axis_tready       = 1'b1;               
        tag                 = {TAG_WIDTH{1'b0}};
        trigger             = 1'b0;

        repeat(5) @(negedge clk); // wait for 5 rising edges of clk, then contiune
        rst = 1'b0;
        repeat(3) @(negedge clk);

        // Send NUM_FRAMES frames of random length (2..40 words).
        // Minimum is 2: this DUT never counts single-beat frames.
        for (i = 0; i < NUM_FRAMES; i = i + 1) begin
            frame_len = {$random} % 39 + 2;
            send_frame(frame_len);
        end

        // Idle for 3 cycles
        repeat(3) @(negedge clk);

        trigger = 1'b1;
        @(negedge clk);
        trigger = 1'b0;

        repeat(2) @(negedge clk);

        if (frame_count == NUM_FRAMES) begin
            $display("round 1 : expected %0d, got %0d  -- PASS", NUM_FRAMES, frame_count);
        end
        else begin
            $display("round 1 : expected %0d, got %0d  -- FAIL", NUM_FRAMES, frame_count);
            error_counter = error_counter + 1;
        end

        $display("");
        if (error_counter == 0) begin
            $display("ALL TESTS PASSED (%0d errors)", error_counter);
        end
        else begin
            $display("TEST FAILED (%0d errors)", error_counter);
        end

        $finish;
    end

    //------------------------------------------------------------------
    // Send one frame of frame_len words, then leave the bus idle.
    // tlast is asserted on the final word only.
    //------------------------------------------------------------------
    task send_frame;
        input integer frame_len;
        integer i;
        begin
            for (i = 0; i < frame_len; i = i + 1) begin
                @(negedge clk);
                monitor_axis_tvalid = 1'b1;
                monitor_axis_tkeep  = {KEEP_WIDTH{1'b1}};
                monitor_axis_tlast  = (i == frame_len - 1);
                @(posedge clk);
            end

            // teardown - no transfer, just stop driving
            @(negedge clk);
            monitor_axis_tvalid = 1'b0;
            monitor_axis_tlast  = 1'b0;

            // gap between frames
            repeat (2) @(negedge clk);
        end
    endtask

endmodule