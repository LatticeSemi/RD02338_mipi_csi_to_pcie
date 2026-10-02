# Get the current working directory
set current_dir [pwd]

# Extract the folder name from the path
set folder_name [file tail $current_dir]

# Path to the .f file
set f_file_path "$current_dir/$folder_name.f"

# Get the IP directory
set ip_path {/home/lylim/dev/gitea/RD02338_mipi_csi_to_pcie/fpga_lfcpnx/radiant/propelbld_mipi_csi_to_pcie/lib/latticesemi.com/ip/pcie_axis_dma/.update}

set reflib_path [file join $ip_path testbench pcie_tb] 

# Map library to existing pcie_tb in testbench folder
vmap pcie_tb $reflib_path

# Read the file content
set file_id [open $f_file_path r]
set file_data [read $file_id]
close $file_id

# Split into lines
set lines [split $file_data "\n"]

# Insert -reflib
set last_reflib_index -1
for {set i 0} {$i < [llength $lines]} {incr i} {
    if {[string match "-reflib *" [lindex $lines $i]]} {
        set last_reflib_index $i
    }
}
if {$last_reflib_index >= 0} {
    set before [lrange $lines 0 $last_reflib_index]
    set after [lrange $lines [expr {$last_reflib_index + 1}] end]
    set lines [concat $before "-reflib pcie_tb" $after]
} else {
    set lines [concat "-reflib $reflib_path" $lines]
}

# Insert +noacc+pcie_tb.* after +noacc+ovi_lfcpnx.*
set last_ovi_lfcpnx_index -1
for {set i 0} {$i < [llength $lines]} {incr i} {
    if {[string match "+noacc+ovi_lfcpnx.*" [lindex $lines $i]]} {
        set last_ovi_lfcpnx_index $i
    }
}
if {$last_ovi_lfcpnx_index >= 0} {
    set before [lrange $lines 0 $last_ovi_lfcpnx_index]
    set after [lrange $lines [expr {$last_ovi_lfcpnx_index + 1}] end]
    set lines [concat $before "+noacc+pcie_tb.*" $after]
} else {
    set lines [concat "+noacc+$reflib_path" $lines]
}

# Modify -vopt.options block
set updated_lines {}
set in_vopt_block 0
foreach line $lines {
    if {$line eq "-vopt.options"} {
        set in_vopt_block 1
        lappend updated_lines $line
        continue
    }
    if {$in_vopt_block} {
        if {[string match "*-suppress *" $line]} {
            lappend updated_lines "  -suppress vopt-7033"
            continue
        }
        if {$line eq "-end"} {
            set in_vopt_block 0
            lappend updated_lines $line
            continue
        }
        continue
    }
    # Skip lines containing pcie_bfm_x4_4.v or pcie_model_x4_4.v or axi4_master_bfm.v
    if {[string match "*pcie_bfm_x4_4.v*" $line] || [string match "*pcie_model_x4_4.v*" $line] || [string match "*axi4_master_bfm.v*" $line]} {
        continue
    }
    if {$line eq "-do \"view wave\""} {
        lappend updated_lines "-do \"log /* -r -optcells\""
    }
    lappend updated_lines $line
}

# Write back to the file
set updated_content [join $updated_lines "\n"]
set file_id [open $f_file_path w]
puts $file_id $updated_content
close $file_id
