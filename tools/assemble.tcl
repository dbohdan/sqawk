#!/usr/bin/env tclsh
# Assemble, a tool for bundling Tcl source files.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::assemble {}

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

proc ::assemble::assemble filename {
    set main [read-file $filename]
    set output {}
    foreach line [split $main \n] {
        if {[regexp {^source\+ (.*)$} $line _ includeFilename]} {
            append output \n[header "$includeFilename" = =]\n
            append output [read-file $includeFilename]\n
            append output [header "end $includeFilename" = =]\n
        } else {
            append output $line\n
        }
    }
    puts $output
}

# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    ::assemble::assemble {*}$argv
}
