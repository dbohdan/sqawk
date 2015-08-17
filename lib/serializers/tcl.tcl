# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk::serializers::tcl {
    variable formats {
        tcl
    }
    variable options {}
}

# A (near) pass-through serializer.
proc ::sqawk::serializers::tcl::serialize {outputRecs options} {
    return $outputRecs\n
}
