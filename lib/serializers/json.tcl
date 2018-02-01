# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018 dbohdan
# License: MIT

namespace eval ::sqawk::serializers::json {
    variable formats {
        json
    }
    variable options {
        arrays 0
        indent 0
    }
}

# Convert records to JSON.
::snit::type ::sqawk::serializers::json::serializer {
    variable ch
    variable useArrays
    variable first 1
    variable initalized 0

    constructor {channel options} {
        package require json::write

        set ch $channel
        set useArrays [dict get $options arrays]
        ::json::write indented [dict get $options indent]

        puts -nonewline $ch \[
        set initalized 1
    }

    method serialize record {
        set fragment [expr {$first ? {} : {,}}]
        set first 0

        set object {}
        foreach {key value} $record {
            lappend object $key [::json::write string $value]
        }

        if {$useArrays} {
            append fragment [::json::write array {*}[dict values $object]]
        } else {
            append fragment [::json::write object {*}$object]
        }

        puts -nonewline $ch $fragment
    }

    destructor {
        if {$initalized} {
            puts $ch \]
        }
    }
}
