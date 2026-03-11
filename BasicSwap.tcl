####################  Label: BasicSwap.tcl ####################
#
# INPUTS:
#   slackThreshold: Slack Threshold
#   maxPaths:       Maximum number of violating paths
#
# OVERVIEW:
#   Optimizes leakage power by replacing LVT cells with HVT/SVT
#   - 50% of highest slack cells swapped to HVT
#   - Next 25% swapped to SVT
######################################################################

# === Swap function using full ref path ===
proc swap_vt {cellName new_ref_path} {
    set cell [get_cells $cellName]
    if {[sizeof_collection [get_lib_cells $new_ref_path]] > 0} {
        size_cell $cell $new_ref_path
        puts "Swapped $cellName to $new_ref_path"
    } else {
        puts ">>> WARNING: $new_ref_path not found. Skipping $cellName"
    }
}

# === Main optimization procedure ===
proc multiVth {slackThreshold maxPaths} {

    set start_time [clock seconds]
    puts ">>> multiVth started"

    # STEP 1: Get all LVT cells based on ref_name prefix
    set lvt_cells {}
    foreach_in_collection cell [get_cells] {
        set ref [get_attribute $cell ref_name]
        if {[string match "HS65_LL_*" $ref]} {
            lappend lvt_cells $cell
        }
    }
    puts ">>> Found [llength $lvt_cells] LVT cells (based on name match)"

    # STEP 2: Assign priority based on slack
    puts ">>> Step 2: Scoring LVT cells..."
    set priority_list {}

    foreach cell $lvt_cells {
        set paths [get_timing_paths -through $cell -nworst 1]
        if {[sizeof_collection $paths] == 0} {
            continue
        }
        set slack [get_attribute $paths slack]
        lappend priority_list [list $slack $cell]
    }

    set sorted_cells [lsort -index 0 -real -decreasing $priority_list]
    set total_cells [llength $sorted_cells]
    puts ">>> Scored and sorted $total_cells LVT cells"

    # STEP 3: Plan replacements — 50% to HVT, 25% to SVT
    puts ">>> Step 3: Preparing to replace cells..."
    set num_hvt [expr {int($total_cells * 0.5)}]
    set num_svt [expr {int($total_cells * 0.25)}]
    puts ">>> Planning to replace $num_hvt cells with HVT and $num_svt cells with SVT"

    set hvt_changed_cells {}
    set svt_changed_cells {}
    set hvt_failed 0
    set svt_failed 0

    # Replace top 50% with HVT
    for {set i 0} {$i < $num_hvt && $i < $total_cells} {incr i} {
        set cell [lindex [lindex $sorted_cells $i] 1]
        set name [get_object_name $cell]
        set old_ref [get_attribute $cell ref_name]

        set new_ref [string map {"HS65_LL_" "HS65_LH_"} $old_ref]
        set new_cell_path "CORE65LPHVT/${new_ref}"

        if {[sizeof_collection [get_lib_cells $new_cell_path]] == 0} {
            puts ">>> WARNING: Cannot replace $name ($old_ref) — target $new_cell_path does not exist"
            incr hvt_failed
            continue
        }

        lappend hvt_changed_cells [list $name $old_ref $new_cell_path]
    }

    # Replace next 25% with SVT
    for {set i $num_hvt} {$i < ($num_hvt + $num_svt) && $i < $total_cells} {incr i} {
        set cell [lindex [lindex $sorted_cells $i] 1]
        set name [get_object_name $cell]
        set old_ref [get_attribute $cell ref_name]

        set new_ref [string map {"HS65_LL_" "HS65_LS_"} $old_ref]
        set new_cell_path "CORE65LPSVT/${new_ref}"

        if {[sizeof_collection [get_lib_cells $new_cell_path]] == 0} {
            puts ">>> WARNING: Cannot replace $name ($old_ref) — target $new_cell_path does not exist"
            incr svt_failed
            continue
        }

        lappend svt_changed_cells [list $name $old_ref $new_cell_path]
    }

    # STEP 4: Apply swaps
    puts ">>> Step 4: Applying HVT swaps..."
    foreach entry $hvt_changed_cells {
        set cell_name [lindex $entry 0]
        set new_ref_path [lindex $entry 2]
        swap_vt $cell_name $new_ref_path
    }

    puts ">>> Step 4: Applying SVT swaps..."
    foreach entry $svt_changed_cells {
        set cell_name [lindex $entry 0]
        set new_ref_path [lindex $entry 2]
        swap_vt $cell_name $new_ref_path
    }


    # === Summary ===
    puts ">>> === SUMMARY ==="
    puts ">>> Total LVT cells analyzed: $total_cells"
    puts ">>> Targeted for HVT: $num_hvt"
    puts ">>> Targeted for SVT: $num_svt"
    puts ">>> Actually swapped to HVT: [llength $hvt_changed_cells]"
    puts ">>> Actually swapped to SVT: [llength $svt_changed_cells]"
    puts ">>> Failed HVT swaps: $hvt_failed"
    puts ">>> Failed SVT swaps: $svt_failed"

    # STEP 5: Update timing after replacements
    puts ">>> Step 5: Updating timing..."
    update_timing -full

    set end_time [clock seconds]
    puts ">>> multiVth finished in [expr {$end_time - $start_time}] seconds"
}
