// forward_unit.v - operand forwarding (bypass) select for the EX stage
//
// The register file is read in ID, but the two instructions ahead may not have written
// their results yet. If one of them is going to write the register EX needs, take the
// value from its pipeline register instead. EX/MEM wins over MEM/WB because it holds the
// younger, i.e. most recent, write. x0 is never forwarded: writes to it are discarded.

`timescale 1ns/1ps
`include "defs.vh"

module forward_unit (
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    input  wire       mem_reg_write,
    input  wire [4:0] mem_rd,
    input  wire       wb_reg_write,
    input  wire [4:0] wb_rd,
    output wire [1:0] fwd_a,
    output wire [1:0] fwd_b
);
    assign fwd_a = (mem_reg_write && mem_rd != 5'd0 && mem_rd == ex_rs1) ? `FWD_MEM :
                   (wb_reg_write  && wb_rd  != 5'd0 && wb_rd  == ex_rs1) ? `FWD_WB  :
                                                                           `FWD_NONE;
    assign fwd_b = (mem_reg_write && mem_rd != 5'd0 && mem_rd == ex_rs2) ? `FWD_MEM :
                   (wb_reg_write  && wb_rd  != 5'd0 && wb_rd  == ex_rs2) ? `FWD_WB  :
                                                                           `FWD_NONE;
endmodule
