# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018 dbohdan
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

        set error [catch {
            set row [list $line {*}[::csv::split \
                {*}[expr {$altMode ? {-alternate} : {}}] \
                $line \
                $separator \
                $quote \
            ]]
        } errorMessage errorOptions]
        if {$error} {
            dict set errorOptions \
                    -errorinfo "CSV decoding error:\
                            [dict get $errorOptions -errorinfo]"
            return -options $errorOptions $errorMessage
        }
        return $row
    }
}
