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
proc ::sqawk::serializers::tcl::serialize {outputRecs options} {
    set useDicts [dict get $options dicts]

    if {$useDicts} {
        set result $outputRecs
    } else {
        set result {}
        foreach record $outputRecs {
            lappend result [dict values $record]
        }
    }
    return $result\n
}
