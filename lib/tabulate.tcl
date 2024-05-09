#! /usr/bin/env tclsh
# Tabulate -- turn standard input into a table.
# Copyright (c) 2015-2018, 2020, 2024 D. Bohdan
# License: MIT
namespace eval ::tabulate {
    variable version 0.12.0
    variable wideChars {[\u1100-\u115F\u2329\u232A\u2E80-\u2E99\u2E9B-\u2EF3\u2F00-\u2FD5\u2FF0-\u2FFB\u3001-\u3003\u3004\u3005\u3006\u3007\u3008\u3009\u300A\u300B\u300C\u300D\u300E\u300F\u3010\u3011\u3012-\u3013\u3014\u3015\u3016\u3017\u3018\u3019\u301A\u301B\u301C\u301D\u301E-\u301F\u3020\u3021-\u3029\u302A-\u302D\u302E-\u302F\u3030\u3031-\u3035\u3036-\u3037\u3038-\u303A\u303B\u303C\u303D\u303E\u3041-\u3096\u3099-\u309A\u309B-\u309C\u309D-\u309E\u309F\u30A0\u30A1-\u30FA\u30FB\u30FC-\u30FE\u30FF\u3105-\u312D\u3131-\u318E\u3190-\u3191\u3192-\u3195\u3196-\u319F\u31A0-\u31BA\u31C0-\u31E3\u31F0-\u31FF\u3200-\u321E\u3220-\u3229\u322A-\u3247\u3250\u3251-\u325F\u3260-\u327F\u3280-\u3289\u328A-\u32B0\u32B1-\u32BF\u32C0-\u32FE\u3300-\u33FF\u3400-\u4DB5\u4DB6-\u4DBF\u4E00-\u9FD5\u9FD6-\u9FFF\uA000-\uA014\uA015\uA016-\uA48C\uA490-\uA4C6\uA960-\uA97C\uAC00-\uD7A3\uF900-\uFA6D\uFA6E-\uFA6F\uFA70-\uFAD9\uFADA-\uFAFF\uFE10-\uFE16\uFE17\uFE18\uFE19\uFE30\uFE31-\uFE32\uFE33-\uFE34\uFE35\uFE36\uFE37\uFE38\uFE39\uFE3A\uFE3B\uFE3C\uFE3D\uFE3E\uFE3F\uFE40\uFE41\uFE42\uFE43\uFE44\uFE45-\uFE46\uFE47\uFE48\uFE49-\uFE4C\uFE4D-\uFE4F\uFE50-\uFE52\uFE54-\uFE57\uFE58\uFE59\uFE5A\uFE5B\uFE5C\uFE5D\uFE5E\uFE5F-\uFE61\uFE62\uFE63\uFE64-\uFE66\uFE68\uFE69\uFE6A-\uFE6B\U0001B000-\U0001B001\U0001F200-\U0001F202\U0001F210-\U0001F23A\U0001F240-\U0001F248\U0001F250-\U0001F251\U00020000-\U0002A6D6\U0002A6D7-\U0002A6FF\U0002A700-\U0002B734\U0002B735-\U0002B73F\U0002B740-\U0002B81D\U0002B81E-\U0002B81F\U0002B820-\U0002CEA1\U0002CEA2-\U0002F7FF\U0002F800-\U0002FA1D\U0002FA1E-\U0002FFFD\U00030000-\U0003FFFD]}
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
                dict set item flags [current]
                next
                while {[current] eq {or}} {
                    next
                    dict lappend item flags [current]
                    next
                }
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
                error [list unknown keyword: [current]; expected store]
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
        error [list expected $expected but got $current]
    }
}

# Process the options in $opts and set the corresponding variables in the
# caller's scope. $declaredOptions is a list of dicts as returns by the proc
# parse-dsl.
proc ::tabulate::options::process-parsed {opts declaredOptions} {
    set possibleOptions {}

    foreach item $declaredOptions {
        # Store value in the caller's variable $varName.
        upvar 1 [dict get $item varName] var

        set flags [dict get $item flags]
        set currentOptionSynonyms [format-flag-synonyms $flags]
        lappend possibleOptions $currentOptionSynonyms
        # Do not use dict operations on $opts in order to produce a proper error
        # message manually below if $opts has an odd number of items.
        set found {}
        foreach flag $flags {
            set keyIndex [lsearch -exact $opts $flag]
            if {$keyIndex > -1} {
                if {$keyIndex + 1 == [llength $opts]} {
                    error [list no value given for option $flag]
                }
                set var [lindex $opts $keyIndex+1]

                # Remove $flag and the corresponding value from opts.
                set temp {}
                lappend temp {*}[lrange $opts 0 $keyIndex-1]
                lappend temp {*}[lrange $opts $keyIndex+2 end]
                set opts $temp

                lappend found $flag
            }
        }
        if {[llength $found] == 0} {
            if {[dict get $item useDefaultValue]} {
                set var [dict get $item defaultValue]
            } else {
                error [list no option $currentOptionSynonyms given]
            }
        } elseif {[llength $found] > 1} {
            error [list can't use the flags $found together]
        }

    }

    # Ensure $opts is empty.
    if {[llength $opts] > 0} {
        error [list unknown option(s): $opts; can use: $possibleOptions]
    }
}

# Return a formatted message listing flag synonyms for an option. The first flag
# is considered the main.
proc ::tabulate::options::format-flag-synonyms flags {
    set result \"[lindex $flags 0]\"
    if {[llength $flags] > 1} {
       append result " (\"[join [lrange $flags 1 end] {", "}]\")"
    }
    return $result
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

# Calculate the fixed-font width of a string with wide CJK characters.
proc ::tabulate::wide-char-width s {
    variable wideChars
    string length [regsub -all $wideChars $s --]
}

# Convert a list of lists into a string representing a table in pseudographics.
proc ::tabulate::tabulate args {
    options::process $args \
        store -data in data \
        store -style in style default $::tabulate::style::default \
        store -alignments or -align in alignments default {} \
        store -margins in margins default 0

    # Find out the maximum width of each column.
    set columnWidths {} ;# Dictionary.
    foreach row $data {
        for {set i 0} {$i < [llength $row]} {incr i} {
            set field [lindex $row $i]
            set currentLength [wide-char-width $field]
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
            -alignments $alignments \
            -margins $margins]
    # For each row...
    for {set i 0} {$i < $rowCount} {incr i} {
        set row [lindex $data $i]
        # Row.
        lappend result [::tabulate::formatRow \
                -substyle [dict get $style row] \
                -row $row \
                -widths $columnWidths \
                -alignments $alignments \
                -margins $margins]
        # Separator.
        if {$i < $rowCount - 1} {
            lappend result [::tabulate::formatRow \
                    -substyle [dict get $style separator] \
                    -row $emptyRow \
                    -widths $columnWidths \
                    -alignments $alignments \
                    -margins $margins]
        }
    }
    # Bottom of the table.
    lappend result [::tabulate::formatRow \
            -substyle [dict get $style bottom] \
            -row $emptyRow \
            -widths $columnWidths \
            -alignments $alignments \
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
        store -alignments or -align in columnAlignments default {} \
        store -margins in margins default 0

    set result {}
    append result [dict get $substyle left]
    set fieldCount [expr { [llength $columnWidths] / 2 }]
    for {set i 0} {$i < $fieldCount} {incr i} {
        set field [lindex $row $i]
        set padding [expr {
            [dict get $columnWidths $i] - [wide-char-width $field] + 2 * $margins
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
                error [list unknown alignment: $alignment]
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
        store -alignments or -align in alignments default {} \
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
