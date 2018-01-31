# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018 dbohdan
# License: MIT

namespace eval ::sqawk::serializers::awk {
    variable formats {
        awk
    }
    variable options {
        ofs {}
        ors {}
    }
}

# Convert records to text.
::snit::type ::sqawk::serializers::awk::serializer {
    variable script
    variable OFS
    variable ORS

    constructor {script_ options} {
        set script $script_
        set OFS [dict get $options ofs]
        set ORS [dict get $options ors]
    }

    method serialize record {
        {*}$script [join [dict values $record] $OFS]$ORS
    }
}
