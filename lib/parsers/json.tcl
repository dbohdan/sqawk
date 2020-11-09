# Sqawk, an SQL Awk.
# Copyright (c) 2020 D. Bohdan
# License: MIT

package require json

namespace eval ::sqawk::parsers::json {
    variable formats {
        json
    }
    variable options {
        kv 1
        lines 0
    }
}

::snit::type ::sqawk::parsers::json::parser {
    variable kv

    variable data
    variable i
    variable keys
    variable len

    constructor {channel options} {
        set kv [dict get $options kv]
        set i [expr { $kv ? -1 : 0 }]

        if {[dict get $options lines]} {
            set lines [split [string trim [read $channel]] \n]
            set data [lmap line $lines {
                if {[regexp {^\s*$} $line]} continue
                json::json2dict $line
            }]
        } else {
            set data [json::json2dict [read $channel]]
        }

        set len [llength $data]
    }

    method next {} {
        if {$i == $len} {
            return -code break
        }

        if {!$kv} {
            set array [lindex $data $i]

            incr i
            return [list $array {*}$array]
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