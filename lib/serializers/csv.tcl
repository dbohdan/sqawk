# Sqawk, an SQL Awk.
# Copyright (c) 2015-2018 D. Bohdan
# License: MIT

namespace eval ::sqawk::serializers::csv {
    variable formats {
        csv
    }
    variable options {}
}

# Convert records to CSV.
::snit::type ::sqawk::serializers::csv::serializer {
    variable ch

    constructor {channel options} {
        package require csv

        set ch $channel
    }

    method serialize record {
        puts $ch [::csv::join [dict values $record]]
    }
}
