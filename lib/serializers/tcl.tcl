# Sqawk, an SQL awk.
# Copyright (c) 2015-2018, 2020 D. Bohdan
# License: MIT

namespace eval ::sqawk::serializers::tcl {
    variable formats {
        tcl
    }
    variable options {
        kv 0
        pretty 0
    }
}

# A (near) pass-through serializer.
::snit::type ::sqawk::serializers::tcl::serializer {
    variable ch
    variable kv
    variable pretty

    variable first 1
    variable initialized 0

    constructor {channel options} {
        set ch $channel
        set kv [dict get $options kv]
        set pretty [dict get $options pretty]
        set initialized 1
    }

    method serialize record {
        set s [expr {$pretty || $first ? {} : { }}]
        set first 0

        if {$kv} {
            append s [list $record]
        } else {
            append s [list [dict values $record]]
        }

        if {$pretty} {
            append s \n
        }

        puts -nonewline $ch $s
    }

    destructor {
        if {$initialized && !$pretty} {
            puts $ch {}
        }
    }
}
