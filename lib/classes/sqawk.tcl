# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk {}

# Performs SQL queries on files and channels.
::snit::type ::sqawk::sqawk {
    variable tables {}
    variable defaultTableNames [split abcdefghijklmnopqrstuvwxyz ""]
    variable formatToParser {}

    option -database
    option -ofs
    option -ors
    option -parsers -default {} -configuremethod Set-parsers

    constructor {} {
        # Register parsers.
        $self configure -parsers [namespace children ::sqawk::parsers]
    }

    destructor {
        dict for {_ tableObj} $tables {
            $tableObj destroy
        }
    }

    # Update formatToParser dict when the option -parsers is set.
    method Set-parsers {option value} {
        if {$option ne {-parsers}} {
            error {Set-parsers is only for setting the option -parsers}
        }
        set options(-parsers) $value
        foreach ns [$self cget -parsers] {
            foreach format [set ${ns}::formats] {
                dict set formatToParser $format $ns
            }
        }
    }

    # Parse $data from $format into a list of rows.
    method Parse {format data fileOptions} {
        set ns [dict get $formatToParser $format]
        set parseOptions [set ${ns}::options]
        # Override the defaults but do not pass any extra keys to the parser.
        dict for {key _} $parseOptions {
            if {[dict exists $fileOptions $key]} {
                dict set parseOptions $key [dict get $fileOptions $key]
            }
        }
        return [${ns}::parse $data $parseOptions]
    }

    # Read data from a file or a channel into a new database table. The filename
    # or channel to read from and the options for how to read and store the data
    # are in all set in the dictionary $fileOptions.
    method read-file fileOptions {
        # Set the default table name ("a", "b", "c", ..., "z").
        set defaultTableName [lindex $defaultTableNames [dict size $tables]]
        ::sqawk::dict-ensure-default fileOptions table $defaultTableName
        # Set the default column name prefix equal to the table name.
        ::sqawk::dict-ensure-default fileOptions prefix \
                [dict get $fileOptions table]
        ::sqawk::dict-ensure-default fileOptions merge {}
        ::sqawk::dict-ensure-default fileOptions format raw
        ::sqawk::dict-ensure-default fileOptions csvsep ,
        ::sqawk::dict-ensure-default fileOptions csvquote \"

        array set metadata $fileOptions

        # Read the data.
        if {[info exists metadata(channel)]} {
            set ch $metadata(channel)
        } elseif {$metadata(filename) eq "-"} {
            set ch stdin
        } else {
            set ch [open $metadata(filename)]
        }
        set raw [read $ch]
        close $ch

        set rows [$self Parse $metadata(format) $raw $fileOptions]
        unset raw

        # Create and configure a new table object.
        set newTable [::sqawk::table create %AUTO%]
        $newTable configure \
                -database [$self cget -database] \
                -dbtable $metadata(table) \
                -columnprefix $metadata(prefix) \
                -maxnf $metadata(NF)
        if {[info exists metadata(header)] && $metadata(header)} {
            $newTable configure -header [lindex [::sqawk::lshift! rows] 0]
        }
        $newTable initialize

        # Insert rows in the table.
        $newTable insert-rows $rows

        dict set tables $metadata(table) $newTable
        return $newTable
    }

    # Perform query $query and output the result to $channel.
    method perform-query {query {channel stdout}} {
        # For each row returned...
        [$self cget -database] eval $query results {
            set outputRecord {}
            set keys $results(*)
            foreach key $keys {
                lappend outputRecord $results($key)
            }
            set output [join $outputRecord [$self cget -ofs]][$self cget -ors]
            puts -nonewline $channel $output
        }
    }
}
