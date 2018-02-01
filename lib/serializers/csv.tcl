# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018 dbohdan
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
