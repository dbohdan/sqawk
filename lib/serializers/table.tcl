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
    variable ch

    variable alignments
    variable margins
    variable style
    variable tableData {}

    variable initialized 0

    constructor {channel options} {
        set ch $channel

        if {([dict get $options align] ne {}) &&
                ([dict get $options alignments] ne {})} {
            error {can't use synonym options "align" and "alignments"\
                   together}
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
            puts $ch [::tabulate::tabulate \
                    -data $tableData \
                    -alignments $alignments \
                    -margins $margins \
                    -style [::tabulate::style::by-name $style]]
        }
    }
}
