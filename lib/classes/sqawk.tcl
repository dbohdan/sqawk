# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk {}

# Performs SQL queries on files and channels.
::snit::type ::sqawk::sqawk {
    # Internal object state.
    variable tables {}
    variable defaultTableNames [split abcdefghijklmnopqrstuvwxyz ""]
    variable formatToParser
    variable formatToSerializer

    # Options.
    option -database
    option -ofs
    option -ors

    option -outputformat -default awk
    option -parsers -default {} -configuremethod Set-and-update-format-list
    option -serializers -default {} -configuremethod Set-and-update-format-list

    # Methods.
    constructor {} {
        # Register parsers and serializers.
        $self configure -parsers [namespace children ::sqawk::parsers]
        $self configure -serializers [namespace children ::sqawk::serializers]
    }

    destructor {
        dict for {_ tableObj} $tables {
            $tableObj destroy
        }
    }

    # Update the related format dictionary when the parser or the serializer
    # list option is set.
    method Set-and-update-format-list {option value} {
        set optToDict {
            -parsers formatToParser
            -serializers formatToSerializer
        }
        set possibleOpts [dict keys $optToDict]
        if {$option ni $possibleOpts} {
            error "Set-and-update-format-list can't set the option \"$option\""
        }
        set options($option) $value

        set dictName [dict get $optToDict $option]
        set $dictName {}
        # For each parser/serializer...
        foreach ns $value {
            foreach format [set ${ns}::formats] {
                dict set $dictName $format $ns
            }
        }
    }

    # Parse $data from $format into a list of rows.
    method Parse {format data fileOptions} {
        set error [catch {
            set ns [dict get $formatToParser $format]
        }]
        if {$error} {
            error "unknown input format: \"$format\""
        }
        set parseOptions [set ${ns}::options]
        return [${ns}::parse $data \
                [::sqawk::override-keys $parseOptions $fileOptions]]
    }

    # Serialize a list of rows into text in the format $format.
    method Serialize {format data sqawkOptions} {
        set error [catch {
            set ns [dict get $formatToSerializer $format]
        }]
        if {$error} {
            error "unknown serialization format: \"$format\""
        }
        set serializeOptions [set ${ns}::options]
        return [${ns}::serialize $data \
                [::sqawk::override-keys $serializeOptions $sqawkOptions]]
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
        set outputRecords {}
        [$self cget -database] eval $query results {
            set outputRecord {}
            set keys $results(*)
            foreach key $keys {
                lappend outputRecord $results($key)
            }
            lappend outputRecords $outputRecord
        }
        set sqawkOptions {}
        foreach option [$self info options] {
            dict set sqawkOptions $option [$self cget $option]
        }
        set output [$self Serialize [$self cget -outputformat] $outputRecords \
                $sqawkOptions]
        puts -nonewline $channel $output
    }
}
