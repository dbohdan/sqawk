# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018 dbohdan
# License: MIT

namespace eval ::sqawk::serializers::tcl {
    variable formats {
        tcl
    }
    variable options {
        dicts 0
    }
}

# A (near) pass-through serializer.
::snit::type ::sqawk::serializers::tcl::serializer {
    variable ch
    variable useDicts

    variable first 1
    variable initialized 0

    constructor {channel options} {
        set ch $channel
        set useDicts [dict get $options dicts]
        set initialized 1
    }

    method serialize record {
        set s [expr {$first ? {} : { }}]
        set first 0

        if {$useDicts} {
            append s [list $record]
        } else {
            append s [list [dict values $record]]
        }
        puts -nonewline $ch $s
    }

    destructor {
        if {$initialized} {
            puts $ch {}
        }
    }
}
