# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018, 2020 D. Bohdan
# License: MIT

namespace eval ::sqawk::parsers::tcl {
    variable formats {
        tcl
    }
    variable options {
        dicts 0
    }
}

::snit::type ::sqawk::parsers::tcl::parser {
    variable useDicts

    variable data
    variable i
    variable keys
    variable len

    constructor {channel options} {
        set useDicts [dict get $options dicts]
        set i [expr { $useDicts ? -1 : 0 }]
        set data [read $channel]
        set len [llength $data]
    }

    method next {} {
        if {$i == $len} {
            return -code break
        }

        if {!$useDicts} {
            set list [lindex $data $i]
            incr i
            return [list $list {*}$list]
        }

        if {$i == -1} {
            set allKeys {}
            foreach record $data {
                set allKeys [lsort -dictionary -unique \
                        [concat $allKeys [dict keys $record]]]
            }

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
