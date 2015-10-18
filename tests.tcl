#!/usr/bin/env tclsh
# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

package require tcltest
package require fileutil

namespace eval ::sqawk::tests {
    variable path [file dirname [file dirname [file normalize $argv0/___]]]
    variable setup [list apply {{path} {
        cd $path
    }} $path]

    # Create and open temporary files (read/write), run a script then close and
    # delete the files. $args is a list of the format {fnVarName1 chVarName1
    # fnVarName2 chVarName2 ... script}.
    proc with-temp-files args {
        set files {}
        set channels {}

        set script [lindex $args end]
        foreach {fnVarName chVarName} [lrange $args 0 end-1] {
            set filename [::fileutil::tempfile]
            uplevel 1 [list set $fnVarName $filename]
            lappend files $filename
            if {$chVarName ne ""} {
                set channel [open $filename w+]
                uplevel 1 [list set $chVarName $channel]
                lappend channels $channel
            }
        }
        set res [catch {uplevel 1 $script} ret retopt]

        foreach channel $channels {
            catch { close $channel }
        }
        foreach filename $files {
            file delete $filename
        }

        return {*}$retopt $ret
    }

    proc sqawk-tcl args {
        exec [info nameofexecutable] sqawk.tcl {*}$args
    }

    tcltest::test test1 {Handle broken pipe, read from stdin} \
            -constraints unix \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "line 1\nline 2\nline 3"
            close $ch
            set result [sqawk-tcl {select a0 from a} < $filename | head -n 1]
        }
        return $result
    } -result {line 1}

    tcltest::test test2 {Fail on bad query or missing file} \
            -setup $setup \
            -body {
        set result {}
        # Bad query.
        lappend result [catch {
            sqawk-tcl -1 asdf sqawk-tcl
        }]
        # Missing file.
        lappend result [catch {
            sqawk-tcl -1 {select a0 from a} missing-file
        }]
        return $result
    } -result {1 1}

    tcltest::test test3 {JOIN on two files from examples/hp/} \
            -constraints unix \
            -setup $setup \
            -body {
        with-temp-files filename {
            sqawk-tcl {
                select a1, b1, a2 from a inner join b on a2 = b2
                where b1 < 10000 order by b1
            } examples/hp/MD5SUMS examples/hp/du-bytes > $filename

            set result [exec diff examples/hp/results.correct $filename]
        }
        return $result
    } -result {}

    tcltest::test test4 {JOIN on files from examples/three-files/, FS setting} \
            -constraints unix \
            -setup $setup \
            -body {
        with-temp-files filename {
            set dir examples/three-files/
            sqawk-tcl -FS , {
                select a1, a2, b2, c2 from a inner join b on a1 = b1
                inner join c on a1 = c1
            } $dir/1 FS=_ FS=, $dir/2 $dir/3 > $filename
            unset dir
            set result \
                    [exec diff examples/three-files/results.correct $filename]
        }
        return $result
    } -result {}

    tcltest::test test5 {Custom table names} \
            -setup $setup \
            -body {
        with-temp-files filename1 ch1 {
            with-temp-files filename2 ch2 {
                puts $ch1 "foo 1\nfoo 2\nfoo 3"
                puts $ch2 "bar 4\nbar 5\nbar 6"
                close $ch1
                close $ch2
                set result [sqawk-tcl {
                    select foo2 from foo; select b2 from b
                } table=foo $filename1 $filename2]
            }
        }
        return $result
    } -result "1\n2\n3\n4\n5\n6"

    tcltest::test test6 {Custom table names and prefixes} \
            -setup $setup \
            -body {
        with-temp-files filename1 ch1 filename2 ch2 {
            puts $ch1 "foo 1\nfoo 2\nfoo 3"
            puts $ch2 "bar 4\nbar 5\nbar 6"
            close $ch1
            close $ch2
            set result [sqawk-tcl {
                select foo.x2 from foo; select baz2 from bar
            } table=foo prefix=x $filename1 table=bar prefix=baz $filename2]
        }
        return $result
    } -result "1\n2\n3\n4\n5\n6"

    tcltest::test test7 {Header row} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "name\tposition\toffice\tphone"
            puts $ch "Smith\tCEO\t10\t555-1234"
            puts $ch "James\tHead of marketing\t11\t555-1235"
            puts $ch "McDonald\tDeveloper\t12\t555-1236\tGood at tables"
            close $ch
            set result [sqawk-tcl {
                select name, office from staff
                where position = "CEO"
                        or staff.phone = "555-1234"
                        or staff.a5 = "Good at tables"
            } FS=\t table=staff prefix=a header=1 $filename]
        }
        return $result
    } -result "Smith 10\nMcDonald 12"

    tcltest::test test8 {::sqawk::parsers::awk::splitmerge} \
            -setup $setup \
            -body {
        source sqawk.tcl
        set result {}
        set lambda {
            {from to {sep AB}} {
                set startingList [list start u v w x y z tail]
                set result {}
                lappend result [lrange $startingList 0 $from-1]
                lappend result [join [lrange $startingList $from $to] $sep]
                lappend result [lrange $startingList $to+1 end]
                return [string trim [join $result { }] { }]
            }
        }
        for {set i 0} {$i < 20} {incr i} {
            for {set j 0} {$j <= $i} {incr j} {
                set literalSplit [::sqawk::parsers::awk::splitmerge \
                        startABuABvABwABxAByABzABtail {AB} [list $j $i]]
                set regexpSplit [::sqawk::parsers::awk::splitmerge \
                        startABuABvABwABxAByABzABtail {(AB?)+} [list $j $i]]
                set correct [apply $lambda $j $i]
                set match [expr {
                    ($literalSplit eq $correct) && ($regexpSplit eq $correct)
                }]
                lappend result $match
            }
        }

        return [lsort -unique $result]
    } -result 1

    tcltest::test test9 {merge option} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            set result {}
            puts $ch "foo 1   foo 2   foo 3"
            puts $ch "bar    4 bar    5 bar    6"
            close $ch
            lappend result [sqawk-tcl -OFS - {
                select a1, a2, a3 from a
            } {merge=0-1,2-3,4-5} $filename]
            lappend result [sqawk-tcl -OFS - {
                select a1, a2, a3 from a
            } {merge=0 1 2 3 4 5} $filename]
        }
        return [lindex [lsort -unique $result] 0]
    } -result "foo 1-foo 2-foo 3\nbar    4-bar    5-bar    6"

    tcltest::test test10 {CSV input} \
            -setup $setup \
            -body {
        with-temp-files filename1 ch1 filename2 ch2 {
            set result {}
            puts $ch1 "1,2,\"Hello, World!\"\nΑλαμπουρνέζικα,3,4\n5,6,7"
            close $ch1
            puts $ch2 "1;2;\"Hello, World!\"\nΑλαμπουρνέζικα;3;4\n5;6;7"
            close $ch2
            lappend result [sqawk-tcl -OFS - {
                select a1, a2, a3 from a
            } format=csv $filename1]
            lappend result [sqawk-tcl -OFS - {
                select a1, a2, a3 from a
            } format=csvalt {csvsep=;} $filename2]
        }
        return [lindex [lsort -unique $result] 0]
    } -result "1-2-Hello, World!\nΑλαμπουρνέζικα-3-4\n5-6-7"

    tcltest::test test11 {Default output format} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "line 1\nline 2\nline 3"
            close $ch
            set result [sqawk-tcl -output awk {select a0 from a} $filename]
        }
        return $result
    } -result "line 1\nline 2\nline 3"

    tcltest::test test12 {Verbatim reproduction of input in a0} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "test:\n\ttclsh tests.tcl\n\"\{"
            close $ch
            set result [sqawk-tcl {select a0 from a} $filename]
        }
        return $result
    } -result "test:\n\ttclsh tests.tcl\n\"\{"

    tcltest::test test13 {Empty lines} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "\n\n\n"
            close $ch
            set result {}
            lappend result [sqawk-tcl {select a1 from a} $filename]
            lappend result [sqawk-tcl {select a1 from a} format=csv $filename]
        }
        return $result
    } -result [list "\n\n\n" "\n\n\n"]

    tcltest::test test14 {CSV output} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "a,b\n1,2"
            close $ch
            set result {}
            lappend result [sqawk-tcl -output awk {select a1 from a} $filename]
            lappend result [sqawk-tcl -output csv {select a1 from a} $filename]
        }
        return $result
    } -result [list "a,b\n1,2" "\"a,b\"\n\"1,2\""]

    tcltest::test test15 {Tcl output} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "1\t2\tHello, World!\t "
            close $ch
            set result {}
            lappend result [sqawk-tcl \
                    -FS \t \
                    -output tcl \
                    {select a1,a2,a3,a4 from a} $filename]
            lappend result [sqawk-tcl \
                    -FS \t \
                    -output tcl,dicts=1 \
                    {select a1,a2,a3,a4 from a} $filename]
        }
        return $result
    } -result [list {{1 2 {Hello, World!} { }}} \
            {{a1 1 a2 2 a3 {Hello, World!} a4 { }}}]

    tcltest::test test16 {Table output} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "a,b,c\nd,e,f\ng,h,i"
            close $ch
            set result [sqawk-tcl \
                    -FS , -output table {select a1,a2,a3 from a} $filename]
        }
        return $result
    } -result ┌─┬─┬─┐\n│a│b│c│\n├─┼─┼─┤\n│d│e│f│\n├─┼─┼─┤\n│g│h│i│\n└─┴─┴─┘

    tcltest::test test17 {trim option} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            set result {}
            puts $ch {   a  }
            close $ch
            lappend result [sqawk-tcl {select a1 from a} $filename]
            lappend result [sqawk-tcl {select a1 from a} trim=left $filename]
            lappend result [sqawk-tcl {select a1 from a} trim=both $filename]
        }
        return $result
    } -result {{} a a}

    tcltest::test test18 {JSON output} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "a,b,c\nd,e,f\ng,h,i"
            close $ch
            set result {}
            lappend result [sqawk-tcl \
                    -FS , \
                    -output json \
                    {select a1,a2,a3 from a} $filename]
            lappend result [sqawk-tcl \
                    -FS , \
                    -output json,arrays=1 \
                    {select a1,a2,a3 from a} $filename]
        }
        return $result
    } -result [list \
            [format {[%s,%s,%s]} \
                    {{"a1":"a","a2":"b","a3":"c"}} \
                    {{"a1":"d","a2":"e","a3":"f"}} \
                    {{"a1":"g","a2":"h","a3":"i"}}] \
            {[["a","b","c"],["d","e","f"],["g","h","i"]]}]


    tcltest::test test19 {Datatypes} \
            -setup $setup \
            -body {
        with-temp-files filename ch {
            puts $ch "001 a\n002 b\nc"
            close $ch
            set result {}
            lappend result [sqawk-tcl \
                    {select a1,a2 from a} $filename]
            lappend result [sqawk-tcl \
                    {select printf("%03d",a1),a2 from a} $filename]
            lappend result [sqawk-tcl \
                    {select a1,a2 from a} datatypes=real,text $filename]
            lappend result [sqawk-tcl \
                    {select a1,a2 from a} datatypes=null,blob $filename]
            lappend result [sqawk-tcl \
                    {select a1,a2 from a} datatypes=text,text $filename]
        }
        return $result
    } -result [list \
            "1 a\n2 b\nc " \
            "001 a\n002 b\n000 " \
            "1.0 a\n2.0 b\nc " \
            "001 a\n002 b\nc " \
            "001 a\n002 b\nc "]


    tcltest::test test-nf-1-crop {NF mode crop} \
            -setup $setup \
            -body {
        set result {}
        with-temp-files filename ch {
            puts $ch "A B"
            puts $ch "A B C"
            puts $ch "A B C D"
            close $ch
            foreach nf {0 1 2 3} {
                lappend result [sqawk-tcl \
                    -FS " " \
                    -NF $nf \
                    -MNF crop \
                    -output tcl \
                    {select * from a} $filename]
            }
        }
        return [join $result \n]
    } -result [join {
        {{1 1 {A B}} {2 1 {A B C}} {3 1 {A B C D}}}
        {{1 2 {A B} A} {2 2 {A B C} A} {3 2 {A B C D} A}}
        {{1 3 {A B} A B} {2 3 {A B C} A B} {3 3 {A B C D} A B}}
        {{1 3 {A B} A B {}} {2 4 {A B C} A B C} {3 4 {A B C D} A B C}}
    } \n]

    tcltest::test test-nf-2-crop {NF mode expand} \
            -setup $setup \
            -body {
        set result {}
        with-temp-files filename ch {
            puts $ch "A B C D"
            puts $ch "A B C"
            puts $ch "A B"
            close $ch
            foreach nf {2 3 4} {
                lappend result [sqawk-tcl \
                    -FS " " \
                    -NF $nf \
                    -MNF crop \
                    -output tcl \
                    {select * from a} $filename]
            }
        }
        return [join $result \n]
    } -result [join {
        {{1 3 {A B C D} A B} {2 3 {A B C} A B} {3 3 {A B} A B}}
        {{1 4 {A B C D} A B C} {2 4 {A B C} A B C} {3 3 {A B} A B {}}}
        {{1 5 {A B C D} A B C D} {2 4 {A B C} A B C {}} {3 3 {A B} A B {} {}}}
    } \n]

    tcltest::test test-nf-3-expand {NF mode expand} \
            -setup $setup \
            -body {
        set result {}
        with-temp-files filename ch {
            puts $ch "A B"
            puts $ch "A B C"
            puts $ch "A B C D"
            close $ch
            foreach nf {0 1 2 3} {
                lappend result [sqawk-tcl \
                    -FS " " \
                    -NF $nf \
                    -MNF expand \
                    -output tcl \
                    {select * from a} $filename]
            }
        }
        return [join $result \n]
    } -result [join {
        {{1 3 {A B} A B {} {}} {2 4 {A B C} A B C {}} {3 5 {A B C D} A B C D}}
        {{1 3 {A B} A B {} {}} {2 4 {A B C} A B C {}} {3 5 {A B C D} A B C D}}
        {{1 3 {A B} A B {} {}} {2 4 {A B C} A B C {}} {3 5 {A B C D} A B C D}}
        {{1 3 {A B} A B {} {}} {2 4 {A B C} A B C {}} {3 5 {A B C D} A B C D}}
    } \n]

    tcltest::test test-nf-4-normal {NF mode normal} \
            -setup $setup \
            -body {
        set result [catch {with-temp-files filename ch {
            puts $ch "A B"
            puts $ch "A B C"
            close $ch
            sqawk-tcl \
                -FS " " \
                -NF 2 \
                -MNF normal \
                -output tcl \
                {select * from a} $filename
        }} msg]
    } -result 1

    # Exit with a nonzero status if there are failed tests.
    if {$::tcltest::numTests(Failed) > 0} {
        exit 1
    }
}
