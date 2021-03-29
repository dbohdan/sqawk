# Sqawk, an SQL Awk.
# Copyright (c) 2015-2018 D. Bohdan
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
    variable ch
    variable OFS
    variable ORS

    constructor {channel options} {
        set ch $channel
        set OFS [dict get $options ofs]
        set ORS [dict get $options ors]
    }

    method serialize record {
        puts -nonewline $ch [join [dict values $record] $OFS]$ORS
    }
}
