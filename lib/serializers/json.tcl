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
proc ::sqawk::serializers::json::serialize {outputRecs options} {
    package require json::write

    set useArrays [dict get $options arrays]
    set indent [dict get $options indent]

    ::json::write indented $indent

    set topLevel {}
    foreach record $outputRecs {
        set object {}
        foreach {key value} $record {
            lappend object $key [::json::write string $value]
        }
        if {$useArrays} {
            lappend topLevel [::json::write array {*}[dict values $object]]
        } else {
            lappend topLevel [::json::write object {*}$object]
        }
    }
    return [::json::write array {*}$topLevel]\n
}
