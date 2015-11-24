# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk::serializers::table {
    variable formats {
        table
    }
    variable options {
        alignments {}
        margins 0
        style default
    }
}

proc ::sqawk::serializers::table::serialize {outputRecs options} {
    # Filter out the field names (dict keys).
    set tableData {}
    foreach record $outputRecs {
        lappend tableData [dict values $record]
    }
    puts [::tabulate::tabulate \
            -data $tableData \
            -alignments [dict get $options alignments] \
            -margins [dict get $options margins] \
            -style [::tabulate::style::by-name [dict get $options style]]]
}
