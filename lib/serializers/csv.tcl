# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk::serializers::csv {
    variable formats {
        csv
    }
    variable options {}
}

# Convert records to text.
proc ::sqawk::serializers::csv::serialize {outputRecs options} {
    package require csv

    set text {}
    foreach record $outputRecs {
        append text [::csv::join $record]\n
    }
    return $text
}
