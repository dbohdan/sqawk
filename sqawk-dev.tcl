#! /usr/bin/env tclsh
# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018, 2020 D. Bohdan
# License: MIT

package require Tcl 8.6
package require cmdline
package require snit 2
package require sqlite3

namespace eval ::sqawk {
    variable version 0.23.0
}

# The following comment is used by Assemble when bundling Sqawk's source code in
# a single file. Do not remove it.
#define SQAWK
interp alias {} ::source+ {} ::source
source+ lib/tabulate.tcl
source+ lib/utils.tcl
source+ lib/parsers/awk.tcl
source+ lib/parsers/csv.tcl
source+ lib/parsers/json.tcl
source+ lib/parsers/tcl.tcl
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
proc ::sqawk::script::process-options argv {
    set options {
        {FS.arg {[ \t]+} "Input field separator for all files (regexp)"}
        {RS.arg {\n} "Input record separator for all files (regexp)"}
        {OFS.arg { } "Output field separator"}
        {ORS.arg {\n} "Output record separator"}
        {NF.arg 10 "Maximum NF value for all files"}
        {MNF.arg {expand} "NF mode (expand, normal or crop)"}
        {dbfile.arg {:memory:} "The SQLite3 database file to create"}
        {noinput "Do not read from stdin when no filenames are given"}
        {output.arg {awk} "Output format"}
        {v "Print version"}
        {1 "One field only. A shortcut for -FS 'x^'"}
    }

    set usage {[options] script [[setting=value ...] filename ...]}
    # ::cmdline::getoptions exits with a nonzero status if it sees a help flag.
    # We catch its help flags (plus {--help}) early to prevents this.
    if {$argv in {{} -h -help --help -? /?}} {
        puts stderr [::cmdline::usage $options $usage]
        exit [expr {$argv eq {} ? 1 : 0}]
    }

    try {
        ::cmdline::getoptions argv $options $usage
    } on error err {
        puts stderr $err
        exit 1
    } on ok cmdOptions {}

    # Report version.
    if {[dict get $cmdOptions v]} {
        puts stderr $::sqawk::version
        exit 0
    }

    set argv [lassign $argv script]

    if {[dict get $cmdOptions 1]} {
        dict set cmdOptions FS x^
    }

    # Substitute slashes.  (In FS and RS the regexp engine will do this for
    # us.)
    foreach option {OFS ORS} {
        dict set cmdOptions $option [subst \
            -nocommands \
            -novariables \
            [dict get $cmdOptions $option] \
        ]
    }

    # Settings that affect the program in general and Sqawk object itself.
    set globalOptions [::sqawk::filter-keys $cmdOptions {
        dbfile noinput OFS ORS output
    }]

    # Filenames and individual file settings.
    set fileOptions [process-file-options \
        $cmdOptions \
        $globalOptions \
        $argv \
    ]

    return [list $script $globalOptions $fileOptions]
}

proc ::sqawk::script::process-file-options {cmdOptions globalOptions argv} {
    set awkKeys { FS RS }
    set defaultKeys { NF MNF }
    set universalKeys { columns datatypes F0 header prefix table }

    set default [::sqawk::filter-keys $cmdOptions $defaultKeys]

    set all {}
    set current $default

    while {[llength $argv] > 0} {
        set argv [lassign $argv elem]

        # setting=value
        if {[regexp {([^=]+)=(.*)} $elem _ key value]} {
            dict set current $key $value
        } else {
            # Filename.
            if {[file exists $elem] || $elem eq "-"} {
                dict set current filename $elem
                lappend all $current
                set current $default
            } else {
                error [list can't find file $elem]
            }
        }
    }

    # If no files are given add "-" (standard input) with the current settings
    # to all.
    if {[llength $all] == 0 && ![dict get $globalOptions noinput]} {
        dict set current filename -
        lappend all $current
    }

    # Verify the file options and add in the "awk" parser defaults.
    set awkDefault [::sqawk::filter-keys $cmdOptions $awkKeys]
    set validFormats {}
    foreach ns [namespace children ::sqawk::parsers] {
        foreach format [set ${ns}::formats] {
            dict set validFormats $format $ns
        }
    }

    set all [lmap current $all {
        set format awk
        if {[dict exists $current format]} {
            set format [dict get $current format]
            if {![dict exists $validFormats $format]} {
                error [list unknown input format: $format]
            }
        }

        if {$format eq {awk}} {
            set current [dict merge $awkDefault $current]
        }

        set ns [dict get $validFormats $format]
        set parserKeys [dict keys [set ${ns}::options]]
        dict for {key value} $current {
            if {$key in {filename format}} continue
            if {$key ni $parserKeys
                && $key ni $universalKeys
                && $key ni $defaultKeys
                && !($format eq {awk} && $key in $awkKeys)} {
                error [list bad option $key for format $format]
            }
        }

        set current
    }]

    return $all
}

# Create an SQLite3 database for ::sqawk::sqawk to use.
proc ::sqawk::script::create-database {database file} {
    variable debug
    if {$debug} {
        ::sqlite3 $database.real $file
        proc ::$database args {
            set me [dict get [info frame 0] proc]
            puts "DEBUG: $me $args"
            return [uplevel 1 [list $me.real {*}$args]]
        }
    } else {
        ::sqlite3 $database $file
    }

    foreach {name script} {
        dict_exists       ::sqawk::dict-exists
        dict_get          ::sqawk::dict-get
        lindex            ::lindex
        llength           ::llength
        lrange            ::lrange
        regexp            ::regexp
        regsub            ::regsub
    } {
        # Compatibility.
        try {
            $database function $name -deterministic $script
        } on error {} {
            $database function $name $script
        }
    }
}

proc ::sqawk::script::main {argv0 argv {databaseHandle db}} {
    # Try to process the command line options.
    try {
        lassign [::sqawk::script::process-options $argv] \
                script options allFileOptions
    } on error errorMessage {
        puts stderr "error: $errorMessage"
        exit 1
    }

    # Initialize Sqawk and the corresponding database.
    set dbfile [dict get $options dbfile]
    ::sqawk::script::create-database $databaseHandle $dbfile
    set sqawkObj [::sqawk::sqawk create %AUTO%]
    $sqawkObj configure \
            -database $databaseHandle \
            -destroytables [expr {$dbfile eq {:memory}}] \
            -ofs [dict get $options OFS] \
            -ors [dict get $options ORS] \
            -outputformat [dict get $options output]

    foreach file $allFileOptions {
        $sqawkObj read-file $file
    }

    try {
        $sqawkObj eval $script
    } trap {POSIX EPIPE} {} {}
    $sqawkObj destroy
    $databaseHandle close
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
