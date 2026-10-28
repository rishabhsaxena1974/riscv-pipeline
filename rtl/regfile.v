// regfile.v - 32 x 32-bit register file, 2 asynchronous read ports, 1 write port
//
// x0 always reads as zero. A write and a read of the same register in the same cycle
// return the new value (write-through bypass): the instruction in WB writes while the
// instruction three behind it reads in ID, and without the bypass ID would see the old
// value.

`timescale 1ns/1ps

module regfile (
    input  wire        clk,
    input  wire [4:0]  ra1,
    input  wire [4:0]  ra2,
    output wire [31:0] rd1,
    output wire [31:0] rd2,
    input  wire        we,
    input  wire [4:0]  wa,
    input  wire [31:0] wd
);
    reg [31:0] regs [0:31];

    integer i;
    initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'd0;

    always @(posedge clk)
        if (we && wa != 5'd0) regs[wa] <= wd;

    assign rd1 = (ra1 == 5'd0)           ? 32'd0 :
                 (we && wa == ra1)       ? wd    : regs[ra1];
    assign rd2 = (ra2 == 5'd0)           ? 32'd0 :
                 (we && wa == ra2)       ? wd    : regs[ra2];
endmodule
