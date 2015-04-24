#!/usr/bin/env tclsh
# Sqawk
# Copyright (C) 2015 Danyil Bohdan
# License: MIT
package require Tcl 8.5
package require cmdline
package require snit 2
package require sqlite3
package require struct
package require textutil

namespace eval ::sqawk {
    variable version 0.4.0
}
namespace eval ::sqawk::script {
    variable debug 0
}

::snit::type ::sqawk::table {
    variable database

    option -database
    option -dbtable
    option -keyprefix
    option -fs
    option -rs
    option -maxnf

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
    variable tables

    option -database
    option -fsx
    option -rsx
    option -ofs { }
    option -ors {\n}
    option -maxnf 10

    method create-table tableName {
        set newTable [::sqawk::table create %AUTO%]
        $newTable configure -dbtable $tableName
        $newTable configure -keyprefix $tableName
        foreach key [list -database -maxnf] {
            $newTable configure $key [$self cget $key]
        }
        $newTable initialize
        dict set tables $tableName $newTable
    }

    method insert-data-from-channel {channel tableName FS RS} {
        [dict get $tables $tableName] insert-data-from-channel $channel $FS $RS
    }

    method output {data} {
        # Do not throw an error if stdout is closed during output (e.g., if
        # someone is piping the output to head(1)).
        catch {
            puts -nonewline $data
        }
    }

    # Perform query $query and print the result.
    method perform-query {query} {
        [$self cget -database] eval $query results {
            set output {}
            set keys $results(*)
            foreach key $keys {
                lappend output $results($key)
            }
            $self output [join $output [$self cget -ofs]][$self cget -ors]
        }
    }
}

proc ::sqawk::script::check-separator-list {sepList fileCount} {
    if {$fileCount != [llength $sepList]} {
        error "given [llength $sepList] separators for $fileCount files"
    }
}

proc ::sqawk::script::adjust-separators {key sep agrKey sepList default
        fileCount} {
    set keyPresent [expr {$sep ne ""}]
    set agrKeyPresent [expr {
        [llength $sepList] > 0
    }]

    if {$keyPresent && $agrKeyPresent} {
        error "cannot specify -$key and -$agrKey at the same time"
    }

    # Set key to its default value.
    if {!$keyPresent && !$agrKeyPresent} {
        set sep $default
        set keyPresent 1
    }

    # Set $agrKey to the value under $key.
    if {$keyPresent && !$agrKeyPresent} {
        set sepList [::struct::list repeat $fileCount $sep]
        set agrKeyPresent 1
    }

    # By now sepList has been set.

    ::sqawk::script::check-separator-list $sepList $fileCount
    return [list $sep $sepList]
}

# Process $argv into sqawker object options.
proc ::sqawk::script::process-options {argv} {
    variable version

    set defaultValues {
        FS {[ \t]+}
        RS {\n}
    }

    set options {
        {FS.arg {} "Input field separator (regexp)"}
        {RS.arg {} "Input record separator (regexp)"}
        {FSx.arg {}
                "Per-file input field separator list (regexp)"}
        {RSx.arg {}
                "Per-file input record separator list (regexp)"}
        {OFS.arg { } "Output field separator"}
        {ORS.arg {\n} "Output record separator"}
        {NF.arg 10 "Maximum NF value"}
        {v "Print version"}
        {1 "One field only. A shortcut for -FS '^$'"}
    }

    set usage "?options? script ?filename ...?"
    set cmdOptions [::cmdline::getoptions argv $options $usage]

    if {[dict get $cmdOptions v]} {
        puts $version
        exit 0
    }

    set script [lindex $argv 0]
    if {$script eq ""} {
        error "empty script"
    }
    set filenames [lrange $argv 1 end]
    set fileCount [llength $filenames]
    if {$fileCount == 0} {
        set fileCount 1
    }

    if {[dict get $cmdOptions 1]} {
        dict set cmdOptions FS ^$
    }


    # The logic for FS and RS default values and FS and RS determining FSx
    # and RSx if the latter two are not set.
    foreach key {FS RS} {
        set agrKey "${key}x"
        lassign [::sqawk::script::adjust-separators $key \
                        [dict get $cmdOptions $key] \
                        $agrKey \
                        [dict get $cmdOptions $agrKey] \
                        [dict get $defaultValues $key] \
                        $fileCount] \
                value \
                agrValue
        dict set cmdOptions $key $value
        dict set cmdOptions $agrKey $agrValue
    }

    # Substitute slashes. (In FS, RS, FSx and RSx the regexp engine will
    # do this for us.)
    foreach option {OFS ORS} {
        dict set cmdOptions $option [subst -nocommands -novariables \
                [dict get $cmdOptions $option]]
    }

    # Map command line option names to sqawker object option names.
    set objOptions {}
    set keyMap {
        FSx -fsx
        RSx -rsx
        OFS -ofs
        ORS -ors
        NF -maxnf
    }
    foreach {keyFrom keyTo} $keyMap {
        if {[dict exists $cmdOptions $keyFrom]} {
            dict set objOptions $keyTo [dict get $cmdOptions $keyFrom]
        }
    }

    return [list $objOptions $script $filenames]
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
                options script filenames
    } errorMessage]
    if {$error} {
        puts "error: $errorMessage"
        exit 1
    }

    if {$filenames eq ""} {
        set fileHandles stdin
    } else {
        set fileHandles [::struct::list mapfor x $filenames {open $x r}]
    }

    ::sqawk::script::create-database $databaseHandle
    set obj [::sqawk::sqawk create %AUTO%]
    $obj configure -database $databaseHandle
    $obj configure {*}$options

    set tableNames [split {abcdefghijklmnopqrstuvwxyz} ""]
    set tableNamesLength [llength $tableNames]
    set i 1
    foreach fileHandle $fileHandles \
            FS [dict get $options -fsx] \
            RS [dict get $options -rsx] {
        if {$i > $tableNamesLength} {
            puts "too many files given ($i);\
                    can import up to $tableNamesLength"
            exit 1
        }
        set tableName [lindex $tableNames [expr {$i - 1}]]
        $obj create-table $tableName
        $obj insert-data-from-channel $fileHandle $tableName $FS $RS
        incr i
    }
    $obj perform-query $script
    $obj destroy
}

# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    ::sqawk::script::main $argv0 $argv
}
