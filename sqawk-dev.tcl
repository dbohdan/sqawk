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
    variable version 0.16.1
}

# The following comment is used by Assemble when bundling Sqawk's source code in
# a single file. Do not remove it.
#define SQAWK
interp alias {} ::source+ {} ::source
source+ lib/tabulate.tcl
source+ lib/utils.tcl
source+ lib/parsers/awk.tcl
source+ lib/parsers/csv.tcl
source+ lib/serializers/awk.tcl
source+ lib/serializers/csv.tcl
source+ lib/serializers/json.tcl
source+ lib/serializers/table.tcl
source+ lib/serializers/tcl.tcl
source+ lib/classes/sqawk.tcl
source+ lib/classes/table.tcl

namespace eval ::sqawk::script {
    variable debug 0
    variable profile 0
    if {$profile} {
        package require profiler
        ::profiler::init
    }
}

# Process $argv into a list of per-file options.
proc ::sqawk::script::process-options {argv} {
    set options {
        {FS.arg {[ \t]+} "Input field separator for all files (regexp)"}
        {RS.arg {\n} "Input record separator for all files (regexp)"}
        {OFS.arg { } "Output field separator"}
        {ORS.arg {\n} "Output record separator"}
        {NF.arg 10 "Maximum NF value for all files"}
        {MNF.arg {expand} "NF mode (expand, normal or crop)"}
        {output.arg {awk} "Output format"}
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
    set globalOptions [::sqawk::filter-keys $cmdOptions { OFS ORS output }]

    # Filenames and individual file settings.
    set fileCount 0
    set fileOptionsForAllFiles {}
    set defaultFileOptions [::sqawk::filter-keys $cmdOptions {
        FS RS NF MNF
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
            -ors [dict get $options ORS] \
            -outputformat [dict get $options output]

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
