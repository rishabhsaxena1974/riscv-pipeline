// dmem.v - data memory: word-wide, 4 byte-write lanes, asynchronous read
//
// Each byte lane is its own array so that FPGA synthesis maps it to distributed RAM
// directly. Addresses wrap: only addr[AW+1:2] is decoded.

`timescale 1ns/1ps

module dmem #(
    parameter WORDS = 256
) (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [3:0]  we,          // byte enables, already gated by "is a store"
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
    localparam AW = $clog2(WORDS);

    reg [7:0] lane0 [0:WORDS-1];
    reg [7:0] lane1 [0:WORDS-1];
    reg [7:0] lane2 [0:WORDS-1];
    reg [7:0] lane3 [0:WORDS-1];

    wire [AW-1:0] idx = addr[AW+1:2];

    integer i;
    initial for (i = 0; i < WORDS; i = i + 1) begin
        lane0[i] = 8'd0;
        lane1[i] = 8'd0;
        lane2[i] = 8'd0;
        lane3[i] = 8'd0;
    end

    always @(posedge clk) begin
        if (we[0]) lane0[idx] <= wdata[7:0];
        if (we[1]) lane1[idx] <= wdata[15:8];
        if (we[2]) lane2[idx] <= wdata[23:16];
        if (we[3]) lane3[idx] <= wdata[31:24];
    end

    assign rdata = {lane3[idx], lane2[idx], lane1[idx], lane0[idx]};
endmodule
