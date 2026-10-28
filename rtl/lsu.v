// lsu.v - load/store alignment for a 32-bit word-wide, byte-enabled data memory
//
// Stores: the byte or halfword is replicated across the word and the byte enables pick
// the lane, so the memory never has to shift anything.
// Loads: the addressed byte/halfword is shifted down to bit 0, then sign- or zero-
// extended. Accesses are assumed to be naturally aligned (RV32I allows a trap instead).

`timescale 1ns/1ps

module lsu (
    input  wire [2:0]  funct3,       // size [1:0]: 0 byte, 1 half, 2 word; [2]: unsigned load
    input  wire [1:0]  addr_lo,
    // store side
    input  wire [31:0] store_data,
    output reg  [3:0]  byte_en,
    output reg  [31:0] wdata,
    // load side
    input  wire [31:0] rdata,
    output reg  [31:0] load_data
);
    wire [31:0] shifted = rdata >> {addr_lo, 3'b000};

    always @(*) begin
        case (funct3[1:0])
            2'b00: begin
                byte_en = 4'b0001 << addr_lo;
                wdata   = {4{store_data[7:0]}};
            end
            2'b01: begin
                byte_en = addr_lo[1] ? 4'b1100 : 4'b0011;
                wdata   = {2{store_data[15:0]}};
            end
            default: begin
                byte_en = 4'b1111;
                wdata   = store_data;
            end
        endcase

        case (funct3)
            3'b000:  load_data = {{24{shifted[7]}},  shifted[7:0]};     // LB
            3'b001:  load_data = {{16{shifted[15]}}, shifted[15:0]};    // LH
            3'b100:  load_data = {24'd0, shifted[7:0]};                 // LBU
            3'b101:  load_data = {16'd0, shifted[15:0]};                // LHU
            default: load_data = rdata;                                 // LW
        endcase
    end
endmodule
