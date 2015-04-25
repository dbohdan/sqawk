# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk {}

# Performs SQL queries on files and channels.
::snit::type ::sqawk::sqawk {
    variable tables {}
    variable defaultTableNames [split abcdefghijklmnopqrstuvwxyz ""]

    option -database
    option -ofs
    option -ors

    destructor {
        dict for {_ tableObj} $tables {
            $tableObj destroy
        }
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
        ::sqawk::dict-ensure-default fileOptions format {}
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

        if {$metadata(format) in {csv csv2 csvalt}} {
            set altMode 0
            if {$metadata(format) in {csv2 csvalt}} {
                set altMode 1
            }
            set rows [::sqawk::parsers::csv::parse $raw \
                    [list csvsep $metadata(csvsep) \
                            csvquote $metadata(csvquote) \
                            format $metadata(format)]]
        } else {
            set rows [::sqawk::parsers::awk::parse $raw \
                    [list RS $metadata(RS) \
                            FS $metadata(FS) \
                            merge $metadata(merge)]]
        }
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
