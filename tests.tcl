#!/usr/bin/env tclsh
# Sqawk
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

package require tcltest

namespace eval ::sqawk::tests {
    variable path [file dirname [file dirname [file normalize $argv0/___]]]
    variable setup [list apply {{path} {
        cd $path
        source [file join $path sqawk.tcl]
    }} $path]

    tcltest::test test1 {Handle broken pipe} \
            -constraints unix \
            -setup $setup \
            -body {
        set ch [file tempfile filename]
        puts $ch "line 1\nline 2\nline 3"
        close $ch
        set result \
                [exec tclsh sqawk.tcl {select a0 from a} $filename | head -n 1]
        file delete $filename
        return $result
    } -result {line 1}

    tcltest::test test2 {Fail on bad query} \
            -setup $setup \
            -body {
        set result {}
        # Bad query.
        lappend result [catch {
            exec tclsh sqawk.tcl -1 asdf sqawk.tcl
        }]
        # Missing file.
        lappend result [catch {
            exec tclsh sqawk.tcl -1 {select a0 from a} missing-file
        }]
        return $result
    } -result {1 1}

    # Exit with a nonzero status if there are failed tests.
    if {$::tcltest::numTests(Failed) > 0} {
        exit 1
    }
}
