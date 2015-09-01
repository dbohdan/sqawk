#! /usr/bin/env tclsh
# Tabulate -- turn standard input into a table.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT
namespace eval ::tabulate {
    variable version 0.3.1
    variable defaultStyle {
        top {
            left ┌
            padding ─
            separator ┬
            right ┐
        }
        separator {
            left ├
            padding ─
            separator ┼
            right ┤
        }
        row {
            left │
            padding { }
            separator │
            right │
        }
        bottom {
            left └
            padding ─
            separator ┴
            right ┘
        }
    }
}

# Return a value from dictionary like [dict get] would if it is there.
# Otherwise return the default value.
proc ::tabulate::dict-get-default {dictionary default args} {
    if {[dict exists $dictionary {*}$args]} {
        dict get $dictionary {*}$args
    } else {
        return $default
    }
}

# Format a list as a table row. Does *not* append a newline after the row.
proc ::tabulate::formatRow {row columnWidths substyle alignment} {
    set result {}
    append result [dict get $substyle left]
    set fieldCount [expr { [llength $columnWidths] / 2 }]
    for {set i 0} {$i < $fieldCount} {incr i} {
        set field [lindex $row $i]
        set padding [expr {
            [dict get $columnWidths $i] - [string length $field]
        }]
        switch -exact -- $alignment {
            center {
                set rightPadding [expr { $padding / 2 }]
                set leftPadding [expr { $padding - $rightPadding }]
            }
            left {
                set rightPadding $padding
                set leftPadding 0
            }
            right {
                set rightPadding 0
                set leftPadding $padding
            }
            default {
                error "unknown row alignment: \"$alignment\""
            }
        }
        append result [string repeat [dict get $substyle padding] $leftPadding]
        append result $field
        append result [string repeat [dict get $substyle padding] $rightPadding]
        if {$i < $fieldCount - 1} {
            append result [dict get $substyle separator]
        }
    }
    append result [dict get $substyle right]
    return $result
}

# Convert a list of lists into a string representing a table in pseudographics.
proc ::tabulate::tabulate args {
    set data [dict get $args -data]
    set style [::tabulate::dict-get-default $args \
            $::tabulate::defaultStyle -style]
    set align [::tabulate::dict-get-default $args center -align]

    # Find out the maximum width of each column.
    set columnWidths {} ;# Dictionary.
    foreach row $data {
        for {set i 0} {$i < [llength $row]} {incr i} {
            set field [lindex $row $i]
            set currentLength [string length $field]
            set width [::tabulate::dict-get-default $columnWidths 0 $i]
            if {($currentLength > $width) || ($width == 0)} {
                dict set columnWidths $i $currentLength
            }
        }
    }

    # A dummy row for formatting the table's decorative elements with
    # [formatRow].
    set emptyRow {}
    for {set i 0} {$i < ([llength $columnWidths] / 2)} {incr i} {
        lappend emptyRow {}
    }

    set result {}
    set rowCount [llength $data]
    # Top of the table.
    lappend result [::tabulate::formatRow $emptyRow \
            $columnWidths [dict get $style top] $align]
    # For each row...
    for {set i 0} {$i < $rowCount} {incr i} {
        set row [lindex $data $i]
        # Row.
        lappend result [::tabulate::formatRow $row \
                $columnWidths [dict get $style row] $align]
        # Separator.
        if {$i < $rowCount - 1} {
            lappend result [::tabulate::formatRow $emptyRow \
                    $columnWidths [dict get $style separator] $align]
        }
    }
    # Bottom of the table.
    lappend result [::tabulate::formatRow $emptyRow \
            $columnWidths [dict get $style bottom] $align]

    return [join $result \n]
}

# Read the input, process the command line options and output the result.
proc ::tabulate::main {argv0 argv} {
    set data [lrange [split [read stdin] \n] 0 end-1]

    # Input field separator. If none is given treat each line of input as a Tcl
    # list.
    set FS [::tabulate::dict-get-default $argv {} -FS]
    if {$FS ne {}} {
        set updateData {}
        foreach line $data {
            lappend updateData [split $line $FS]
        }
        set data $updateData
        dict unset argv FS
    }

    puts [tabulate -data $data {*}$argv]
}

# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0]) &&
        ![string match sqawk* [file tail $argv0]]} {
    ::tabulate::main $argv0 $argv
}
