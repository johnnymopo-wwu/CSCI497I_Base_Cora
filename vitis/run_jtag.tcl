# Load bitstream, init PS, download and run hello.elf over JTAG.
# Run from CSCI497I_Base_Cora/vitis:   xsdb run_jtag.tcl
set here [file normalize [file dirname [info script]]]
set repo [file normalize [file join $here ..]]
set xsa  [file join $repo fpga project_main project_main.xsa]
set hw   [file join $here hw]
set elf  [file join $here ws hello build hello.elf]

if {![file exists $xsa]} { error "XSA not found: $xsa" }
if {![file exists $elf]} {
    set found [glob -nocomplain [file join $here ws hello * *.elf] [file join $here ws hello *.elf]]
    if {[llength $found] == 0} { error "hello.elf not found under [file join $here ws hello]" }
    set elf [lindex $found 0]
}
puts "run_jtag.tcl: elf = $elf"

# unpack the XSA to get the bitstream and ps7_init.tcl
file delete -force $hw
file mkdir $hw
exec unzip -o -q $xsa -d $hw

# Select a target, retrying while JTAG contexts are (re)appearing.
# Contexts are recreated after hw_server launch, rst -system and fpga.
proc select_target {filter {tries 20}} {
    for {set i 0} {$i < $tries} {incr i} {
        if {![catch {targets -set -nocase -filter $filter}]} { return }
        after 250
    }
    error "run_jtag.tcl: no target matching {$filter}"
}

connect

select_target {name =~ "*A9*#0"}
catch {stop}

select_target {name =~ "APU*"}
rst -system
after 3000

select_target {name =~ "xc7z*"}
fpga [lindex [glob [file join $hw *.bit]] 0]
after 1000

source [file join $hw ps7_init.tcl]
select_target {name =~ "APU*"}
configparams force-mem-access 1
ps7_init
ps7_post_config

select_target {name =~ "*A9*#0"}
dow $elf
configparams force-mem-access 0
con
disconnect
