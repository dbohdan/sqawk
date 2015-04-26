# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
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
proc ::sqawk::parsers::csv::parse {data options} {
    package require csv

    # Parse $args.
    set separator [dict get $options csvsep]
    set quote [dict get $options csvquote]
    set altMode [expr { [dict get $options format] in {csv2 csvalt} }]

    set rows {}
    set lines [split $data \n]
    if {[lindex $lines end] eq {}} {
        set lines [lrange $lines 0 end-1]
    }
    set error [catch {
        set opts {}
        if {$altMode} {
            set opts -alternate
        }
        foreach line $lines {
            lappend rows [list $line {*}[::csv::split {*}$opts $line $separator $quote]]
        }
    } errorMessage errorOptions]
    if {$error} {
        dict set errorOptions \
                -errorinfo "CSV decoding error:\
                        [dict get $errorOptions -errorinfo]"
        return -options $errorOptions $errorMessage
    }

    return $rows
}
