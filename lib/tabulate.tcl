#! /usr/bin/env tclsh
# Tabulate -- turn standard input into a table.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT
namespace eval ::tabulate {
    variable version 0.8.0
}
namespace eval ::tabulate::style {
    variable default {
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
    variable loFi {
        top {
            left +
            padding -
            separator +
            right +
        }
        separator {
            left +
            padding -
            separator +
            right +
        }
        row {
            left |
            padding { }
            separator |
            right |
        }
        bottom {
            left +
            padding -
            separator +
            right +
        }
    }
}

namespace eval ::tabulate::options {}

# Simulate keyword arguments in procedures that accept "args".
# Usage: store <key in the caller's $args> in <name of a variable in the
# caller's scope> ?default <default value>?
proc ::tabulate::options::store {name {__in__ {}} varName
        {__default__ {}} {default {}}} {
    if {$__in__ ne {in}} {
        error "incorrect keyword: \"$__in__\" instead of \"in\""
    }
    set useDefaultValue 0
    if {$__default__ ne {}} {
        if {$__default__ ne {default}} {
            error "incorrect keyword: \"$__default__\" instead of \"default\""
        }
        set useDefaultValue 1
    }
    upvar 1 args arguments
    upvar 1 $varName var
    if {[dict exists $arguments $name]} {
        set var [dict get $arguments $name]
    } else {
        if {$useDefaultValue} {
            set var $default
        } else {
            error "no argument \"$name\" given"
        }
    }
    dict unset arguments $name
}

# Check that the caller's $args is empty.
proc ::tabulate::options::got-all {} {
    upvar 1 args arguments
    set keys [dict keys $arguments]
    if {[llength $keys] > 0} {
        set keysQuoted {}
        foreach key $keys {
            lappend keysQuoted "\"$key\""
        }
        error "unknown option(s): [join $keysQuoted {, }]"
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
# $columnAlignments is a list that contains one alignment ("left", "right" or
# "center") for each column. If there are more columns than alignments in
# $columnAlignments "center" is assumed for those columns.
proc ::tabulate::formatRow args {
    options::store -substyle in substyle
    options::store -row in row
    options::store -widths in columnWidths
    options::store -alignments in columnAlignments default {}
    options::store -margins in margins default 0
    options::got-all

    set result {}
    append result [dict get $substyle left]
    set fieldCount [expr { [llength $columnWidths] / 2 }]
    for {set i 0} {$i < $fieldCount} {incr i} {
        set field [lindex $row $i]
        set padding [expr {
            [dict get $columnWidths $i] - [string length $field] + 2 * $margins
        }]
        set alignment [lindex $columnAlignments $i]
        switch -exact -- $alignment {
            {} -
            center {
                set rightPadding [expr { $padding / 2 }]
                set leftPadding [expr { $padding - $rightPadding }]
            }
            left {
                set rightPadding [expr { $padding - $margins }]
                set leftPadding $margins
            }
            right {
                set rightPadding $margins
                set leftPadding [expr { $padding - $margins }]
            }
            default {
                error "unknown alignment: \"$alignment\""
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
    options::store -data in data
    options::store -style in style default $::tabulate::style::default
    options::store -alignments in align default {}
    options::store -margins in margins default 0
    options::got-all

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
    lappend result [::tabulate::formatRow \
            -substyle [dict get $style top] \
            -row $emptyRow \
            -widths $columnWidths \
            -alignments $align \
            -margins $margins]
    # For each row...
    for {set i 0} {$i < $rowCount} {incr i} {
        set row [lindex $data $i]
        # Row.
        lappend result [::tabulate::formatRow \
                -substyle [dict get $style row] \
                -row $row \
                -widths $columnWidths \
                -alignments $align \
                -margins $margins]
        # Separator.
        if {$i < $rowCount - 1} {
            lappend result [::tabulate::formatRow \
                    -substyle [dict get $style separator] \
                    -row $emptyRow \
                    -widths $columnWidths \
                    -alignments $align \
                    -margins $margins]
        }
    }
    # Bottom of the table.
    lappend result [::tabulate::formatRow \
            -substyle [dict get $style bottom] \
            -row $emptyRow \
            -widths $columnWidths \
            -alignments $align \
            -margins $margins]

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

#ifndef SQAWK
# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    ::tabulate::main $argv0 $argv
}
#endif
