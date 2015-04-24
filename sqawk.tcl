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

    # Returns column name for column number $i, custom (if present) or
    # automatically generate.
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

    # Insert each row from the list $rows into the table in a transaction.
    method insert-rows rows {
        set db [$self cget -database]
        set colPrefix [$self cget -columnprefix]
        set tableName [$self cget -dbtable]

        set commands {}

        set rowInsertCommand {
            INSERT INTO $tableName ($insertColumnNames)
            VALUES ($insertValues);
        }

        set maxNF [$self cget -maxnf]
        for {set i 0} {$i <= $maxNF} {incr i} {
            set columnNames($i) [$self column-name $i]
        }

        $db transaction {
            foreach row $rows {
                set insertColumnNames "${colPrefix}nf,${colPrefix}0,"
                set insertValues {$nf,$row,}
                set i 1
                set nf [llength $row]
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

# Performs SQL queries on files and channels.
::snit::type ::sqawk::sqawk {
    variable tables {}
    variable defaultTableNames [split {abcdefghijklmnopqrstuvwxyz} ""]

    option -database
    option -ofs
    option -ors

    destructor {
        dict for {_ tableObj} $tables {
            $tableObj destroy
        }
    }

    # Read data from the file specified in the dictionary $fileOptions into a
    # new database table.
    method read-file fileOptions {
        # Set the default table name ("a", "b", "c", ..., "z").
        set defaultTableName [lindex $defaultTableNames [dict size $tables]]
        ::sqawk::dict-ensure-default fileOptions table $defaultTableName
        # Set the default column name prefix equal to the table name.
        ::sqawk::dict-ensure-default fileOptions prefix \
                [dict get $fileOptions table]
        ::sqawk::dict-ensure-default fileOptions header 0

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

        if {[lindex $records end] eq ""} {
            set records [lrange $records 0 end-1]
        }
        set rows {}
        foreach record $records {
            lappend rows [::textutil::splitx $record $metadata(FS)]
        }

        # Create and configure a new table object.
        set newTable [::sqawk::table create %AUTO%]
        $newTable configure -database [$self cget -database]
        $newTable configure -dbtable $metadata(table)
        $newTable configure -columnprefix $metadata(prefix)
        $newTable configure -maxnf $metadata(NF)
        if {$metadata(header)} {
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
    set fileOptions {}
    set defaultFileOptions [::sqawk::script::filter-keys $cmdOptions {
        FS RS NF
    }]
    set currentFileSettings $defaultFileOptions
    while {[llength $argv] > 0} {
        lassign [::sqawk::lshift! argv] elem
        # setting=value
        if {[regexp {([^=]+)=(.*)} $elem _ key value]} {
            dict set currentFileSettings $key $value
        } else {
            # Filename.
            if {[file exists $elem] || ($elem eq "-")} {
                dict set currentFileSettings filename $elem
                lappend fileOptions $currentFileSettings
                set currentFileSettings $defaultFileOptions
                incr fileCount
            } else {
                error "can't find file \"$elem\""
            }
        }
    }
    # If no files are given add "-" (standard input) with the current settings
    # to fileOptions.
    if {$fileCount == 0} {
        dict set currentFileSettings filename -
        lappend fileOptions $currentFileSettings
    }

    return [list $script $globalOptions $fileOptions]
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
                script options fileOptions
    } errorMessage]
    if {$error} {
        puts "error: $errorMessage"
        exit 1
    }

    # Initialize Sqawk and the corresponding database.
    ::sqawk::script::create-database $databaseHandle
    set obj [::sqawk::sqawk create %AUTO%]
    $obj configure -database $databaseHandle
    $obj configure -ofs [dict get $options OFS]
    $obj configure -ors [dict get $options ORS]

    foreach file $fileOptions {
        $obj read-file $file
    }

    set error [catch { $obj perform-query $script } errorMessage errorOptions]
    if {$error} {
        # Ignore errors caused by stdout being closed during output (e.g., if
        # someone is piping the output to head(1)).
        if {[lrange [dict get $errorOptions -errorcode] 0 1] ne {POSIX EPIPE}} {
            return -options $errorOptions $errorMessage
        }
    }
    $obj destroy
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
