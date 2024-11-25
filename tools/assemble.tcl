#!/usr/bin/env tclsh
# Assemble, a tool for bundling Tcl source files.
# Copyright (c) 2015-2019, 2024 D. Bohdan
# License: MIT

namespace eval ::assemble {
    variable version 1.0.0
}

proc ::assemble::read-text-file {filename {linePrefix {}}} {
    set ch [open $filename]
    set result {}
    while {[gets $ch line] >= 0} {
        append result $linePrefix$line\n
    }
    close $ch
    return $result
}

proc ::assemble::header {text {charLeft { }} {charRight { }}
                         {linePrefix {}} {lineWidth 80}} {
    set text " $text "
    set length [string length $text]
    set padding [expr { 2 + [string length $linePrefix] }]
    set countLeft [expr { ($lineWidth - $length) / 2 - $padding }]
    set countRight [expr { $lineWidth - $countLeft - $length - $padding }]

    set result {}
    append result "$linePrefix# [string repeat $charLeft $countLeft]"
    append result $text[string repeat $charRight $countRight]
    return $result
}

# A run a C-style preprocessor on $text.
proc ::assemble::preprocess {text {definitions {ASSEMBLE 1}}} {
    set conditionStack {}
    set result {}
    # A stack for the skip conditions. It grows with each #ifdef/#ifndef.
    set skip [list 0]

    foreach line [split $text \n] {
        lassign [split $line] command arg1 arg2
        switch -exact -- $command {
            \#define {
                if {$arg2 eq {}} {
                    dict set definitions $arg1 1
                } else {
                    dict set definitions $arg1 $arg2
                }
            }
            \#undef {
                dict unset definitions $arg1
            }
            \#ifdef {
                lappend skip [expr {
                    ![dict exists $definitions $arg1]
                }]
            }
            \#ifndef {
                lappend skip [dict exists $definitions $arg1]
            }
            \#endif {
                set skip [lrange $skip 0 end-1]
            }
            default {
                # Skip the line if at least one skip condition is met.
                if {{1} ni $skip} {
                    lappend result $line
                }
            }
        }
    }
    return [join $result \n]
}

# Replace all instances of the command [source+ filename] with the contents of
# the file $filename.
proc ::assemble::include-sources text {
    set result {}
    foreach line [split $text \n] {
        if {[regexp {^(\s*)source\+ (.*)$} $line _ whitespace filename]} {
            append result \n[header $filename = = $whitespace]\n
            append result [read-text-file $filename $whitespace]\n
            append result [header "end $filename" = = $whitespace]\n
        } else {
            append result $line\n
        }
    }
    return $result
}

proc ::assemble::assemble filename {
    set main [read-text-file $filename]
    set output [preprocess [include-sources $main] ]
    puts $output
}

# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    ::assemble::assemble {*}$argv
}
