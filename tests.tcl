#!/usr/bin/env tclsh
# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

package require fileutil
package require tcltest

namespace eval ::sqawk::tests {
    variable path [file dirname [file dirname [file normalize $argv0/___]]]
    variable setup [list apply {{path} {
        cd $path
    }} $path]

    if {[llength $argv] > 0} {
        tcltest::configure -match $argv
    }

    proc make-temp-file content {
        return [tcltest::makeFile $content [::fileutil::tempfile]]
    }

    # Run Sqawk with {*}$args.
    proc sqawk-tcl args {
        exec [info nameofexecutable] sqawk.tcl {*}$args
    }

    # Return 1 if $version in the format of X.Y.Z.W is newer than $reference and
    # 0 otherwise.
    proc newer-or-equal {version reference} {
        foreach a [split $version .] b [split $reference .] {
            if {$a > $b} {
                return 1
            } elseif {$a < $b} {
                return 0
            }
        }
        return 1
    }

    # Set the constraints.
    set sqliteVersion [sqawk-tcl {select sqlite_version()} << {}]
    tcltest::testConstraint printfInSqlite3 \
            [newer-or-equal $sqliteVersion 3.8.3]
    tcltest::testConstraint jimsh [expr {
        ![catch { exec jimsh << {} }]
    }]

    tcltest::test test1 {Handle broken pipe, read from stdin} \
            -constraints unix \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file "line 1\nline 2\nline 3"]
        sqawk-tcl {select a0 from a} < $filename | head -n 1
    } -result {line 1}

    tcltest::test test2 {Fail on bad query or missing file} \
            -setup $setup \
            -cleanup {unset result} \
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
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file {}]
        sqawk-tcl {
            select a1, b1, a2 from a inner join b on a2 = b2
            where b1 < 10000 order by b1
        } examples/hp/MD5SUMS examples/hp/du-bytes > $filename
        exec diff examples/hp/results.correct $filename
    } -result {}

    tcltest::test test4 {JOIN on files from examples/three-files/, FS setting} \
            -constraints unix \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file {}]
        set dir examples/three-files/
        sqawk-tcl -FS , {
            select a1, a2, b2, c2 from a inner join b on a1 = b1
            inner join c on a1 = c1
        } $dir/1 FS=_ FS=, $dir/2 $dir/3 > $filename
        unset dir
        exec diff examples/three-files/results.correct $filename
    } -result {}

    tcltest::test test5 {Custom table names} \
            -setup $setup \
            -cleanup {unset filename1 filename2} \
            -body {
        set filename1 [make-temp-file "foo 1\nfoo 2\nfoo 3"]
        set filename2 [make-temp-file "bar 4\nbar 5\nbar 6"]
        sqawk-tcl {
            select foo2 from foo; select b2 from b
        } table=foo $filename1 $filename2
    } -result "1\n2\n3\n4\n5\n6"

    tcltest::test test6 {Custom table names and prefixes} \
            -setup $setup \
            -cleanup {unset filename1 filename2} \
            -body {
        set filename1 [make-temp-file "foo 1\nfoo 2\nfoo 3"]
        set filename2 [make-temp-file "bar 4\nbar 5\nbar 6"]
        sqawk-tcl {
            select foo.x2 from foo; select baz2 from bar
        } table=foo prefix=x $filename1 table=bar prefix=baz $filename2
    } -result "1\n2\n3\n4\n5\n6"

    tcltest::test test7 {Header row} \
            -setup $setup \
            -cleanup {unset content filename} \
            -body {
        set content {}
        append content "name\tposition\toffice\tphone\n"
        append content "Smith\tCEO\t10\t555-1234\n"
        append content "James\tHead of marketing\t11\t555-1235\n"
        append content "McDonald\tDeveloper\t12\t555-1236\tGood at tables\n"
        set filename [make-temp-file $content]
        sqawk-tcl {
            select name, office from staff
            where position = "CEO"
                    or staff.phone = "555-1234"
                    or staff.a5 = "Good at tables"
        } FS=\t table=staff prefix=a header=1 $filename
    } -result "Smith 10\nMcDonald 12"

    tcltest::test test8 {::sqawk::parsers::awk::splitmerge} \
            -setup $setup \
            -cleanup {unset result} \
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
            -cleanup {unset content filename result} \
            -body {
        set content {}
        append content "foo 1   foo 2   foo 3\n"
        append content "bar    4 bar    5 bar    6\n"
        set filename [make-temp-file $content]
        set result {}
        lappend result [sqawk-tcl -OFS - {
            select a1, a2, a3 from a
        } {merge=0-1,2-3,4-5} $filename]
        lappend result [sqawk-tcl -OFS - {
            select a1, a2, a3 from a
        } {merge=0 1 2 3 4 5} $filename]
        return [lindex [lsort -unique $result] 0]
    } -result "foo 1-foo 2-foo 3\nbar    4-bar    5-bar    6"

    tcltest::test test10 {CSV input} \
            -setup $setup \
            -cleanup {unset filename1 filename2 result} \
            -body {
        set result {}
        set filename1 [make-temp-file \
                "1,2,\"Hello, World!\"\nΑλαμπουρνέζικα,3,4\n5,6,7"]
        set filename2 [make-temp-file \
                "1;2;\"Hello, World!\"\nΑλαμπουρνέζικα;3;4\n5;6;7"]

        lappend result [sqawk-tcl -OFS - {
            select a1, a2, a3 from a
        } format=csv $filename1]
        lappend result [sqawk-tcl -OFS - {
            select a1, a2, a3 from a
        } format=csvalt {csvsep=;} $filename2]
        return [lindex [lsort -unique $result] 0]
    } -result "1-2-Hello, World!\nΑλαμπουρνέζικα-3-4\n5-6-7"

    tcltest::test test11 {Default output format} \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file "line 1\nline 2\nline 3"]
        sqawk-tcl -output awk {select a0 from a} $filename
    } -result "line 1\nline 2\nline 3"

    tcltest::test test12 {Verbatim reproduction of input in a0} \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file "test:\n\ttclsh tests.tcl\n\"\{"]
        sqawk-tcl {select a0 from a} $filename
    } -result "test:\n\ttclsh tests.tcl\n\"\{"

    tcltest::test test13 {Empty lines} \
            -setup $setup \
            -cleanup {unset filename result} \
            -body {
        set filename [make-temp-file "\n\n\n\n"]
        set result {}
        lappend result [sqawk-tcl {select a1 from a} $filename]
        lappend result [sqawk-tcl {select a1 from a} format=csv $filename]
        return $result
    } -result [list "\n\n\n" "\n\n\n"]

    tcltest::test test14 {CSV output} \
            -setup $setup \
            -cleanup {unset filename result} \
            -body {
        set filename [make-temp-file "a,b\n1,2"]
        set result {}
        lappend result [sqawk-tcl -output awk {select a1 from a} $filename]
        lappend result [sqawk-tcl -output csv {select a1 from a} $filename]
        return $result
    } -result [list "a,b\n1,2" "\"a,b\"\n\"1,2\""]

    tcltest::test test15 {Tcl output} \
            -setup $setup \
            -cleanup {unset filename result} \
            -body {
        set filename [make-temp-file "1\t2\tHello, World!\t "]
        lappend result [sqawk-tcl \
                -FS \t \
                -output tcl \
                {select a1,a2,a3,a4 from a} $filename]
        lappend result [sqawk-tcl \
                -FS \t \
                -output tcl,dicts=1 \
                {select a1,a2,a3,a4 from a} $filename]
        return $result
    } -result [list {{1 2 {Hello, World!} { }}} \
            {{a1 1 a2 2 a3 {Hello, World!} a4 { }}}]

    tcltest::test test16 {Table output} \
            -setup $setup \
            -cleanup {unset filename result} \
            -body {
        set filename [make-temp-file "a,b,c\nd,e,f\ng,h,i"]
        lappend result [sqawk-tcl \
                -FS , \
                -output table \
                {select a1,a2,a3 from a} $filename]
        lappend result [sqawk-tcl \
                -FS , \
                -output {table,alignments=left center right} \
                {select a1,a2,a3 from a} $filename]
        return $result
    } -result [list \
        ┌─┬─┬─┐\n│a│b│c│\n├─┼─┼─┤\n│d│e│f│\n├─┼─┼─┤\n│g│h│i│\n└─┴─┴─┘ \
        ┌─┬─┬─┐\n│a│b│c│\n├─┼─┼─┤\n│d│e│f│\n├─┼─┼─┤\n│g│h│i│\n└─┴─┴─┘ \
    ]

    tcltest::test test17 {trim option} \
            -setup $setup \
            -cleanup {unset filename result} \
            -body {
        set filename [make-temp-file "   a  \n"]
        set result {}
        lappend result [sqawk-tcl {select a1 from a} $filename]
        lappend result [sqawk-tcl {select a1 from a} trim=left $filename]
        lappend result [sqawk-tcl {select a1 from a} trim=both $filename]
        return $result
    } -result {{} a a}

    tcltest::test test18 {JSON output} \
            -setup $setup \
            -cleanup {unset filename result} \
            -body {
        set filename [make-temp-file "a,b,c\nd,e,f\ng,h,i\n"]
        set result {}
        lappend result [sqawk-tcl \
                -FS , \
                -output json \
                {select a1,a2,a3 from a} $filename]
        lappend result [sqawk-tcl \
                -FS , \
                -output json,arrays=1 \
                {select a1,a2,a3 from a} $filename]
        return $result
    } -result [list \
            [format {[%s,%s,%s]} \
                    {{"a1":"a","a2":"b","a3":"c"}} \
                    {{"a1":"d","a2":"e","a3":"f"}} \
                    {{"a1":"g","a2":"h","a3":"i"}}] \
            {[["a","b","c"],["d","e","f"],["g","h","i"]]}]


    tcltest::test test19 {Datatypes} \
            -constraints printfInSqlite3 \
            -cleanup {unset filename result} \
            -setup $setup \
            -body {
        set filename [make-temp-file "001 a\n002 b\nc"]
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
        return $result
    } -result [list \
            "1 a\n2 b\nc " \
            "001 a\n002 b\n000 " \
            "1.0 a\n2.0 b\nc " \
            "001 a\n002 b\nc " \
            "001 a\n002 b\nc "]


    # NF tests

    tcltest::test test-nf-1-crop {NF mode crop} \
            -setup $setup \
            -cleanup {unset content filename result} \
            -body {
        set content {}
        append content "A B\n"
        append content "A B C\n"
        append content "A B C D\n"
        set filename [make-temp-file $content]
        foreach nf {0 1 2 3} {
            lappend result [sqawk-tcl \
                -FS " " \
                -NF $nf \
                -MNF crop \
                -output tcl \
                {select * from a} $filename]
        }
        return [join $result \n]
    } -result [join {
        {{1 1 {A B}} {2 1 {A B C}} {3 1 {A B C D}}}
        {{1 2 {A B} A} {2 2 {A B C} A} {3 2 {A B C D} A}}
        {{1 3 {A B} A B} {2 3 {A B C} A B} {3 3 {A B C D} A B}}
        {{1 3 {A B} A B {}} {2 4 {A B C} A B C} {3 4 {A B C D} A B C}}
    } \n]

    tcltest::test test-nf-2-crop {NF mode crop 2} \
            -setup $setup \
            -cleanup {unset content filename result} \
            -body {
        set content {}
        append content "A B C D\n"
        append content "A B C\n"
        append content "A B\n"
        set filename [make-temp-file $content]
        foreach nf {2 3 4} {
            lappend result [sqawk-tcl \
                -FS " " \
                -NF $nf \
                -MNF crop \
                -output tcl \
                {select * from a} $filename]
        }
        return [join $result \n]
    } -result [join {
        {{1 3 {A B C D} A B} {2 3 {A B C} A B} {3 3 {A B} A B}}
        {{1 4 {A B C D} A B C} {2 4 {A B C} A B C} {3 3 {A B} A B {}}}
        {{1 5 {A B C D} A B C D} {2 4 {A B C} A B C {}} {3 3 {A B} A B {} {}}}
    } \n]

    tcltest::test test-nf-3-expand {NF mode expand} \
            -setup $setup \
            -cleanup {unset content filename result} \
            -body {
        set content {}
        append content "A B\n"
        append content "A B C\n"
        append content "A B C D\n"
        set filename [make-temp-file $content]
        foreach nf {0 1 2 3} {
            lappend result [sqawk-tcl \
                -FS " " \
                -NF $nf \
                -MNF expand \
                -output tcl \
                {select * from a} $filename]
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
            -cleanup {unset content filename} \
            -body {
        set content {}
        append content "A B\n"
        append content "A B C\n"
        set filename [make-temp-file $content]
        catch {
            sqawk-tcl \
                -FS " " \
                -NF 2 \
                -MNF normal \
                -output tcl \
                {select * from a} $filename
        }
    } -result 1

    # Tabulate tests

    set tabulateAppTestBody {
        set result {}
        lappend result [tabulate-tcl << "a b c\nd e f\n"]
        lappend result [tabulate-tcl -FS , << "a,b,c\nd,e,f\n"]
        lappend result [tabulate-tcl -margins 1 << "a b c\nd e f\n"]
        lappend result [tabulate-tcl -alignments {left center right} << \
                "hello space world\nfoo bar baz\n"]
        return \n[join $result \n]
    }

    set tabulateAppTestOutput {
┌─┬─┬─┐
│a│b│c│
├─┼─┼─┤
│d│e│f│
└─┴─┴─┘
┌─┬─┬─┐
│a│b│c│
├─┼─┼─┤
│d│e│f│
└─┴─┴─┘
┌───┬───┬───┐
│ a │ b │ c │
├───┼───┼───┤
│ d │ e │ f │
└───┴───┴───┘
┌─────┬─────┬─────┐
│hello│space│world│
├─────┼─────┼─────┤
│foo  │ bar │  baz│
└─────┴─────┴─────┘}

    proc tabulate-tcl args {
        exec [info nameofexecutable] lib/tabulate.tcl {*}$args
    }

    tcltest::test tabulate-1 {Tabulate as application} \
            -setup $setup \
            -body $tabulateAppTestBody \
            -result $tabulateAppTestOutput

    proc tabulate-tcl args {
        exec jimsh lib/tabulate.tcl {*}$args
    }

    tcltest::test tabulate-2 {Tabulate as application with Jim Tcl} \
            -setup $setup \
            -constraints jimsh \
            -body $tabulateAppTestBody \
            -result $tabulateAppTestOutput

    rename tabulate-tcl {}

    tcltest::test tabulate-3 {Tabulate as library} \
            -setup $setup \
            -body {
        set result {}
        source [file join $path lib tabulate.tcl]
        lappend result [::tabulate::tabulate \
                -data {{a b c} {d e f}}]
        lappend result [::tabulate::tabulate \
                -data {{a b c} {d e f}} \
                -style $::tabulate::style::loFi]
        lappend result [::tabulate::tabulate \
                -margins 1 \
                -data {{a b c} {d e f}}]
        lappend result [::tabulate::tabulate \
                -alignments {left center right} \
                -data {{hello space world} {foo bar baz}}]
        return \n[join $result \n]
    } -result {
┌─┬─┬─┐
│a│b│c│
├─┼─┼─┤
│d│e│f│
└─┴─┴─┘
+-+-+-+
|a|b|c|
+-+-+-+
|d|e|f|
+-+-+-+
┌───┬───┬───┐
│ a │ b │ c │
├───┼───┼───┤
│ d │ e │ f │
└───┴───┴───┘
┌─────┬─────┬─────┐
│hello│space│world│
├─────┼─────┼─────┤
│foo  │ bar │  baz│
└─────┴─────┴─────┘}

    tcltest::cleanupTests
    # Exit with a nonzero status if there are failed tests.
    if {$tcltest::numTests(Failed) > 0} {
        exit 1
    }
}
