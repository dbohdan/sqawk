# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT
namespace eval ::sqawk::serializers::table {
    variable formats {
        table
    }
    variable options {
    }
}

proc ::sqawk::serializers::table::serialize {outputRecs options} {
    puts [::tabulate::tabulate -data $outputRecs]
}
