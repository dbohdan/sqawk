#!/usr/bin/env tclsh
# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT
package require Tcl 8.5
package require cmdline
package require snit 2
package require sqlite3
package require textutil

namespace eval ::sqawk {
    variable version 0.5.0
}
namespace eval ::sqawk::script {
    variable debug 0
    variable profile 0
    if {$profile} {
        package require profiler
        ::profiler::init
    }
}

# Creates and populates an SQLite3 table with a specific format.
::snit::type ::sqawk::table {
    option -database
    option -dbtable
    option -columnprefix
    option -maxnf
    option -header {}

    destructor {
        [$self cget -database] eval "DROP TABLE [$self cget -dbtable]"
    }

    # Return column name for column number $i, custom (if present) or
    # automatically generated.
    method column-name i {
        set customColName [lindex [$self cget -header] $i-1]
        if {($i > 0) && ($customColName ne "")} {
            set colName $customColName
        } else {
            set colName [$self cget -columnprefix]$i
        }
    }

    # Create a database table for the table object.
    method initialize {} {
        set fields {}
        set colPrefix [$self cget -columnprefix]
        set command {
            CREATE TABLE [$self cget -dbtable] (
                ${colPrefix}nr INTEGER PRIMARY KEY,
                ${colPrefix}nf INTEGER,
                [join $fields ","]
            )
        }
        set maxNF [$self cget -maxnf]
        for {set i 0} {$i <= $maxNF} {incr i} {
            lappend fields "[$self column-name $i] INTEGER"
        }
        [$self cget -database] eval [subst $command]
    }

    # Insert each row from the list $rows into the database table in a
    # transaction.
    method insert-rows rows {
        set db [$self cget -database]
        set colPrefix [$self cget -columnprefix]
        set tableName [$self cget -dbtable]

        set commands {}

        set rowInsertCommand {
            INSERT INTO $tableName ($insertColumnNames)
            VALUES ($insertValues)
        }

        set maxNF [$self cget -maxnf]
        for {set i 0} {$i <= $maxNF} {incr i} {
            set columnNames($i) [$self column-name $i]
        }

        $db transaction {
            foreach row $rows {
                set nf [llength $row]
                set insertColumnNames "${colPrefix}nf,${colPrefix}0"
                set insertValues {$nf,$row}
                if {$nf > 0} {
                    append insertColumnNames ,
                    append insertValues ,
                }
                set i 1
                foreach field $row {
                    set lastRow [expr { $i == $nf }]
                    set $columnNames($i) $field
                    append insertColumnNames $columnNames($i)
                    if {!$lastRow} {
                        append insertColumnNames ,
                    }
                    append insertValues "\$$columnNames($i)"
                    if {!$lastRow} {
                        append insertValues ,
                    }
                    incr i
                }
                $db eval [subst $rowInsertCommand]
            }
        }
    }
}

# If key $key is absent in the dictionary variable $dictVarName set it to
# $value.
proc ::sqawk::dict-ensure-default {dictVarName key value} {
    upvar 1 $dictVarName dictionary
    set dictionary [dict merge [list $key $value] $dictionary]
}

# Remove and return $n elements from the list stored in the variable $varName.
proc ::sqawk::lshift! {varName {n 1}} {
    upvar 1 $varName list
    set result [lrange $list 0 $n-1]
    set list [lrange $list $n end]
    return $result
}

# Find which part of the range $number is for the first range it falls into in
# out of the ranges in $rangeList. $rangeList should have the format {from1 to1
# from2 to2 ...}.
proc ::sqawk::range-position {number rangeList} {
    foreach {first last} $rangeList {
        if {$number == $first} {
            if {$first == $last} {
                return both
            } else {
                return first
            }
        } elseif {$number == $last} {
            return last
        }
    }
    return none
}

# If $merge is false lappend $elem to the list stored in $varName. If $merge is
# true append it to the last element of the same list.
proc ::sqawk::lappend-merge! {varName elem merge} {
    upvar 1 $varName list
    if {$merge} {
        lset list end [lindex $list end]$elem
    } else {
        lappend list $elem
    }
}

# Split $str on separators that match $regexp. Returns the resulting list of
# fields with field ranges in $mergeRanges merged together with the separators
# between them preserved.
#
# This procedure is based in part on ::textutil::split::splitx from Tcllib,
# which was originally developed by Bob Techentin and released into the public
# domain by him.
#
# ::textutil::split carries the following copyright notice:
# *****************************************************************************
#       Various ways of splitting a string.
#
# Copyright (c) 2000      by Ajuba Solutions.
# Copyright (c) 2000      by Eric Melski <ericm@ajubasolutions.com>
# Copyright (c) 2001      by Reinhard Max <max@suse.de>
# Copyright (c) 2003      by Pat Thoyts <patthoyts@users.sourceforge.net>
# Copyright (c) 2001-2006 by Andreas Kupries
#                                       <andreas_kupries@users.sourceforge.net>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.
# *****************************************************************************
# The contents of "license.terms" can be found in the file "LICENSE.Tcllib".
proc ::sqawk::splitmerge {str regexp mergeRanges} {
    if {$str eq {}} {
        return {}
    }
    if {$regexp eq {}} {
        return [split $str {}]
    }

    set mergeRangesFiltered {}
    foreach {first last} $mergeRanges {
        if {$first < $last} {
            lappend mergeRangesFiltered $first $last
        }
    }

    # Split $str into a list of fields and separators.
    set fields {}
    set offset 0
    set merging 0
    set i 0
    set rangePos none
    while {[regexp -start $offset -indices -- $regexp $str match]} {
        lassign $match matchStart matchEnd
        set field [string range $str $offset $matchStart-1]

        set rangePos [::sqawk::range-position $i $mergeRangesFiltered]
        ::sqawk::lappend-merge! fields $field $merging
        # Switch merging on the first field of a merge range and off on the
        # last.
        if {$rangePos eq {first}} {
            set merging 1
        } elseif {$rangePos eq {last}} {
            set merging 0
        }
        incr i

        set sep [string range $str $matchStart $matchEnd]
        # Append the separator if merging.
        if {$merging} {
            ::sqawk::lappend-merge! fields $sep $merging
        }

        incr matchEnd
        set offset $matchEnd
    }
    # Handle the remainer of $str after all the separators.
    set tail [string range $str $offset end]
    if {$tail ne {}} {
        if {$rangePos eq {first}} {
            set merging 1
        }
        if {$rangePos eq {last}} {
            set merging 0
        }
        ::sqawk::lappend-merge! fields $tail $merging
    }

    return $fields
}


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

        array set metadata $fileOptions

        # Read the data. Split it first into records then into fields.
        if {[info exists metadata(channel)]} {
            set ch $metadata(channel)
        } elseif {$metadata(filename) eq "-"} {
            set ch stdin
        } else {
            set ch [open $metadata(filename)]
        }
        set records [::textutil::splitx [read $ch] $metadata(RS)]
        close $ch
        # Remove final record if empty (typically due to a newline at the end of
        # the file).
        if {[lindex $records end] eq ""} {
            set records [lrange $records 0 end-1]
        }

        # Split records into fields.
        set rows {}
        if {[info exists metadata(merge)]} {
            # Allow both the {1-2,3-4,5-6} and the {1 2 3 4 5 6} syntax for the
            # merge option.
            set rangeRegexp {[0-9]+-[0-9]+}
            set overallRegexp "^(?:$rangeRegexp,)*$rangeRegexp\$"
            if {[regexp $overallRegexp $metadata(merge)]} {
                set metadata(merge) [string map {- { } , { }} $metadata(merge)]
            }
            foreach record $records {
                lappend rows [::sqawk::splitmerge \
                        $record $metadata(FS) $metadata(merge)]
            }
        } else {
            foreach record $records {
                lappend rows [::textutil::splitx $record $metadata(FS)]
            }
        }

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

# Return a subdictionary of $dictionary with only the keys in $keyList and the
# corresponding values.
proc ::sqawk::script::filter-keys {dictionary keyList {mustExist 1}} {
    set result {}
    foreach key $keyList {
        if {!$mustExist && ![dict exists $dictionary $key]} {
            continue
        }
        dict set result $key [dict get $dictionary $key]
    }
    return $result
}

# Process $argv into a list of per-file options.
proc ::sqawk::script::process-options {argv} {
    set options {
        {FS.arg {[ \t]+} "Input field separator for all files (regexp)"}
        {RS.arg {\n} "Input record separator for all files (regexp)"}
        {OFS.arg { } "Output field separator"}
        {ORS.arg {\n} "Output record separator"}
        {NF.arg 10 "Maximum NF value for all files"}
        {v "Print version"}
        {1 "One field only. A shortcut for -FS '^$'"}
    }

    set usage {[options] script [[setting=value ...] filename ...]}
    set cmdOptions [::cmdline::getoptions argv $options $usage]

    # Report version.
    if {[dict get $cmdOptions v]} {
        puts $::sqawk::version
        exit 0
    }

    lassign [::sqawk::lshift! argv] script
    if {$script eq ""} {
        error "empty script"
    }

    if {[dict get $cmdOptions 1]} {
        dict set cmdOptions FS ^$
    }

    # Substitute slashes. (In FS, RS, FSx and RSx the regexp engine will
    # do this for us.)
    foreach option {OFS ORS} {
        dict set cmdOptions $option [subst -nocommands -novariables \
                [dict get $cmdOptions $option]]
    }

    # Settings that affect the Sqawk object itself.
    set globalOptions [::sqawk::script::filter-keys $cmdOptions { OFS ORS }]

    # Filenames and individual file settings.
    set fileCount 0
    set fileOptionsForAllFiles {}
    set defaultFileOptions [::sqawk::script::filter-keys $cmdOptions {
        FS RS NF
    }]
    set currentFileOptions $defaultFileOptions
    while {[llength $argv] > 0} {
        lassign [::sqawk::lshift! argv] elem
        # setting=value
        if {[regexp {([^=]+)=(.*)} $elem _ key value]} {
            dict set currentFileOptions $key $value
        } else {
            # Filename.
            if {[file exists $elem] || ($elem eq "-")} {
                dict set currentFileOptions filename $elem
                lappend fileOptionsForAllFiles $currentFileOptions
                set currentFileOptions $defaultFileOptions
                incr fileCount
            } else {
                error "can't find file \"$elem\""
            }
        }
    }
    # If no files are given add "-" (standard input) with the current settings
    # to fileOptionsForAllFiles.
    if {$fileCount == 0} {
        dict set currentFileOptions filename -
        lappend fileOptionsForAllFiles $currentFileOptions
    }

    return [list $script $globalOptions $fileOptionsForAllFiles]
}

# Create an SQLite3 database for ::sqawk::sqawk to use.
proc ::sqawk::script::create-database {database} {
    variable debug

    if {$debug} {
        file delete /tmp/sqawk.db
        ::sqlite3 $database /tmp/sqawk.db
    } else {
        ::sqlite3 $database :memory:
    }
}

proc ::sqawk::script::main {argv0 argv {databaseHandle db}} {
    # Try to process the command line options.
    set error [catch {
        lassign [::sqawk::script::process-options $argv] \
                script options fileOptionsForAllFiles
    } errorMessage]
    if {$error} {
        puts "error: $errorMessage"
        exit 1
    }

    # Initialize Sqawk and the corresponding database.
    ::sqawk::script::create-database $databaseHandle
    set sqawkObj [::sqawk::sqawk create %AUTO%]
    $sqawkObj configure \
            -database $databaseHandle \
            -ofs [dict get $options OFS] \
            -ors [dict get $options ORS]

    foreach file $fileOptionsForAllFiles {
        $sqawkObj read-file $file
    }

    set error [catch {
        $sqawkObj perform-query $script
    } errorMessage errorOptions]
    if {$error} {
        # Ignore errors caused by stdout being closed during output (e.g., if
        # someone is piping the output to head(1)).
        if {[lrange [dict get $errorOptions -errorcode] 0 1] ne {POSIX EPIPE}} {
            return -options $errorOptions $errorMessage
        }
    }
    $sqawkObj destroy
}

# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    ::sqawk::script::main $argv0 $argv
    if {$::sqawk::script::profile} {
        foreach line [::profiler::sortFunctions exclusiveRuntime] {
            puts stderr $line
        }
    }
}
