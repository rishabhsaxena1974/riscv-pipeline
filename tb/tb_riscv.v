// tb_riscv.v - runs one program on riscv_top and writes a retirement trace
//
// Plusargs:
//   +HEX:<file>        program, one 32-bit word per line ($readmemh)
//   +TRACE:<file>      output: one line per retired instruction
//   +MAXCYCLES:<n>     timeout (default 200000)
//
// Trace line:  <pc> <instr> [x<rd>=<value>] [M<bytes>[<addr>]=<value>]
// tools/iss.py writes the same format, so a plain text diff checks every register write
// and every store, in program order. The run ends when ECALL retires.

`timescale 1ns/1ps

module tb_riscv;
    reg clk = 1'b0;
    reg rst = 1'b1;

    always #5 clk = ~clk;

    riscv_top dut (
        .clk        (clk),
        .rst        (rst),
        .imem_we    (1'b0),
        .imem_waddr (10'd0),
        .imem_wdata (32'd0),
        .tohost     ()
    );

    wire        rv     = dut.u_core.retire_valid;
    wire [31:0] rpc    = dut.u_core.retire_pc;
    wire [31:0] rins   = dut.u_core.retire_instr;
    wire        rwe    = dut.u_core.retire_reg_write;
    wire [4:0]  rrd    = dut.u_core.retire_rd;
    wire [31:0] rwd    = dut.u_core.retire_wdata;
    wire        rstore = dut.u_core.retire_store;
    wire [31:0] rsa    = dut.u_core.retire_store_addr;
    wire [31:0] rsd    = dut.u_core.retire_store_data;
    wire [1:0]  rss    = dut.u_core.retire_store_size;

    reg [8*512-1:0] hex_file, trace_file;
    integer fd, max_cycles, cycles, instret, stalls, redirects;
    reg [31:0] st_mask;

    initial begin
        if (!$value$plusargs("HEX:%s", hex_file)) begin
            $display("ERROR: +HEX:<file> not given");
            $finish;
        end
        if (!$value$plusargs("TRACE:%s", trace_file))
            trace_file = "trace.txt";
        if (!$value$plusargs("MAXCYCLES:%d", max_cycles))
            max_cycles = 200000;

        $readmemh(hex_file, dut.u_imem.mem);
        fd = $fopen(trace_file, "w");

        cycles    = 0;
        instret   = 0;
        stalls    = 0;
        redirects = 0;
        repeat (3) @(posedge clk);
        rst <= 1'b0;
    end

    always @(posedge clk) begin
        if (!rst) begin
            cycles = cycles + 1;
            if (dut.u_core.stall)    stalls    = stalls + 1;
            if (dut.u_core.redirect) redirects = redirects + 1;

            if (rv) begin
                instret = instret + 1;
                $fwrite(fd, "%08x %08x", rpc, rins);
                if (rwe)
                    $fwrite(fd, " x%0d=%08x", rrd, rwd);
                if (rstore) begin
                    st_mask = (rss == 2'd0) ? 32'h0000_00ff :
                              (rss == 2'd1) ? 32'h0000_ffff : 32'hffff_ffff;
                    $fwrite(fd, " M%0d[%08x]=%08x", 1 << rss, rsa, rsd & st_mask);
                end
                $fwrite(fd, "\n");
            end

            if (dut.u_core.halted) begin
                $fclose(fd);
                $display("DONE CYCLES=%0d INSTRET=%0d STALLS=%0d REDIRECTS=%0d",
                         cycles, instret, stalls, redirects);
                $finish;
            end

            if (cycles >= max_cycles) begin
                $fclose(fd);
                $display("TIMEOUT CYCLES=%0d INSTRET=%0d", cycles, instret);
                $finish;
            end
        end
    end
endmodule
