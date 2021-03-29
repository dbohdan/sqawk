# Sqawk, an SQL Awk.
# Copyright (c) 2015-2018, 2020 D. Bohdan
# License: MIT

namespace eval ::sqawk::parsers::tcl {
    variable formats {
        tcl
    }
    variable options {
        kv 0
        lines 0
    }
}

::snit::type ::sqawk::parsers::tcl::parser {
    variable kv
    variable linesMode

    variable ch
    variable data
    variable i
    variable keys
    variable len

    constructor {channel options} {
        set kv [dict get $options kv]
        set linesMode [dict get $options lines]

        set i [expr { $kv ? -1 : 0 }]
        if {$linesMode} {
            if {$kv} {
                set lines [split [string trim [read $channel]] \n]
                set data [lmap line $lines {
                    if {[regexp {^\s*$} $line]} continue
                    set line
                }]
            } else {
                set ch $channel
                set data %NEVER_USED%
            }
        } else {
            set data [read $channel]
        }
        set len [llength $data]
    }

    method next {} {
        if {$i == $len} {
            return -code break
        }

        if {!$kv} {
            if {$linesMode} {
                set line {}
                while {[set blank [regexp {^\s*$} $line]] && ![eof $ch]} {
                    gets $ch line
                }

                if {$blank && [eof $ch]} {
                    return -code break
                }

                set list $line
            } else {
                set list [lindex $data $i]
                incr i
            }

            return [list $list {*}$list]
        }

        if {$i == -1} {
            set allKeys [lsort -unique [concat {*}[lmap record $data {
                dict keys $record
            }]]]

            # Order the keys like they are ordered in the first row for
            # ergonomics.  Keys that aren't in the first row follow in
            # alphabetical order after those that are.
            set keys [dict keys [lindex $data 0]]
            foreach key $allKeys {
                if {$key ni $keys} {
                    lappend keys $key
                }
            }

            incr i
            return [list $keys {*}$keys]
        }

        set record [lindex $data $i]
        set row [list $record]
        foreach key $keys {
            if {[dict exists $record $key]} {
                lappend row [dict get $record $key]
            } else {
                lappend row {}
            }
        }

        incr i
        return $row
    }
}
