// imm_gen.v - immediate extraction and sign extension for the five RV32I formats
//
// The instruction bit always lands in the same place (instr[31] is always the sign), which
// is why the B and J immediates look scrambled: the ISA keeps the register fields fixed
// and moves the immediate bits around them instead.

`timescale 1ns/1ps
`include "defs.vh"

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    always @(*) begin
        case (instr[6:0])
            `OP_LUI, `OP_AUIPC:                                   // U-type
                imm = {instr[31:12], 12'd0};
            `OP_JAL:                                              // J-type
                imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            `OP_BRANCH:                                           // B-type
                imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            `OP_STORE:                                            // S-type
                imm = {{21{instr[31]}}, instr[30:25], instr[11:7]};
            default:                                              // I-type
                imm = {{21{instr[31]}}, instr[30:20]};
        endcase
    end
endmodule
