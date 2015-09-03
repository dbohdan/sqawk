#!/usr/bin/env tclsh
# Assemble, a tool for bundling Tcl source files.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::assemble {
    variable version 0.2.0
}

proc ::assemble::read-file filename {
    set ch [open $filename]
    set result [read $ch]
    close $ch
    return $result
}

proc ::assemble::line {{char #} {lineWidth 80}} {
    return "# [string repeat $char [expr { $lineWidth - 2 }]]"
}

proc ::assemble::header {text {charLeft { }} {charRight { }} {lineWidth 80}} {
    set text " $text "
    set length [string length $text]
    set padding 2
    set countLeft [expr { ($lineWidth - $length) / 2 - $padding }]
    set countRight [expr { $lineWidth - $countLeft - $length - $padding }]
    set result "# [string repeat $charLeft $countLeft]$text[string repeat \
            $charRight $countRight]"
    return $result
}

# A run a C-style preprocessor on $text.
proc ::assemble::preprocess {text {definitions {ASSEMBLE 1}}} {
    set conditionStack {}
    set result {}
    set skip [list 0] ;# This is a stack.

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
                # Skip the line if one or more conditions are unmet.
                if {{1} ni $skip} {
                    lappend result $line
                }
            }
        }
    }
    return [join $result \n]
}

# Replace all instances of the command "source+ <filename>" with the contents of
# the file $filename.
proc ::assemble::include-sources text {
    set result {}
    foreach line [split $text \n] {
        if {[regexp {^source\+ (.*)$} $line _ includeFilename]} {
            append result \n[header "$includeFilename" = =]\n
            append result [read-file $includeFilename]\n
            append result [header "end $includeFilename" = =]\n
        } else {
            append result $line\n
        }
    }
    return $result
}

proc ::assemble::assemble filename {
    set main [read-file $filename]
    set output [::assemble::preprocess [::assemble::include-sources $main] ]
    puts $output
}

# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    ::assemble::assemble {*}$argv
}
