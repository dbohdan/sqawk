#!/usr/bin/env tclsh
# SQLAwk
# Copyright (C) 2015 Danyil Bohdan
# License: MIT
package require Tcl 8.5
package require cmdline
package require struct
package require textutil
package require sqlite3

namespace eval sqlawk {
    variable version 0.2.1

    proc create-database {database} {
        file delete /tmp/sqlawk.db
        ::sqlite3 $database /tmp/sqlawk.db
    }

    proc create-table {database table maxNR} {
        set query {
            CREATE TABLE %s(
                nr INTEGER PRIMARY KEY,
                nf INTEGER,
                %s
            )
        }
        set fields {}
        for {set i 0} {$i <= $maxNR} {incr i} {
            lappend fields "f$i INTEGER"
        }
        $database eval [format $query $table [join $fields ","]]
    }

    proc read-data {fileHandle database table FS RS} {
        set insertQuery {
            INSERT INTO %s (%s) VALUES (%s)
        }

        foreach f0 [split [read $fileHandle] $RS] {
            set fields [::textutil::splitx $f0 $FS]
            set insertColumnNames {nf,f0}
            set insertValues {$nf,$f0}
            set nf [llength $fields]
            set i 1
            foreach field $fields {
                set f$i $field
                lappend insertColumnNames "f$i"
                lappend insertValues "\$f$i"
                incr i
            }
            $database eval [format $insertQuery \
                    $table \
                    [join $insertColumnNames ,] \
                    [join $insertValues ,]]
        }
    }

    proc perform-query {database query OFS ORS} {
        $database eval $query results {
            set output {}
            set keys $results(*)
            foreach key $keys {
                lappend output $results($key)
            }
            puts -nonewline [join $output $OFS]$ORS
        }
    }

    proc process-options {argv} {
        variable version

        set options {
            {FS.arg "[ \t]+" "Input field separator (regexp)"}
            {RS.arg "\n" "Input record separator"}
            {OFS.arg " " "Output field separator"}
            {ORS.arg "\n" "Output record separator"}
            {table.arg {t%s} "Table name template"}
            {NR.arg 10 "Maximum NR value"}
            {v "Print version"}
            {1 "One field only. A shortcut for -FS '^$'"}
        }
        set usage "script ?options? ?filename ...?"
        set cmdOptions [::cmdline::getoptions argv $options $usage]

        if {[dict get $cmdOptions v]} {
            puts $version
            exit 0
        }
        if {[dict get $cmdOptions 1]} {
            dict set cmdOptions FS '^$'
        }

        return [list $cmdOptions $argv]
    }

    proc main {argv {databaseHandle db}} {
        set error [catch {
            lassign [process-options $argv] settings argv
        } errorMessage]
        if {$error} {
            puts $errorMessage
            exit 1
        }

        set script [lindex $argv 0]
        set filenames [lrange $argv 1 end]

        if {$filenames eq ""} {
            set fileHandles stdin
        } else {
            set fileHandles [::struct::list mapfor x $filenames {open $x r}]
        }

        create-database $databaseHandle

        set i 1
        foreach fileHandle $fileHandles {
            set tableName [format [dict get $settings table] $i]
            create-table $databaseHandle $tableName [dict get $settings NR]
            read-data $fileHandle \
                    $databaseHandle $tableName \
                    [dict get $settings FS] \
                    [dict get $$settings RS]
            incr i
        }
        perform-query $databaseHandle \
                $script \
                [dict get $settings OFS] \
                [dict get $settings ORS]
    }
}

::sqlawk::main $argv
