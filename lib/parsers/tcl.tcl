# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018 dbohdan
# License: MIT

namespace eval ::sqawk::parsers::tcl {
    variable formats {
        tcl
    }
    variable options {
        dicts 0
    }
}

proc ::sqawk::parsers::tcl::parse {data options} {
    set useDicts [dict get $options dicts]
    set rows {}

    if {$useDicts} {
        set allKeys {}
        foreach record $data {
            set allKeys [lsort -dictionary -unique \
                    [concat $allKeys [dict keys $record]]]
        }
        # Order the keys like they are ordered in the first row for ergonomics.
        # The keys that aren't in the first row follow those that are in
        # alphabetical order.
        set keys [dict keys [lindex $data 0]]
        foreach key $allKeys {
            if {$key ni $keys} {
                lappend keys $key
            }
        }
        lappend rows [list $keys {*}$keys] ;# Header row.

        foreach record $data {
            set row [list $record]
            foreach key $keys {
                if {[dict exists $record $key]} {
                    lappend row [dict get $record $key]
                } else {
                    lappend row {}
                }
            }
            lappend rows $row
        }
    } else {
        foreach record $data {
            lappend rows [list $record {*}$record]
        }
    }

    return $rows
}
