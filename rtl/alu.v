// alu.v - RV32I integer ALU (combinational)
//
// Also computes addresses: load/store (rs1 + imm), branch/JAL targets (pc + imm),
// JALR targets (rs1 + imm), LUI (0 + imm) and AUIPC (pc + imm). The decoder picks the
// operands, so the ALU itself only ever sees two 32-bit values and an operation.

`timescale 1ns/1ps
`include "defs.vh"

module alu (
    input  wire [3:0]  ctrl,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] y
);
    wire [4:0] shamt = b[4:0];    // RV32I shifts use only the low 5 bits

    always @(*) begin
        case (ctrl)
            `ALU_ADD:  y = a + b;
            `ALU_SUB:  y = a - b;
            `ALU_SLL:  y = a << shamt;
            `ALU_SLT:  y = {31'd0, $signed(a) < $signed(b)};
            `ALU_SLTU: y = {31'd0, a < b};
            `ALU_XOR:  y = a ^ b;
            `ALU_SRL:  y = a >> shamt;
            `ALU_SRA:  y = $signed(a) >>> shamt;
            `ALU_OR:   y = a | b;
            `ALU_AND:  y = a & b;
            default:   y = a + b;
        endcase
    end
endmodule
