// hazard_unit.v - load-use stall detection
//
// A load's data only exists at the end of MEM, but the instruction right behind it needs
// it at the start of EX - one cycle too early for forwarding. So when the instruction in
// ID reads the register a load in EX is about to write, hold PC and IF/ID for one cycle
// and send a bubble into EX. Next cycle the load is in WB and its data is forwarded.

`timescale 1ns/1ps

module hazard_unit (
    input  wire       id_valid,
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_uses_rs1,
    input  wire       id_uses_rs2,
    input  wire       ex_mem_read,     // instruction in EX is a load
    input  wire [4:0] ex_rd,
    output wire       stall
);
    assign stall = id_valid && ex_mem_read && ex_rd != 5'd0 &&
                   ((id_uses_rs1 && ex_rd == id_rs1) ||
                    (id_uses_rs2 && ex_rd == id_rs2));
endmodule
