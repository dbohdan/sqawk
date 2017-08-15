# Sqawk, an SQL Awk.
# Copyright (C) 2015, 2016, 2017 dbohdan
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
proc ::sqawk::serializers::awk::serialize {outputRecs options} {
    # Parse $args.
    set OFS [dict get $options ofs]
    set ORS [dict get $options ors]

    set text {}
    foreach record $outputRecs {
        append text [join [dict values $record] $OFS]$ORS
    }
    return $text
}
