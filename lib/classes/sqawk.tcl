# Sqawk, an SQL awk.
# Copyright (c) 2015-2018, 2020 D. Bohdan
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

    option -destroytables -default true
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
        if {[$self cget -destroytables]} {
            dict for {_ tableObj} $tables {
                $tableObj destroy
            }
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
            error [list Set-and-update-format-list can't set option $option]
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

    # Create a parser object for the format $format.
    method Make-parser {format channel fileOptions} {
        try {
            set ns [dict get $formatToParser $format]
        } on error {} {
            error [list unknown input format: $format]
        }
        set parseOptions [set ${ns}::options]

        try {
            ${ns}::parser create %AUTO% \
                                 $channel \
                                 [::sqawk::override-keys $parseOptions \
                                                         $fileOptions]
        } on error {errorMessage errorOptions} {
            regsub {^Error in constructor: } $errorMessage {} errorMessage
            return -options $errorOptions $errorMessage
        } on ok parser {}

        return $parser
    }

    # Create a serializer object for the format $format.
    method Make-serializer {format channel sqawkOptions} {
        # Parse $format.
        set splitFormat [split $format ,]
        set formatName [lindex $splitFormat 0]
        set formatOptions {}
        foreach option [lrange $splitFormat 1 end] {
            lassign [split $option =] key value
            lappend formatOptions $key $value
        }
        try {
            set ns [dict get $formatToSerializer $formatName]
        } on error {} {
            error [list unknown output format: $formatName]
        }

        # Get the dict containing the options the serializer accepts with their
        # default values.
        set so [set ${ns}::options]
        # Set the two main options for the "awk" serializer. "awk" is a special
        # case: its options are set based on separate command line arguments
        # whose values are passed to us in $sqawkOptions.
        if {$formatName eq {awk}} {
            if {[dict exists $formatOptions ofs]} {
                error {to set the field separator for the "awk" output format\
                        please use the command line option "-OFS" instead of\
                        the format option "ofs"}
            }
            if {[dict exists $formatOptions ors]} {
                error {to set the record separator for the "awk" output format\
                        please use the command line option "-OFS" instead of\
                        the format option "ofs"}
            }
            dict set so ofs [dict get $sqawkOptions -ofs]
            dict set so ors [dict get $sqawkOptions -ors]
        }
        # Check if all the serializer options we have been given in $format are
        # valid. Replace the default values with the actual values.
        foreach {key value} $formatOptions {
            if {[dict exists $so $key]} {
                dict set so $key $value
            } else {
                error [list unknown option $key for output format $formatName]
            }
        }

        return [${ns}::serializer create %AUTO% $channel $so]
    }

    # Read data from a file or a channel into a new database table. The filename
    # or channel to read from and the options for how to read and store the data
    # are in all set in the dictionary $fileOptions.
    method read-file fileOptions {
        # Set the default table name ("a", "b", "c", ..., "z").
        set defaultTableName [lindex $defaultTableNames [dict size $tables]]
        # Set the default column name prefix equal to the table name.
        ::sqawk::dict-ensure-default fileOptions table $defaultTableName
        ::sqawk::dict-ensure-default fileOptions F0 1
        ::sqawk::dict-ensure-default fileOptions csvquote \"
        ::sqawk::dict-ensure-default fileOptions csvsep ,
        ::sqawk::dict-ensure-default fileOptions format awk
        ::sqawk::dict-ensure-default fileOptions prefix \
                [dict get $fileOptions table]

        array set metadata $fileOptions

        # Read the data.
        if {[info exists metadata(channel)]} {
            set ch $metadata(channel)
        } elseif {$metadata(filename) eq "-"} {
            set ch stdin
        } else {
            set ch [open $metadata(filename)]
        }

        set parser [$self Make-parser $metadata(format) $ch $fileOptions]

        # Create and configure a new table object.
        set newTable [::sqawk::table create %AUTO%]
        $newTable configure \
                -database [$self cget -database] \
                -dbtable $metadata(table) \
                -columnprefix $metadata(prefix) \
                -f0 $metadata(F0) \
                -maxnf $metadata(NF) \
                -modenf $metadata(MNF)
        # Configure datatypes.
        if {[info exists metadata(datatypes)]} {
            $newTable configure -datatypes [split $metadata(datatypes) ,]
        }
        # Configure column names.
        set header {}
        if {[info exists metadata(header)] && $metadata(header)} {
            # Remove the header from the input. Strip the first field
            # (a0/b0/...) from the header.
            set header [lrange [$parser next] 1 end]
        }
        # Override the header with custom column names.
        if {[info exists metadata(columns)]} {
            set customColumnNames [split $metadata(columns) ,]
            set header [list \
                    {*}[lrange $customColumnNames \
                            0 [llength $customColumnNames]-1] \
                    {*}[lrange $header \
                            [llength $customColumnNames] end]]
        }
        $newTable configure -header $header

        $newTable initialize

        $newTable insert-rows [list $parser next]
        $parser destroy
        if {$ch ne {stdin}} {
            close $ch
        }

        dict set tables $metadata(table) $newTable
        return $newTable
    }

    # Perform query $query and output the result to $channel.
    method eval {query {channel stdout}} {
        set sqawkOptions {}
        foreach option [$self info options] {
            dict set sqawkOptions $option [$self cget $option]
        }

        set serializer [$self Make-serializer \
                [$self cget -outputformat] stdout $sqawkOptions]

        # For each row returned...
        [$self cget -database] eval $query results {
            set outputRecord {}
            set keys $results(*)
            foreach key $keys {
                lappend outputRecord $key $results($key)
            }
            $serializer serialize $outputRecord
        }
        $serializer destroy
    }
}
