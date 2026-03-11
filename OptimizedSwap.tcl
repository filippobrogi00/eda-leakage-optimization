# Global variables (constants)
set TECH_BASENAME "CORE65LP"
set LEAKAGE_MODES [list "LVT" "SVT" "HVT"]

proc colorReset {} {
    puts -nonewline "\033\[0m"      ;# Reset
}

proc colorSetRed {} {
    puts -nonewline "\033\[1;31m"   ;# Red
}

proc colorSetGreen {} {
    puts -nonewline "\033\[1;32m"   ;# Green
}

proc colorSetBlue {} {
    puts -nonewline "\033\[1;34m"   ;# Blue
}

proc printError {msg} {
    colorSetRed
    puts $msg
    colorReset
}

proc printSuccess {msg} {
    colorSetGreen
    puts $msg
    colorReset
}

proc printInfo {msg} {
    colorSetBlue
    puts $msg
    colorReset
}

### @name: CheckAllowedLeakage
### @inputs:
###      leakageMode -> Stirng representing a leakage mode ("LVT", "SVT", "HVT")
### @return:
###      0 on success, -1 on failure
### @desc:
###      Checks that the passed string is one of the allowed leakage modes
proc CheckAllowedLeakage {leakageString} {
    global LEAKAGE_MODES

    if {[lsearch $LEAKAGE_MODES $leakageString] == -1} {
        printError "CellAllowedLeakage(): A wrong leakage string ${leakageString} was passed"
        return -1
    }

    return 0
}



### @name: GetCellThreshold
### @inputs:
###      cellObj -> Cell object
### @return:
###      List with ([LVT/SVT/HVT], [L/S/H])
### @desc:
###      Gets the two parts of the cell "signature" that change based on the tech library
proc GetCellThreshold {cellObj} {
    # Search for the cell in various libs and build the corresponding string
    set techLibraryThreshold ""
    if {[sizeof_collection [get_cells $cellObj -filter "lib_cell.threshold_voltage_group == LVT"]] > 0} {
        set techLibraryThreshold "LVT"
    } elseif {[sizeof_collection [get_cells $cellObj -filter "lib_cell.threshold_voltage_group == SVT"]] > 0} {
        set techLibraryThreshold "SVT"
    } elseif {[sizeof_collection [get_cells $cellObj -filter "lib_cell.threshold_voltage_group == HVT"]] > 0} {
        set techLibraryThreshold "HVT"
    } else {
        printError "GetCellThreshold(): failed to find cell tech library"
        return [list "" ""]
    }

    # Get first char of tech lib threshold to build the final list to return
    set cellThreshold [string index $techLibraryThreshold 0]

    return [list $techLibraryThreshold $cellThreshold]
}


### @name: GetNewCellSignature
### @inputs:
###      cellObj -> cell object
###      newLeakage -> new target leakage ("LVT", "SVT", "HVT")
### @return:
###      The "Cell Signature", defined as the string needed for size_cell as second argument
### @desc:
###      Builds a string we called "Cell Signature" that we can then pass to size_cell to swap the vt
proc GetNewCellSignature {cellObj newLeakage} {
    global TECH_BASENAME

    if {[CheckAllowedLeakage $newLeakage] == -1} {
        printError "GetNewCellSignature(): wrong leakage ${newLeakage}"
        return ""
    }

    # Get the list with (e.g.) "LVT, L"
    set lCellAttributes [GetCellThreshold $cellObj]
    set techLibThresh [lindex $lCellAttributes 0]   ;# "LVT" (e.g.)
    set cellThresh [lindex $lCellAttributes 1]      ;# "L" (e.g.)

    # Create the new strings
    set newCellThresh [string index $newLeakage 0]        ;# "H" (e.g.)
    set newTechLibThresh "${newCellThresh}VT" ;# "HVT" (e.g.)

    # Get cell reference name and swap the _Lx_ char for the new one
    set cellRefName [get_attribute $cellObj ref_name] ;# "HS65_LL_AND2X1" (e.g.)
    set refNamelist [split $cellRefName "_"]
    lset refNamelist 1 "L${newCellThresh}" ;# replace first sublist, first char with the new one
    set newCellRefName [join ${refNamelist} "_"] ;# "HS65_LH_AND2X1" (e.g.)

    # Use them to build the new signature "CORE65LPHVT/HS65_LH_AND2X1 and return it
    set newCellSignature "${TECH_BASENAME}${newTechLibThresh}/${newCellRefName}"

    return $newCellSignature
}




### @name: SwapVt
### @inputs:
###     cellFullName -> reference name of cell to swap
###     currentLeakageMode -> current leakage ("LVT", "SVT" or "HVT")
###     newLeakageMode -> target leakage to swap the cell to
### @return:
###     the new cell reference name after being swapped
### @desc:
###     Swaps cell with reference name "cellFullName" to the specified mode (LVT, SVT or HVT)
proc SwapVt {cellFullName currentLeakageMode newLeakageMode} {
    global TECH_BASENAME

    # Check if both leakage modes (strings) are correct
    if {[CheckAllowedLeakage $currentLeakageMode] == -1} {
        printError "SwapVt(): Wrong current leakage mode ${currentLeakageMode}"
    }
    if {[CheckAllowedLeakage $currentLeakageMode] == -1} {
        printError "SwapVt(): Wrong new leakage mode ${currentLeakageMode}"
    }

    # Check if swapping to a different leakage mode
    if {$currentLeakageMode == $newLeakageMode} {
        printError "SwapVt(): Swapping to same leakage ${currentLeakageMode}"
    }

    # Get target cell to swap
    set cellObject [get_cells $cellFullName]
    set cellFullName [get_attribute $cellObject full_name]
    set cellRefName [get_attribute $cellObject ref_name]

    # Get new cell signature to pass to size_cell
    set cellNewSignature [GetNewCellSignature $cellObject $newLeakageMode]

    # Swap cell
    size_cell $cellFullName $cellNewSignature
    # printInfo "SwapVt(): Swapped $cellFullName to $cellRefName"

    # Update timing info after swapping cell
    update_timing

    # Return the new cell name
    return $cellFullName
}



### @name: TrySwapVT
### @inputs:
###     cellFullName -> reference name of cell to swap
###     currentLeakageMode -> current leakage ("LVT", "SVT" or "HVT")
###     newLeakageMode -> target leakage to swap the cell to
###     slackThreshold -> slack < slackThreshold => violating path
###     maxPaths -> max number of violating paths through the cell
###     cellsList -> ordered cells list
###     index -> index to update the cell object
### @return:
###      0 on success, 1 when reverting swap
### @desc:
###      Tries to swap cell to the new leakage mode using SwapVt.
###      If the new cell doesn't respect the slack, then swaps back.
proc TrySwapVT {cellFullName currentLeakageMode newLeakageMode slackThreshold maxPaths cellsList index} {
    # Old cell info
    set oldCellObj [get_cells $cellFullName]
    set oldRefName [get_attribute $oldCellObj ref_name]
    set oldSlack [get_attribute [get_timing_paths -through $oldCellObj] slack]

    # New cell info
    set newCellFullName [SwapVt $cellFullName $currentLeakageMode $newLeakageMode]
    set newCellObj [get_cells $newCellFullName]
    set newCellRefName [get_attribute $newCellObj ref_name]
    printInfo "Swapped cell ${oldRefName} to ${newCellRefName}"


    # V2: for each endpoint in the netlist, check that its number of violating paths is acceptable
    set endpoints [add_to_collection [all_outputs] [all_registers -data_pins]]
    foreach_in_collection endpoint $endpoints {
        set endpointViolatingPaths [get_timing_paths -to $endpoint -nworst 10000 -slack_lesser_than $slackThreshold]
        set numViolatingPaths [sizeof_collection $endpointViolatingPaths]

        # Check slack is met for every violating path that ends in the endpoint
        set slackNotMet 0
        foreach_in_collection violatingPath $endpointViolatingPaths {
            set violatingPathSlack [get_attribute $violatingPath slack]
            if {$violatingPathSlack < 0} {
                set slackNotMet 1
                break
            }
        }

        # Revert back only if exceed number of violating paths OR slack is not met
        if {$numViolatingPaths >= $maxPaths || $slackNotMet == 1} {
            set revertedFullName [SwapVt $newCellFullName $newLeakageMode $currentLeakageMode] ;# Swap back to LVT
            set revertedRefName [get_attribute [get_cells $revertedFullName] ref_name]
            printInfo "Reverted back cell ${newCellRefName} to ${revertedRefName}"

            # Also update the cell object in the original cell list
            set revertedCellObj [get_cells $revertedFullName]
            lset cellsList $index 1 $revertedCellObj

            return 1
        }

    }

}


##### ================================================================= #####
##### ========================= MAIN FUNCTION ========================= #####
##### ================================================================= #####
proc multiVth {slackThreshold maxPaths} {
    global TECH_BASENAME
    global LEAKAGE_MODES
    # Naming convention:
    #  * l_.... -> list
    #  * c_... -> collection


    # Measure runtime of script
    set scriptStartTime [clock seconds]
    printInfo ">>> multiVth started"

    #### [STEP 1]: Get all LVT cells in the netlist ####
    printSuccess "#### \[STEP 1\] ####"
    set cLVTCells [get_cells -filter "ref_name =~ *_LL_*"]

    printInfo ">>> Found [sizeof_collection $cLVTCells] LVT cells in the netlist"



    #### [STEP 2]: Assign a priority to each found cell based on slack ####
    printSuccess "#### \[STEP 2\] ####"
    # 2.1) Build a (Slack, Reference Name) list for each cell
    set lLVTCellsSlack {}
    foreach_in_collection cell $cLVTCells {
        # For each cell, append its slack (got from the worst path that passes through it) and the cell
        # itself to an LVT cells list
        set path [get_timing_paths -through $cell -nworst 1]
        set slack [get_attribute $path slack]
        lappend lLVTCellsSlack [list $slack $cell]
    }

    # 2.2) Sort by descending slack — higher slack = more replaceable
    set lLVTCellsSlack [lsort -index 0 -real -decreasing $lLVTCellsSlack]



    #### [STEP 3]: Replace cells and update timing ####
    printSuccess "#### \[STEP 3\] ####"

    # 3.1) For each cell, if we can swap it to HVT we do
    set targetListLength [llength $lLVTCellsSlack]
    set noMoreHVTIndex 0
    for {set i 0} { $i < $targetListLength } { incr i } {
        set cell [lindex [lindex $lLVTCellsSlack $i] 1]
        set fullName [get_object_name $cell]
        set oldSlack [get_attribute [get_timing_paths -through $cell] slack]

        set swappingResult [TrySwapVT $fullName "LVT" "HVT" $slackThreshold $maxPaths $lLVTCellsSlack $i]

        # Update slacks inside the list after update_timing, before the new iteration
        foreach item $lLVTCellsSlack {
            set cellObj [lindex [lindex $lLVTCellsSlack $i] 1]
            set updatedSlack [get_attribute [get_timing_paths -through $cellObj] slack]
            lset lLVTCellsSlack $i 0 $updatedSlack
        }

        if {$swappingResult == 1} {
            # Swapped but reverted, no more cell swaping to HVT possible (because ordered),
            # so we start swapping to SVT from the current cell onwards
            incr noMoreHVTIndex -1 ;# decrement
            break
        }

        # If swapped to HVT and still met slack, increment the corresponding index for later use
        incr noMoreHVTIndex
    }

    # 3.2) Then, for every other cell which can't be swapped to HVT because
    # it would violate slack, we try to swap it to SVT
    for {set i $noMoreHVTIndex} { $i < $targetListLength } { incr i } {
        set cell [lindex [lindex $lLVTCellsSlack $i] 1]
        set fullName [get_object_name $cell]
        set oldSlack [get_timing_paths -through $cell]

        set swappingResult [TrySwapVT $fullName "LVT" "SVT" $slackThreshold $maxPaths $lLVTCellsSlack $i]

        # Update slacks inside the list after update_timing, before the new iteration
        foreach item $lLVTCellsSlack {
            set cellObj [lindex [lindex $lLVTCellsSlack $i] 1]
            set updatedSlack [get_attribute [get_timing_paths -through $cellObj] slack]
            lset lLVTCellsSlack $i 0 $updatedSlack
        }

        if {$swappingResult == 1} {
            # Swapped but reverted, no more cell swaping to SVT possible (because ordered)
            # END of swapping possibilites!
            break
        }

    }


    # 3.3) After swapping everything, check that constraints are still met
    update_timing -full


    # Calculate and output runtime
    set scriptEndTime [clock seconds]
    set passedTime [expr {$scriptEndTime - $scriptStartTime}]
    printInfo "Script time: ${passedTime}"

    printSuccess "#### \[SCRIPT END\] ####"
}

