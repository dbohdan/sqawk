# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018 dbohdan
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

::snit::type ::sqawk::serializers::table::serializer {
    variable script

    variable alignments
    variable margins
    variable style
    variable tableData {}

    variable initialized 0

    constructor {script_ options} {
        set script $script_

        if {([dict get $options align] ne {}) &&
                ([dict get $options alignments] ne {})} {
            error "can't use the synonym options \"align\" and \"alignments\"\
                    together"
        } elseif {[dict get $options align] ne {}} {
            set alignments [dict get $options align]
        } else {
            set alignments [dict get $options alignments]
        }
        set margins [dict get $options margins]
        set style [dict get $options style]

        set initialized 1
    }

    method serialize record {
        lappend tableData [dict values $record]
    }

    destructor {
        if {$initialized} {
            {*}$script [::tabulate::tabulate \
                    -data $tableData \
                    -alignments $alignments \
                    -margins $margins \
                    -style [::tabulate::style::by-name $style]]
        }
    }
}
