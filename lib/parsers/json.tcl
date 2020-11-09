# Sqawk, an SQL Awk.
# Copyright (c) 2020 D. Bohdan
# License: MIT

package require json

namespace eval ::sqawk::parsers::json {
    variable formats {
        json
    }
    variable options {
        arrays 0
    }
}

::snit::type ::sqawk::parsers::json::parser {
    variable useArrays

    variable data
    variable i
    variable keys
    variable len

    constructor {channel options} {
        set useArrays [dict get $options arrays]
        set i [expr { $useArrays ? 0 : -1 }]
        set data [json::json2dict [read $channel]]
        set len [llength $data]
    }

    method next {} {
        if {$i == $len} {
            return -code break
        }

        if {$useArrays} {
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
