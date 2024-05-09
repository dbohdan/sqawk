# Sqawk, an SQL awk.
# Copyright (c) 2015-2018, 2020 D. Bohdan
# License: MIT

namespace eval ::sqawk::serializers::json {
    variable formats {
        json
    }
    variable options {
        pretty 0
        kv 1
    }
}

# Convert records to JSON.
::snit::type ::sqawk::serializers::json::serializer {
    variable ch
    variable first 1
    variable initalized 0
    variable kv

    constructor {channel options} {
        package require json::write

        set ch $channel
        set kv [dict get $options kv]
        ::json::write indented [dict get $options pretty]

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

        if {$kv} {
            append fragment [::json::write object {*}$object]
        } else {
            append fragment [::json::write array {*}[dict values $object]]
        }

        puts -nonewline $ch $fragment
    }

    destructor {
        if {$initalized} {
            puts $ch \]
        }
    }
}
