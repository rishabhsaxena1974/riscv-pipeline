// defs.vh - RV32I opcodes and internal control encodings shared by the RTL

`ifndef RV_DEFS_VH
`define RV_DEFS_VH

// opcode = instr[6:0]
`define OP_LUI     7'b0110111
`define OP_AUIPC   7'b0010111
`define OP_JAL     7'b1101111
`define OP_JALR    7'b1100111
`define OP_BRANCH  7'b1100011
`define OP_LOAD    7'b0000011
`define OP_STORE   7'b0100011
`define OP_IMM     7'b0010011
`define OP_OP      7'b0110011
`define OP_SYSTEM  7'b1110011

// ALU control = {instr[30], funct3}: the RV32I encoding already separates the ops,
// bit 3 only distinguishes SUB from ADD and SRA from SRL.
`define ALU_ADD    4'b0000
`define ALU_SUB    4'b1000
`define ALU_SLL    4'b0001
`define ALU_SLT    4'b0010
`define ALU_SLTU   4'b0011
`define ALU_XOR    4'b0100
`define ALU_SRL    4'b0101
`define ALU_SRA    4'b1101
`define ALU_OR     4'b0110
`define ALU_AND    4'b0111

// ALU operand A select
`define A_RS1      2'd0
`define A_PC       2'd1
`define A_ZERO     2'd2

// forwarding mux select
`define FWD_NONE   2'd0    // value read from the register file in ID
`define FWD_WB     2'd1    // from MEM/WB (ALU result or load data)
`define FWD_MEM    2'd2    // from EX/MEM (ALU result)

`endif
