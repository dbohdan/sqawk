# Sqawk, an SQL Awk.
# Copyright (c) 2015-2018, 2020 D. Bohdan
# License: MIT

namespace eval ::sqawk::parsers::csv {
    variable formats {
        csv csv2 csvalt
    }
    variable options {
        format csv
        csvsep ,
        csvquote \"
    }
}

# Convert CSV data into a list of database rows.
::snit::type ::sqawk::parsers::csv::parser {
    variable separator
    variable quote
    variable altMode

    variable ch

    constructor {channel options} {
        package require csv

        set ch $channel

        set separator [dict get $options csvsep]
        set quote [dict get $options csvquote]
        set altMode [expr {
            [dict get $options format] in {csv2 csvalt}
        }]
    }

    method next {} {
        if {[gets $ch line] < 0} {
            return -code break {}
        }

        try {
            set row [list $line {*}[::csv::split \
                {*}[expr {$altMode ? {-alternate} : {}}] \
                $line \
                $separator \
                $quote \
            ]]
        } on error {errorMessage errorOptions} {
            dict set errorOptions -errorinfo [list \
                CSV decoding error: \
                [dict get $errorOptions -errorinfo] \
            ]
            return -options $errorOptions $errorMessage
        }
        return $row
    }
}
