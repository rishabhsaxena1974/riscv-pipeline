# build.tcl - synthesize, place and route riscv_top on an Artix-7 and report timing/area.
#
# Out-of-context run: the design is not pinned to package I/O, so only register-to-register
# paths inside the core and memories are timed - that is the number that says how fast the
# pipeline itself can be clocked.
#
# usage (from this folder):  vivado -mode batch -source build.tcl -tclargs <period_ns>

set period [expr {[llength $argv] > 0 ? [lindex $argv 0] : 10.0}]
set root   [file normalize [file join [file dirname [info script]] ..]]
set out    [file join $root synth reports]
file mkdir $out

read_verilog [glob [file join $root rtl *.v]]
set_property include_dirs [file join $root rtl] [current_fileset]

synth_design -top riscv_top -part xc7a35tcpg236-1 -mode out_of_context
create_clock -name clk -period $period [get_ports clk]

opt_design
place_design
route_design

report_timing_summary -max_paths 5 -file [file join $out timing_${period}ns.rpt]
report_utilization                 -file [file join $out utilization.rpt]

set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
puts "RESULT period=${period}ns WNS=${wns}ns fmax=[format %.1f [expr {1000.0 / ($period - $wns)}]]MHz"
