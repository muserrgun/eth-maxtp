module s_axi_lite_read(
    input axi_clk,
    input rstn, // axi is reset low

    // Read Address Channel
    input [31:0]        s_raddr,
    input               s_raddr_valid,
    output              s_raddr_ready,

    // Read Data Channel
    input               s_rdata_ready,
    output reg [31:0]   s_rdata,
    output reg [1:0]    s_rdata_resp,
    output reg          s_rdata_valid,

    input  [31:0]       rd_data,
    output [4:0]        rd_addr
);

    localparam RESP_OKAY   = 2'b00; // normal access success
    localparam RESP_SLVERR = 2'b10; // slave error 

    wire ar_handshake = s_raddr_valid & s_raddr_ready; // master sends address
    wire r_handshake  = s_rdata_valid & s_rdata_ready; // master takes data

    // address must be word aligned and inside the 32 word window
    wire addr_ok = (s_raddr[31:7] == 25'd0) & (s_raddr[1:0] == 2'b00);

    assign rd_addr = s_raddr[6:2];

    // handshake
    always@(posedge axi_clk)
    begin
        if(~rstn)
            s_rdata_valid <= 1'b0;
        else if(r_handshake)        
            s_rdata_valid <= 1'b0;
        else if(ar_handshake)
            s_rdata_valid <= 1'b1;
    end

    // accepts new address if not holding data
    assign s_raddr_ready = ~s_rdata_valid;

    // latch the read data and the response at the address handshake
    always@(posedge axi_clk)
    begin
        if(~rstn)
        begin
            s_rdata      <= 32'h0;
            s_rdata_resp <= RESP_OKAY;
        end
        else if(ar_handshake)
        begin
            s_rdata      <= addr_ok ? rd_data : 32'h0;
            s_rdata_resp <= addr_ok ? RESP_OKAY : RESP_SLVERR;
        end
    end

endmodule