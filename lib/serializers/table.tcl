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
    # Filter out the field names (dict keys).
    set tableData {}
    foreach record $outputRecs {
        lappend tableData [dict values $record]
    }
    puts [::tabulate::tabulate -data $tableData]
}
