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
    variable script

    constructor {script_ options} {
        package require csv

        set script $script_
    }

    method serialize record {
        {*}$script [::csv::join [dict values $record]]\n
    }
}
