// riscv_top.v - core + instruction memory + data memory
//
// Memory map (Harvard: separate instruction and data spaces)
//   instruction memory  4 KB, PC 0x000 - 0xFFF
//   data memory         1 KB, addresses wrap every 1 KB
//   tohost              a store with address bit 31 set writes this output register
//                       instead of data memory (a "program finished / result" port)

`timescale 1ns/1ps

module riscv_top #(
    parameter IMEM_WORDS = 1024,
    parameter DMEM_WORDS = 256
) (
    input  wire        clk,
    input  wire        rst,
    // program load port
    input  wire        imem_we,
    input  wire [$clog2(IMEM_WORDS)-1:0] imem_waddr,
    input  wire [31:0] imem_wdata,
    output reg  [31:0] tohost
);
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_we;

    wire to_host = dmem_addr[31];

    riscv_core u_core (
        .clk               (clk),
        .rst               (rst),
        .imem_addr         (imem_addr),
        .imem_rdata        (imem_rdata),
        .dmem_addr         (dmem_addr),
        .dmem_we           (dmem_we),
        .dmem_wdata        (dmem_wdata),
        .dmem_rdata        (dmem_rdata),
        .retire_valid      (),
        .retire_pc         (),
        .retire_instr      (),
        .retire_reg_write  (),
        .retire_rd         (),
        .retire_wdata      (),
        .retire_store      (),
        .retire_store_addr (),
        .retire_store_data (),
        .retire_store_size (),
        .halted            ()
    );

    imem #(.WORDS(IMEM_WORDS)) u_imem (
        .clk   (clk),
        .addr  (imem_addr),
        .rdata (imem_rdata),
        .we    (imem_we),
        .waddr (imem_waddr),
        .wdata (imem_wdata)
    );

    dmem #(.WORDS(DMEM_WORDS)) u_dmem (
        .clk   (clk),
        .addr  (dmem_addr),
        .we    (to_host ? 4'b0000 : dmem_we),
        .wdata (dmem_wdata),
        .rdata (dmem_rdata)
    );

    always @(posedge clk) begin
        if (rst)
            tohost <= 32'd0;
        else if (to_host && dmem_we == 4'b1111)
            tohost <= dmem_wdata;
    end
endmodule
