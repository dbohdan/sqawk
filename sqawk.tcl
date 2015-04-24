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
}

::snit::type ::sqawk::table {
    option -database
    option -dbtable
    option -keyprefix
    option -maxnf

    destructor {
        [$self cget -database] eval "DROP TABLE [$self cget -dbtable]"
    }

    # Create DB tables.
    method initialize {} {
        set fields {}
        set keyPrefix [$self cget -keyprefix]
        set command {
            CREATE TABLE [$self cget -dbtable] (
                ${keyPrefix}nr INTEGER PRIMARY KEY,
                ${keyPrefix}nf INTEGER,
                [join $fields ","]
            )
        }
        set maxNF [$self cget -maxnf]
        for {set i 0} {$i <= $maxNF} {incr i} {
            lappend fields "$keyPrefix$i INTEGER"
        }
        [$self cget -database] eval [subst $command]
    }

    # Read data from $channel.
    method insert-data-from-channel {channel FS RS} {
        set keyPrefix [$self cget -keyprefix]
        set records [::textutil::splitx [read $channel] $RS]
        if {[lindex $records end] eq ""} {
            set records [lrange $records 0 end-1]
        }

        set insertCommand {
            INSERT INTO [$self cget -dbtable] ([join $insertColumnNames ","])
            VALUES ([join $insertValues ,])
        }
        foreach record $records {
            set fields [::textutil::splitx $record $FS]
            set insertColumnNames "${keyPrefix}nf,${keyPrefix}0"
            set insertValues  {$nf,$record}
            set nf [llength $fields]
            set i 1
            foreach field $fields {
                set $keyPrefix$i $field
                lappend insertColumnNames "$keyPrefix$i"
                lappend insertValues "\$$keyPrefix$i"
                incr i
            }
            [$self cget -database] eval [subst $insertCommand]
        }
    }
}

::snit::type ::sqawk::sqawk {
    variable tables {}
    variable defaultTableNames [split {abcdefghijklmnopqrstuvwxyz} ""]

    option -database
    option -ofs { }
    option -ors {\n}

    destructor {
        foreach {_ tableObj} $tables {
            $tableObj destroy
        }
    }

    # Read data from the file specified in the dictionary $fileData into a new
    # database table.
    method read-file fileData {
        set tableName [lindex $defaultTableNames [dict size $tables]]
        set newTable [::sqawk::table create %AUTO%]
        $newTable configure -database [$self cget -database]
        $newTable configure -dbtable $tableName
        $newTable configure -keyprefix $tableName
        $newTable configure -maxnf [dict get $fileData NF]
        $newTable initialize
        set filename [dict get $fileData filename]
        if {$filename eq "-"} {
            set ch stdin
        } else {
            set ch [open $filename]
        }
        $newTable insert-data-from-channel \
                $ch \
                [dict get $fileData FS] \
                [dict get $fileData RS]
        close $ch
        dict set tables $tableName $newTable
        return $newTable
    }

    # Perform query $query and output the result to $channel.
    method perform-query {query {channel stdout}} {
        # For each row returned...
        [$self cget -database] eval $query results {
            set output {}
            set keys $results(*)
            foreach key $keys {
                lappend output $results($key)
            }
            set outputRecord [join $output [$self cget -ofs]][$self cget -ors]
            puts -nonewline $channel $outputRecord
        }
    }
}

# Remove and return $n elements from the list stored in the variable $varName.
proc ::sqawk::script::lshift! {varName {n 1}} {
    upvar 1 $varName list
    set result [lrange $list 0 $n-1]
    set list [lrange $list $n end]
    return $result
}

# Return a subdictionary of $dictionary with only the keys in $keyList.
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

# Process $argv into per-file options.
proc ::sqawk::script::process-options {argv} {
    set options {
        {FS.arg {[ \t]+} "Input field separator for all files (regexp)"}
        {RS.arg {\n} "Input record separator for all files (regexp)"}
        {OFS.arg { } "Output field separator"}
        {ORS.arg {\n} "Output record separator"}
        {NF.arg 10 "Maximum NF value"}
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

    lassign [lshift! argv] script
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

    # Global settings.
    set globalOptions [::sqawk::script::filter-keys $cmdOptions { OFS ORS }]

    # File settings.
    set fileCount 0
    set usedStdin 0
    set fileSettings {}
    set defaultFileSettings [::sqawk::script::filter-keys $cmdOptions {
        FS RS NF
    }]
    set currentFileSettings $defaultFileSettings
    while {[llength $argv] > 0} {
        lassign [lshift! argv] elem
        # setting=value
        if {[regexp {([^=]+)=(.*)} $elem _ key value]} {
            dict set currentFileSettings $key $value
        } else {
            # Filename.
            if {[file exists $elem] || ($elem eq "-")} {
                dict set currentFileSettings filename $elem
                lappend fileSettings $currentFileSettings
                set currentFileSettings $defaultFileSettings
                incr fileCount
            } else {
                error "can't find file \"$elem\""
            }
        }
    }
    # If not files are given add "-" (standard input) with the current settings
    # to fileSettings.
    if {$fileCount == 0} {
        dict set currentFileSettings filename -
        lappend fileSettings $currentFileSettings
    }

    return [list $script $globalOptions $fileSettings]
}

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
    set error [catch {
        lassign [::sqawk::script::process-options $argv] \
                script options fileSettings
    } errorMessage]
    if {$error} {
        puts "error: $errorMessage"
        exit 1
    }

    ::sqawk::script::create-database $databaseHandle
    set obj [::sqawk::sqawk create %AUTO%]
    $obj configure -database $databaseHandle
    $obj configure -ofs [dict get $options OFS]
    $obj configure -ors [dict get $options ORS]

    foreach file $fileSettings {
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
}
