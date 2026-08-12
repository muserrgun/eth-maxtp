module s_axi_lite_write(
    input axi_clk,
    input rstn,

    // Write Address Channel (AW)
    input [31:0]    s_waddr,
    input           s_waddr_valid,
    output          s_waddr_ready,

    // Write Data Channel (W)
    input [31:0]    s_wdata,
    input [3:0]     s_wstrb,
    input           s_wdata_valid,
    output          s_wdata_ready,

    // Write Response Channel (B)
    output [1:0]    s_bresp,
    output reg      s_bvalid,
    input           s_bready,

    output wr_en,
    output [4:0]    wr_addr,
    output [31:0]   wr_latch,
    output [3:0]    wr_strb
);

    reg addr_done;
    reg data_done;

    reg ok_latch;

    reg [4:0]  addr_latch;
    reg [31:0] data_latch;
    reg [3:0]  strb_latch;

    wire aw_handshake = s_waddr_valid & s_waddr_ready;
    wire w_handshake  = s_wdata_valid & s_wdata_ready;
    wire b_handshake  = s_bvalid & s_bready;

    localparam RESP_OKAY   = 2'b00; // normal access success
    localparam RESP_SLVERR = 2'b10; // slave error 

    wire addr_ok = (s_waddr[31:7]==25'd0) & (s_waddr[1:0]==2'b00);

    // AW Channel
    always@(posedge axi_clk)
    begin
        if(~rstn)
        begin
            addr_done  <= 1'b0;
            addr_latch <= 5'd0;
            ok_latch   <= 1'b0;
        end
        else if(b_handshake)
            addr_done <= 1'b0;
        else if(aw_handshake)
        begin
            addr_done  <= 1'b1;
            addr_latch <= s_waddr[6:2];
            ok_latch   <= addr_ok;
        end
    end

    assign s_waddr_ready = ~addr_done;

    // W Channel
    always@(posedge axi_clk)
    begin
        if(~rstn)
        begin
            data_done  <= 1'b0;
            data_latch <= 32'd0;
            strb_latch <= 4'd0; 
        end
        else if(b_handshake)
            data_done <= 1'b0;
        else if(w_handshake)
        begin
            data_done <= 1'b1;
            data_latch <= s_wdata;
            strb_latch <= s_wstrb;
        end
    end

    assign s_wdata_ready = ~data_done;


    wire commit = addr_done & data_done & ~s_bvalid;

    assign wr_en = commit & ok_latch;
    assign wr_addr = addr_latch;
    assign wr_latch = data_latch;
    assign wr_strb = strb_latch;

    // B Channel
    always@(posedge axi_clk)
    begin
        if(~rstn)
            s_bvalid <= 1'b0;
        else if(b_handshake)
            s_bvalid <= 1'b0;
        else if(commit)
            s_bvalid <= 1'b1;
    end

    assign s_bresp = ok_latch ? RESP_OKAY : RESP_SLVERR;


endmodule