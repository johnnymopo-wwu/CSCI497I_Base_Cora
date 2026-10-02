
set origin_dir [file dirname [info script]]
set proj_name  "project_main"
set proj_dir   [file join $origin_dir $proj_name]
set src_dir    [file join $origin_dir "src"]

set fpga_part  "xc7z007sclg400-1"
set board_part "digilentinc.com:cora-z7-07s:part0:1.1"

create_project $proj_name $proj_dir -part $fpga_part -force

set_property board_part $board_part [current_project]
set_property target_language Verilog [current_project]

set hdl_dir [file join $src_dir "hdl"]
set hdl_files [glob -nocomplain \
    [file join $hdl_dir "*.v"] \
    [file join $hdl_dir "*.vh"] \
    [file join $hdl_dir "*.sv"] \
    [file join $hdl_dir "*.svh"] \
]

if {[llength $hdl_files] > 0} {
    add_files -norecurse $hdl_files
    update_compile_order -fileset sources_1
} else {
    puts "WARNING: no .v/.vh/.sv/.svh files found in $hdl_dir"
}

set_property top main [current_fileset]
update_compile_order -fileset sources_1

source [file join $src_dir "bd" "design_main.tcl"]

set bd_file [get_files "design_main.bd"]
if {[llength $bd_file] > 0} {
    generate_target all [get_files $bd_file] -force
    export_ip_user_files -of_objects [get_files $bd_file] -no_script -sync -force -quiet
} else {
    puts "WARNING: no block design found after sourcing design_main.tcl \                                                                                                                    
          -- check that it calls create_bd_design."
}

puts "create.tcl: project_main created at $proj_dir"

if {"build" in $argv} {
    puts "will now build"

    launch_runs synth_1 -jobs 24
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
        error "ERROR: synth_1 did not complete successfully"
    }

    set dbg_dir [file join $src_dir "dbg"]
    set dbg_files [glob -nocomplain [file join $dbg_dir "*.xdc"]]

    if {[llength $dbg_files] > 0} {
        puts "create.tcl: found [llength $dbg_files] debug script(s) in $dbg_dir"
        open_run synth_1

        foreach dbg_file $dbg_files {
            puts "create.tcl: sourcing debug script $dbg_file"
            source $dbg_file
        }

        save_constraints -force
    } else {
        puts "create.tcl: no debug scripts found in $dbg_dir -- skipping debug core insertion"
    }

    launch_runs impl_1 -to_step write_bitstream -jobs 24
    wait_on_run impl_1
    if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
        error "ERROR: impl_1 did not complete successfully"
    }

    open_run impl_1

    write_hw_platform -fixed -include_bit -force \
        -file [file join $proj_dir "${proj_name}.xsa"]

    puts "create.tcl: bitstream generated and hardware exported to \
          [file join $proj_dir "${proj_name}.xsa"]"

}

exit
