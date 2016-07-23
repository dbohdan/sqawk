# Sqawk, an SQL Awk.
# Copyright (C) 2015, 2016 Danyil Bohdan
# License: MIT

namespace eval ::sqawk::serializers::table {
    variable formats {
        table
    }
    variable options {
        align {}
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

    if {([dict get $options align] ne {}) &&
            ([dict get $options alignments] ne {})} {
        error "can't use the synonym options \"align\" and \"alignments\"\
                together"
    } elseif {[dict get $options align] ne {}} {
        set alignments [dict get $options align]
    } else {
        set alignments [dict get $options alignments]
    }

    puts [::tabulate::tabulate \
            -data $tableData \
            -alignments $alignments \
            -margins [dict get $options margins] \
            -style [::tabulate::style::by-name [dict get $options style]]]
}
