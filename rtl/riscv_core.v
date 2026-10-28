// riscv_core.v - 5-stage pipelined RV32I core (IF, ID, EX, MEM, WB)
//
//   IF   fetch at PC, predict not-taken (next PC = PC + 4)
//   ID   decode, read registers, generate immediate, detect load-use hazards
//   EX   forward operands, ALU, compare branch operands, resolve branches and jumps
//   MEM  access data memory, align/extend load data
//   WB   write the register file
//
// Hazards:
//   data    - forwarding from EX/MEM and MEM/WB into EX; regfile write-through for WB->ID;
//             one-cycle stall for a load followed by a dependent instruction
//   control - branches and jumps resolve in EX; when taken, the two younger instructions
//             in IF/ID and ID/EX are flushed (2-cycle penalty)
//
// Each pipeline register carries a valid bit. A flushed or stalled slot becomes a bubble
// (valid = 0) whose control signals are all cleared, so it cannot write anything.
// The retire_* ports expose the instruction leaving WB, for the testbench trace.

`timescale 1ns/1ps
`include "defs.vh"

module riscv_core (
    input  wire        clk,
    input  wire        rst,             // synchronous, active high

    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    output wire [31:0] dmem_addr,
    output wire [3:0]  dmem_we,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,

    output wire        retire_valid,
    output wire [31:0] retire_pc,
    output wire [31:0] retire_instr,
    output wire        retire_reg_write,
    output wire [4:0]  retire_rd,
    output wire [31:0] retire_wdata,
    output wire        retire_store,
    output wire [31:0] retire_store_addr,
    output wire [31:0] retire_store_data,
    output wire [1:0]  retire_store_size,
    output wire        halted
);
    wire        stall;          // load-use: hold PC and IF/ID, bubble into ID/EX
    wire        redirect;       // taken branch or jump in EX: flush IF/ID and ID/EX
    wire [31:0] redirect_pc;
    wire [31:0] wb_data;

    // ================================ IF ================================
    reg  [31:0] pc;

    always @(posedge clk) begin
        if (rst)           pc <= 32'd0;
        else if (redirect) pc <= redirect_pc;
        else if (!stall)   pc <= pc + 32'd4;
    end

    assign imem_addr = pc;

    // ------------------------------ IF/ID -------------------------------
    reg        if_id_valid;
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;

    always @(posedge clk) begin
        if (rst || redirect)
            if_id_valid <= 1'b0;
        else if (!stall)
            if_id_valid <= 1'b1;
    end

    always @(posedge clk) begin
        if (!stall) begin
            if_id_pc    <= pc;
            if_id_instr <= imem_rdata;
        end
    end

    // ================================ ID ================================
    wire [4:0] id_rs1 = if_id_instr[19:15];
    wire [4:0] id_rs2 = if_id_instr[24:20];
    wire [4:0] id_rd  = if_id_instr[11:7];

    wire        dec_reg_write, dec_mem_read, dec_mem_write;
    wire        dec_branch, dec_jal, dec_jalr, dec_halt;
    wire [1:0]  dec_a_sel;
    wire        dec_b_sel;
    wire [3:0]  dec_alu_ctrl;
    wire        dec_uses_rs1, dec_uses_rs2;
    wire [31:0] id_imm, id_rs1_val, id_rs2_val;

    decoder u_decoder (
        .instr     (if_id_instr),
        .reg_write (dec_reg_write),
        .mem_read  (dec_mem_read),
        .mem_write (dec_mem_write),
        .branch    (dec_branch),
        .jal       (dec_jal),
        .jalr      (dec_jalr),
        .a_sel     (dec_a_sel),
        .b_sel     (dec_b_sel),
        .alu_ctrl  (dec_alu_ctrl),
        .uses_rs1  (dec_uses_rs1),
        .uses_rs2  (dec_uses_rs2),
        .halt      (dec_halt)
    );

    imm_gen u_imm_gen (
        .instr (if_id_instr),
        .imm   (id_imm)
    );

    reg        mem_wb_reg_write;
    reg [4:0]  mem_wb_rd;

    regfile u_regfile (
        .clk (clk),
        .ra1 (id_rs1),
        .ra2 (id_rs2),
        .rd1 (id_rs1_val),
        .rd2 (id_rs2_val),
        .we  (mem_wb_reg_write),
        .wa  (mem_wb_rd),
        .wd  (wb_data)
    );

    reg        id_ex_mem_read;
    reg [4:0]  id_ex_rd;

    hazard_unit u_hazard (
        .id_valid    (if_id_valid),
        .id_rs1      (id_rs1),
        .id_rs2      (id_rs2),
        .id_uses_rs1 (dec_uses_rs1),
        .id_uses_rs2 (dec_uses_rs2),
        .ex_mem_read (id_ex_mem_read),
        .ex_rd       (id_ex_rd),
        .stall       (stall)
    );

    // ------------------------------ ID/EX -------------------------------
    reg        id_ex_valid;
    reg        id_ex_reg_write, id_ex_mem_write;
    reg        id_ex_branch, id_ex_jal, id_ex_jalr, id_ex_halt;
    reg [1:0]  id_ex_a_sel;
    reg        id_ex_b_sel;
    reg [3:0]  id_ex_alu_ctrl;
    reg [2:0]  id_ex_funct3;
    reg [31:0] id_ex_pc, id_ex_instr, id_ex_imm, id_ex_rs1_val, id_ex_rs2_val;
    reg [4:0]  id_ex_rs1, id_ex_rs2;

    // control: cleared into a bubble on flush or stall
    always @(posedge clk) begin
        if (rst || redirect || stall || !if_id_valid) begin
            id_ex_valid     <= 1'b0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read  <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_branch    <= 1'b0;
            id_ex_jal       <= 1'b0;
            id_ex_jalr      <= 1'b0;
            id_ex_halt      <= 1'b0;
        end else begin
            id_ex_valid     <= 1'b1;
            id_ex_reg_write <= dec_reg_write;
            id_ex_mem_read  <= dec_mem_read;
            id_ex_mem_write <= dec_mem_write;
            id_ex_branch    <= dec_branch;
            id_ex_jal       <= dec_jal;
            id_ex_jalr      <= dec_jalr;
            id_ex_halt      <= dec_halt;
        end
    end

    // datapath: no reset needed, a bubble's control bits make these don't-cares
    always @(posedge clk) begin
        id_ex_pc       <= if_id_pc;
        id_ex_instr    <= if_id_instr;
        id_ex_imm      <= id_imm;
        id_ex_rs1_val  <= id_rs1_val;
        id_ex_rs2_val  <= id_rs2_val;
        id_ex_rs1      <= id_rs1;
        id_ex_rs2      <= id_rs2;
        id_ex_rd       <= id_rd;
        id_ex_a_sel    <= dec_a_sel;
        id_ex_b_sel    <= dec_b_sel;
        id_ex_alu_ctrl <= dec_alu_ctrl;
        id_ex_funct3   <= if_id_instr[14:12];
    end

    // ================================ EX ================================
    reg        ex_mem_reg_write;
    reg [4:0]  ex_mem_rd;
    reg [31:0] ex_mem_result;

    wire [1:0] fwd_a, fwd_b;

    forward_unit u_forward (
        .ex_rs1        (id_ex_rs1),
        .ex_rs2        (id_ex_rs2),
        .mem_reg_write (ex_mem_reg_write),
        .mem_rd        (ex_mem_rd),
        .wb_reg_write  (mem_wb_reg_write),
        .wb_rd         (mem_wb_rd),
        .fwd_a         (fwd_a),
        .fwd_b         (fwd_b)
    );

    wire [31:0] ex_rs1_val = (fwd_a == `FWD_MEM) ? ex_mem_result :
                             (fwd_a == `FWD_WB)  ? wb_data       : id_ex_rs1_val;
    wire [31:0] ex_rs2_val = (fwd_b == `FWD_MEM) ? ex_mem_result :
                             (fwd_b == `FWD_WB)  ? wb_data       : id_ex_rs2_val;

    wire [31:0] alu_a = (id_ex_a_sel == `A_PC)   ? id_ex_pc :
                        (id_ex_a_sel == `A_ZERO) ? 32'd0    : ex_rs1_val;
    wire [31:0] alu_b = id_ex_b_sel ? id_ex_imm : ex_rs2_val;
    wire [31:0] alu_y;

    alu u_alu (
        .ctrl (id_ex_alu_ctrl),
        .a    (alu_a),
        .b    (alu_b),
        .y    (alu_y)
    );

    // branch condition, on the forwarded register values
    reg br_cond;
    always @(*) begin
        case (id_ex_funct3)
            3'b000:  br_cond = (ex_rs1_val == ex_rs2_val);                     // BEQ
            3'b001:  br_cond = (ex_rs1_val != ex_rs2_val);                     // BNE
            3'b100:  br_cond = ($signed(ex_rs1_val) <  $signed(ex_rs2_val));   // BLT
            3'b101:  br_cond = ($signed(ex_rs1_val) >= $signed(ex_rs2_val));   // BGE
            3'b110:  br_cond = (ex_rs1_val <  ex_rs2_val);                     // BLTU
            3'b111:  br_cond = (ex_rs1_val >= ex_rs2_val);                     // BGEU
            default: br_cond = 1'b0;
        endcase
    end

    assign redirect    = id_ex_jal || id_ex_jalr || (id_ex_branch && br_cond);
    assign redirect_pc = {alu_y[31:1], 1'b0};     // JALR clears bit 0; others are even

    wire [31:0] ex_result = (id_ex_jal || id_ex_jalr) ? id_ex_pc + 32'd4 : alu_y;

    // ------------------------------ EX/MEM ------------------------------
    reg        ex_mem_valid, ex_mem_mem_read, ex_mem_mem_write, ex_mem_halt;
    reg [2:0]  ex_mem_funct3;
    reg [31:0] ex_mem_pc, ex_mem_instr, ex_mem_rs2_val;

    always @(posedge clk) begin
        if (rst) begin
            ex_mem_valid     <= 1'b0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read  <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_halt      <= 1'b0;
        end else begin
            ex_mem_valid     <= id_ex_valid;
            ex_mem_reg_write <= id_ex_reg_write;
            ex_mem_mem_read  <= id_ex_mem_read;
            ex_mem_mem_write <= id_ex_mem_write;
            ex_mem_halt      <= id_ex_halt;
        end
    end

    always @(posedge clk) begin
        ex_mem_pc      <= id_ex_pc;
        ex_mem_instr   <= id_ex_instr;
        ex_mem_result  <= ex_result;
        ex_mem_rs2_val <= ex_rs2_val;
        ex_mem_rd      <= id_ex_rd;
        ex_mem_funct3  <= id_ex_funct3;
    end

    // =============================== MEM ================================
    wire [3:0]  st_byte_en;
    wire [31:0] st_wdata, ld_data;

    lsu u_lsu (
        .funct3     (ex_mem_funct3),
        .addr_lo    (ex_mem_result[1:0]),
        .store_data (ex_mem_rs2_val),
        .byte_en    (st_byte_en),
        .wdata      (st_wdata),
        .rdata      (dmem_rdata),
        .load_data  (ld_data)
    );

    assign dmem_addr  = ex_mem_result;
    assign dmem_we    = ex_mem_mem_write ? st_byte_en : 4'b0000;
    assign dmem_wdata = st_wdata;

    // ------------------------------ MEM/WB ------------------------------
    reg        mem_wb_valid, mem_wb_mem_read, mem_wb_mem_write, mem_wb_halt;
    reg [2:0]  mem_wb_funct3;
    reg [31:0] mem_wb_pc, mem_wb_instr, mem_wb_result, mem_wb_load_data, mem_wb_rs2_val;

    always @(posedge clk) begin
        if (rst) begin
            mem_wb_valid     <= 1'b0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_mem_read  <= 1'b0;
            mem_wb_mem_write <= 1'b0;
            mem_wb_halt      <= 1'b0;
        end else begin
            mem_wb_valid     <= ex_mem_valid;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_mem_read  <= ex_mem_mem_read;
            mem_wb_mem_write <= ex_mem_mem_write;
            mem_wb_halt      <= ex_mem_halt;
        end
    end

    always @(posedge clk) begin
        mem_wb_pc        <= ex_mem_pc;
        mem_wb_instr     <= ex_mem_instr;
        mem_wb_result    <= ex_mem_result;
        mem_wb_load_data <= ld_data;
        mem_wb_rs2_val   <= ex_mem_rs2_val;
        mem_wb_rd        <= ex_mem_rd;
        mem_wb_funct3    <= ex_mem_funct3;
    end

    // ================================ WB ================================
    assign wb_data = mem_wb_mem_read ? mem_wb_load_data : mem_wb_result;

    assign retire_valid      = mem_wb_valid;
    assign retire_pc         = mem_wb_pc;
    assign retire_instr      = mem_wb_instr;
    assign retire_reg_write  = mem_wb_reg_write && mem_wb_rd != 5'd0;
    assign retire_rd         = mem_wb_rd;
    assign retire_wdata      = wb_data;
    assign retire_store      = mem_wb_mem_write;
    assign retire_store_addr = mem_wb_result;
    assign retire_store_data = mem_wb_rs2_val;
    assign retire_store_size = mem_wb_funct3[1:0];
    assign halted            = mem_wb_valid && mem_wb_halt;
endmodule
