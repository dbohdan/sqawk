#!/usr/bin/env tclsh
# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

package require tcltest

namespace eval ::sqawk::tests {
    variable path [file dirname [file dirname [file normalize $argv0/___]]]
    variable setup [list apply {{path} {
        cd $path
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

    tcltest::test test2 {Fail on bad query or missing file} \
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

    tcltest::test test3 {JOIN on two files from examples/hp/} \
            -constraints unix \
            -setup $setup \
            -body {

        close [file tempfile filename]
        exec tclsh sqawk.tcl {
            select a1, b1, a2 from a inner join b on a2 = b2
            where b1 < 10000 order by b1
        } examples/hp/MD5SUMS examples/hp/du-bytes > $filename
        set result [exec diff examples/hp/results.correct $filename]
        file delete $filename
        return $result
    } -result {}

    tcltest::test test3 {JOIN on files from examples/three-files/, FS setting} \
            -constraints unix \
            -setup $setup \
            -body {
        set dir examples/three-files/
        close [file tempfile filename]
        exec tclsh sqawk.tcl -FS , {
            select a1, a2, b2, c2 from a inner join b on a1 = b1
            inner join c on a1 = c1
        } $dir/1 FS=, $dir/2 FS=_ FS=, $dir/3 > $filename
        unset dir
        set result [exec diff examples/three-files/results.correct $filename]
        file delete $filename
        return $result
    } -result {}

    # Exit with a nonzero status if there are failed tests.
    if {$::tcltest::numTests(Failed) > 0} {
        exit 1
    }
}
