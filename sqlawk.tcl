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
    variable version 0.3.0

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

        set records [::textutil::splitx [read $fileHandle] $RS]
        if {[lindex $records end] eq ""} {
            set records [lrange $records 0 end-1]
        }

        foreach f0 $records {
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
            #parray results
            foreach key $keys {
                lappend output $results($key)
            }
            puts -nonewline [join $output $OFS]$ORS
        }
    }

    proc process-options {argv} {
        variable version

        set defaultFS {[ \t]+}
        set defaultRS {\n}

        set options [string map \
                [list %defaultFS $defaultFS %defaultRS $defaultRS] {
            {FS.arg {%defaultFS} "Input field separator (regexp)"}
            {RS.arg {%defaultRS} "Input record separator (regexp)"}
            {FSx.arg {{%defaultFS}}
                    "Per-file input field separator list (regexp)"}
            {RSx.arg {{%defaultRS}}
                    "Per-file input record separator list (regexp)"}
            {OFS.arg { } "Output field separator"}
            {ORS.arg {\n} "Output record separator"}
            {NR.arg 10 "Maximum NR value"}
            {table.arg {t%s} "Table name template"}
            {v "Print version"}
            {1 "One field only. A shortcut for -FS '^$'"}
        }]
        set usage "?options? query ?filename ...?"
        set cmdOptions [::cmdline::getoptions argv $options $usage]

        if {[dict get $cmdOptions v]} {
            puts $version
            exit 0
        }
        if {[dict get $cmdOptions 1]} {
            dict set cmdOptions FS '^$'
        }
        if {[dict get $cmdOptions FS] ne $defaultFS} {
            dict set cmdOptions FSx [list [dict get $cmdOptions FS]]
        }
        if {[dict get $cmdOptions RS] ne $defaultRS} {
            dict set cmdOptions RSx [list [dict get $cmdOptions RS]]
        }

        # Substitute slashes. (In FS, RS, FSx and RSx the regexp engine will
        # do this for us.)
        foreach option {OFS ORS} {
            dict set cmdOptions $option [subst -nocommands -novariables \
                    [dict get $cmdOptions $option]]
        }

        set query [lindex $argv 0]
        set filenames [lrange $argv 1 end]

        return [list $cmdOptions $query $filenames]
    }

    proc main {argv {databaseHandle db}} {
        set error [catch {
            lassign [process-options $argv] settings script filenames
        } errorMessage]
        if {$error} {
            puts $errorMessage
            exit 1
        }

        if {$filenames eq ""} {
            set fileHandles stdin
        } else {
            set fileHandles [::struct::list mapfor x $filenames {open $x r}]
        }

        create-database $databaseHandle

        set i 1
        foreach fileHandle $fileHandles \
                FS [dict get $settings FSx] \
                RS [dict get $settings RSx] {
            puts [list  $FS $RS]
            set tableName [format [dict get $settings table] $i]
            create-table $databaseHandle $tableName [dict get $settings NR]
            read-data $fileHandle $databaseHandle $tableName $FS $RS
            incr i
        }
        perform-query $databaseHandle \
                $script \
                [dict get $settings OFS] \
                [dict get $settings ORS]
    }
}

::sqlawk::main $argv
