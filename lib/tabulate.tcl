#! /usr/bin/env tclsh
# Tabulate -- turn standard input into a table.
# Copyright (C) 2015, 2016 Danyil Bohdan
# License: MIT
namespace eval ::tabulate {
    variable version 0.10.0
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

# Simulate named arguments in procedures that accept "args".
# Usage: process store <key in the caller's $tokens> in <name of a variable in
# the caller's scope> ?default <default value>? ?store ...?
proc ::tabulate::options::process args {
    set opts [lindex $args 0]
    set parsed [parse-dsl [lrange $args 1 end]]
    uplevel 1 [list ::tabulate::options::process-parsed $opts $parsed]
}

# Convert the human-readable options DSL (see the proc parse below for its
# syntax) into a machine-readable format (a list of dicts).
proc ::tabulate::options::parse-dsl tokens {
    set i 0 ;# $tokens index

    set result {}

    while {$i < [llength $tokens]} {
        switch -exact -- [current] {
            store {
                next

                set item {}
                dict set item useDefaultValue 0

                # Parse.
                dict set item name [current]
                next
                expect in
                next
                dict set item varName [current]
                next

                if {[current] eq {default}} {
                    next
                    dict set item useDefaultValue 1
                    dict set item defaultValue [current]
                    next
                }
            }
            default {
                error "unknown keyword: \"[current]\"; expected \"store\""
            }
        }
        lappend result $item
    }

    return $result
}

# Go to the next token in the proc parse-dsl.
proc ::tabulate::options::next {} {
    upvar 1 i i
    incr i
}

# Return the current token in the proc parse-dsl.
proc ::tabulate::options::current {} {
    upvar 1 i i
    upvar 1 tokens tokens
    return [lindex $tokens $i]
}

# Throw an error unless the current token equals $expected.
proc ::tabulate::options::expect expected {
    set current [uplevel 1 current]
    if {$current ne $expected} {
        error "expected \"$expected\" but got \"$current\""
    }
}

# Process the options in $opts and set the corresponding variables in the
# caller's scope. $declaredOptions is a list of dicts as returns by the proc
# parse-dsl.
proc ::tabulate::options::process-parsed {opts declaredOptions} {
    set names {}

    foreach item $declaredOptions {
        # Store value in the caller's variable $varName.
        upvar 1 [dict get $item varName] var

        set name [dict get $item name]
        lappend names $name
        # Do not use dict operations on $opts in order to produce a proper error
        # message manually below if $opts has an odd number of items.
        set keyIndex [lsearch -exact $opts $name]
        if {$keyIndex > -1} {
            if {$keyIndex + 1 == [llength $opts]} {
                error "no value given for option \"$name\""
            }
            set var [lindex $opts $keyIndex+1]

            # Remove $name and the corresponding value from opts.
            set temp {}
            lappend temp {*}[lrange $opts 0 $keyIndex-1]
            lappend temp {*}[lrange $opts $keyIndex+2 end]
            set opts $temp
        } else {
            if {[dict get $item useDefaultValue]} {
                set var [dict get $item defaultValue]
            } else {
                error "no option \"$name\" given"
            }
        }

    }

    # Ensure $opts is empty.
    if {[llength $opts] > 0} {
        error "unknown option(s): $opts; can use\
                \"[join $names {", "}]\""
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

# Convert a list of lists into a string representing a table in pseudographics.
proc ::tabulate::tabulate args {
    options::process $args \
        store -data in data \
        store -style in style default $::tabulate::style::default \
        store -alignments in align default {} \
        store -margins in margins default 0

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

# Format a list as a table row. Does *not* append a newline after the row.
# $columnAlignments is a list that contains one alignment ("left", "right" or
# "center") for each column. If there are more columns than alignments in
# $columnAlignments "center" is assumed for those columns.
proc ::tabulate::formatRow args {
    options::process $args \
        store -substyle in substyle \
        store -row in row \
        store -widths in columnWidths \
        store -alignments in columnAlignments default {} \
        store -margins in margins default 0

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
            c -
            center {
                set leftPadding [expr { $padding / 2 }]
                set rightPadding [expr { $padding - $leftPadding }]
            }
            l -
            left {
                set leftPadding $margins
                set rightPadding [expr { $padding - $margins }]
            }
            r -
            right {
                set leftPadding [expr { $padding - $margins }]
                set rightPadding $margins
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

# Return the style value if $name is a valid style name.
proc ::tabulate::style::by-name name {
    if {[info exists ::tabulate::style::$name]} {
        return [set ::tabulate::style::$name]
    } else {
        set message {}
        lappend message "Unknown style name: \"$name\"; can use"
        foreach varName [info vars ::tabulate::style::*] {
            lappend message "   - \"[namespace tail $varName]\""
        }
        error [join $message \n]
    }
}

# Read the input, process the command line options and output the result.
proc ::tabulate::main {argv0 argv} {
    options::process $argv \
        store -FS in FS default {} \
        store -style in style default default \
        store -alignments in alignments default {} \
        store -margins in margins default 0
    set data [lrange [split [read stdin] \n] 0 end-1]

    # Input field separator. If none is given treat each line of input as a Tcl
    # list.
    if {$FS ne {}} {
        set updateData {}
        foreach line $data {
            lappend updateData [split $line $FS]
        }
        set data $updateData
    }
    # Accept style names rather than style *values* that ::tabulate::tabulate
    # normally takes.
    set styleName [::tabulate::dict-get-default $argv default -style]

    puts [tabulate -data $data \
            -style [::tabulate::style::by-name $style] \
            -alignments $alignments \
            -margins $margins]
}

#ifndef SQAWK
# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    ::tabulate::main $argv0 $argv
}
#endif
