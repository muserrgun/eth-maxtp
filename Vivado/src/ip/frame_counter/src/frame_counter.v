`timescale 1ns / 1ps
`default_nettype none

module frame_counter(
    input wire aclk,
    input wire aresetn,

    // Read Address Channel (AR)
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    input  wire [2:0]  s_axi_arprot,
    output wire        s_axi_arready,

    // Read Data Channel (R)
    input  wire        s_axi_rready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,

    // Write Address Channel (AW)
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    input  wire [2:0]  s_axi_awprot,
    output wire        s_axi_awready,

    // Write Data Channel (W)
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    // Write Response Channel (B)
    output wire [1:0] s_axi_bresp,
    output wire       s_axi_bvalid,
    input  wire       s_axi_bready,

    // Monitor Ports
    input  wire [3:0]        tx0_tkeep,
    input  wire              tx0_tvalid,
    input  wire              tx0_tready,
    input  wire              tx0_tlast,
    input  wire [31:0]       tx0_tdata,


    input  wire [3:0]        tx1_tkeep,
    input  wire              tx1_tvalid,
    input  wire              tx1_tready,
    input  wire              tx1_tlast,
    input  wire [31:0]       tx1_tdata

);
    localparam CTRL         = 5'd0;
    localparam STATUS       = 5'd1;
    localparam CYCLES       = 5'd2;
    localparam TX0_FRAMES   = 5'd8;
    localparam TX1_FRAMES   = 5'd9;
    localparam TX0_BYTES    = 5'd16;
    localparam TX1_BYTES    = 5'd17;

    wire rst = ~aresetn;

    wire wr_en;
    wire [4:0]  wr_addr;
    wire [31:0] wr_latch;
    wire [3:0]  wr_strb;
    wire [4:0]  rd_addr;
    reg  [31:0] rd_data;

    wire tx0_busy;
    wire [31:0] tx0_tick_count;
    wire [31:0] tx0_byte_count;
    wire [31:0] tx0_frame_count;

    wire tx1_busy;
    wire [31:0] tx1_tick_count;
    wire [31:0] tx1_byte_count;
    wire [31:0] tx1_frame_count;

    // Capture strobe.  ONE wire to every counter, so all shadow registers
    // latch on the same clock edge
    reg capture;

    // Free-running time base and its shadow, latched by the same strobe.
    reg [31:0] cycle_count;
    reg [31:0] cycle_shadow;
 
    // The instance for AXI Write
    s_axi_lite_write u_write(
        .axi_clk        (aclk),
        .rstn           (aresetn),
        .s_waddr        (s_axi_awaddr),
        .s_waddr_valid  (s_axi_awvalid),
        .s_waddr_ready  (s_axi_awready),
        .s_wdata        (s_axi_wdata),
        .s_wstrb        (s_axi_wstrb),
        .s_wdata_valid  (s_axi_wvalid),
        .s_wdata_ready  (s_axi_wready),
        .s_bresp        (s_axi_bresp),
        .s_bvalid       (s_axi_bvalid),
        .s_bready       (s_axi_bready),
        .wr_en          (wr_en),
        .wr_addr        (wr_addr),
        .wr_latch       (wr_latch),
        .wr_strb        (wr_strb)
    );

    // The instance for AXI Read
    s_axi_lite_read u_read(
        .axi_clk        (aclk),
        .rstn           (aresetn),
        .s_raddr        (s_axi_araddr),
        .s_raddr_valid  (s_axi_arvalid),
        .s_raddr_ready  (s_axi_arready),
        .s_rdata        (s_axi_rdata),
        .s_rdata_resp   (s_axi_rresp),
        .s_rdata_ready  (s_axi_rready),
        .s_rdata_valid  (s_axi_rvalid),
        .rd_addr        (rd_addr),
        .rd_data        (rd_data)
    );

    axis_stat_counter #(
        .DATA_WIDTH (32),
        .TAG_ENABLE (0)
    ) tx0(
        .clk                    (aclk),
        .rst                    (rst),

        .monitor_axis_tkeep     (tx0_tkeep),
        .monitor_axis_tvalid    (tx0_tvalid),
        .monitor_axis_tready    (tx0_tready),
        .monitor_axis_tlast     (tx0_tlast),

        // Status byte-stream is unused
        .m_axis_tready          (1'b1),
        .m_axis_tdata           (),
        .m_axis_tvalid          (),
        .m_axis_tlast           (),
        .m_axis_tuser           (),

        .tag                    (16'd0),        
        .trigger                (capture),

        .busy                   (tx0_busy),
        .tick_count             (tx0_tick_count),
        .byte_count             (tx0_byte_count),
        .frame_count            (tx0_frame_count)
    );

    axis_stat_counter #(
        .DATA_WIDTH (32),
        .TAG_ENABLE (0)
    ) tx1(
        .clk                    (aclk),
        .rst                    (rst),

        .monitor_axis_tkeep     (tx1_tkeep),
        .monitor_axis_tvalid    (tx1_tvalid),
        .monitor_axis_tready    (tx1_tready),
        .monitor_axis_tlast     (tx1_tlast),

        // Status byte-stream is unused
        .m_axis_tready          (1'b1),
        .m_axis_tdata           (),
        .m_axis_tvalid          (),
        .m_axis_tlast           (),
        .m_axis_tuser           (),

        .tag                    (16'd0),        
        .trigger                (capture),

        .busy                   (tx1_busy),
        .tick_count             (tx1_tick_count),
        .byte_count             (tx1_byte_count),
        .frame_count            (tx1_frame_count)
    );


    always@(posedge aclk)
    begin
        if(!aresetn)
            capture <= 0;
        else
            capture <= wr_en && (wr_addr == CTRL) && wr_latch[0] && wr_strb[0];
    end

    always@(posedge aclk)
    begin
        if(!aresetn) begin
            cycle_count  <= 32'd0;
            cycle_shadow <= 32'd0;
        end
        else begin
            cycle_count <= cycle_count + 32'd1;
            if(capture)
                cycle_shadow <= cycle_count;
        end
    end

    always@*
    begin
        case(rd_addr)
        CTRL      :       rd_data = 32'd0;
        STATUS    :       rd_data = {31'd0, tx0_busy | tx1_busy};
        CYCLES    :       rd_data = cycle_shadow;
        TX0_FRAMES:       rd_data = tx0_frame_count;
        TX1_FRAMES:       rd_data = tx1_frame_count;
        TX0_BYTES :       rd_data = tx0_byte_count;
        TX1_BYTES :       rd_data = tx1_byte_count;
        default   :       rd_data = 32'd0;
        endcase
    end


endmodule

// Restore the default so `default_nettype none does not leak into the files
// compiled after this one. s_axi_lite_read.v and s_axi_lite_write.v declare
// their ports without an explicit wire and would fail to compile under it.
`resetall