// decoder.v - main control: instruction -> control signals (combinational)
//
// uses_rs1/uses_rs2 say whether the instruction actually reads that register. The hazard
// unit needs them so that, for example, a LUI after a load to x5 does not stall just
// because its (unused) rs1 field happens to contain 5.
//
// Every branch and jump computes its target in the ALU (pc + imm, or rs1 + imm for JALR),
// so a separate branch-target adder is not needed. ECALL/EBREAK stop the simulation;
// FENCE and unknown opcodes execute as NOPs.

`timescale 1ns/1ps
`include "defs.vh"

module decoder (
    input  wire [31:0] instr,
    output reg         reg_write,
    output reg         mem_read,
    output reg         mem_write,
    output reg         branch,
    output reg         jal,
    output reg         jalr,
    output reg  [1:0]  a_sel,
    output reg         b_sel,       // 0: rs2, 1: immediate
    output reg  [3:0]  alu_ctrl,
    output reg         uses_rs1,
    output reg         uses_rs2,
    output reg         halt
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire       bit30  = instr[30];

    always @(*) begin
        reg_write = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        branch    = 1'b0;
        jal       = 1'b0;
        jalr      = 1'b0;
        a_sel     = `A_RS1;
        b_sel     = 1'b0;
        alu_ctrl  = `ALU_ADD;
        uses_rs1  = 1'b0;
        uses_rs2  = 1'b0;
        halt      = 1'b0;

        case (opcode)
            `OP_LUI: begin                      // rd = 0 + imm
                reg_write = 1'b1;
                a_sel     = `A_ZERO;
                b_sel     = 1'b1;
            end
            `OP_AUIPC: begin                    // rd = pc + imm
                reg_write = 1'b1;
                a_sel     = `A_PC;
                b_sel     = 1'b1;
            end
            `OP_JAL: begin                      // target = pc + imm, rd = pc + 4
                reg_write = 1'b1;
                jal       = 1'b1;
                a_sel     = `A_PC;
                b_sel     = 1'b1;
            end
            `OP_JALR: begin                     // target = rs1 + imm, rd = pc + 4
                reg_write = 1'b1;
                jalr      = 1'b1;
                b_sel     = 1'b1;
                uses_rs1  = 1'b1;
            end
            `OP_BRANCH: begin                   // target = pc + imm, compare rs1/rs2
                branch    = 1'b1;
                a_sel     = `A_PC;
                b_sel     = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
            end
            `OP_LOAD: begin                     // address = rs1 + imm
                reg_write = 1'b1;
                mem_read  = 1'b1;
                b_sel     = 1'b1;
                uses_rs1  = 1'b1;
            end
            `OP_STORE: begin                    // address = rs1 + imm, data = rs2
                mem_write = 1'b1;
                b_sel     = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
            end
            `OP_IMM: begin                      // bit 30 only matters for SRAI
                reg_write = 1'b1;
                b_sel     = 1'b1;
                alu_ctrl  = {(funct3 == 3'b101) & bit30, funct3};
                uses_rs1  = 1'b1;
            end
            `OP_OP: begin
                reg_write = 1'b1;
                alu_ctrl  = {bit30, funct3};
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
            end
            `OP_SYSTEM: halt = 1'b1;
            default: ;
        endcase
    end
endmodule
