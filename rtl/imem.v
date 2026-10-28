// imem.v - instruction memory: asynchronous read, plus a write port for loading a program
//
// The write port is how a program gets in on real hardware (a boot loader or debug port);
// the testbench instead preloads `mem` with $readmemh. Keeping the write port also stops
// synthesis from treating the memory as a constant ROM and optimizing the core away.

`timescale 1ns/1ps

module imem #(
    parameter WORDS = 1024
) (
    input  wire        clk,
    input  wire [31:0] addr,
    output wire [31:0] rdata,
    input  wire        we,
    input  wire [$clog2(WORDS)-1:0] waddr,
    input  wire [31:0] wdata
);
    localparam AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];

    integer i;
    initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h0000_0013;   // NOP

    always @(posedge clk)
        if (we) mem[waddr] <= wdata;

    assign rdata = mem[addr[AW+1:2]];
endmodule
