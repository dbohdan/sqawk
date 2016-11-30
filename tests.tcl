#!/usr/bin/env tclsh
# Sqawk, an SQL Awk.
# Copyright (C) 2015, 2016 Danyil Bohdan
# License: MIT

package require fileutil
package require struct
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
    tcltest::testConstraint utf8 [expr {
        [encoding system] eq {utf-8}
    }]

    tcltest::test error-handling-1.1 {Handle broken pipe, read from stdin} \
            -setup $setup \
            -cleanup {unset filename script} \
            -body {
        set filename [make-temp-file "line 1\nline 2\nline 3"]
        set script [make-temp-file {
            fconfigure stdin -buffering line
            puts [gets stdin]
            exit 0
        }]
        sqawk-tcl {select a0 from a} < $filename \
                | [info nameofexecutable] $script
    } -result {line 1}

    tcltest::test error-handling-2.1 {Fail on bad query} \
            -setup $setup \
            -body {
        sqawk-tcl -1 asdf sqawk-tcl
    } -returnCodes 1 -match regexp -result {\s+}

    tcltest::test error-handling-2.2 {Fail on missing file} \
            -setup $setup \
            -body {
        sqawk-tcl -1 {select a0 from a} missing-file
    } -returnCodes 1  -match glob -result {*can't find file "missing-file"*}

    proc difference {filename1 filename2} {
        set lines1 [split [::fileutil::cat $filename1] \n]
        set lines2 [split [::fileutil::cat $filename2] \n]
        set lcs [::struct::list longestCommonSubsequence $lines1 $lines2]

        return [::struct::list lcsInvert $lcs [llength $lines1] \
                [llength $lines2]]
    }

    tcltest::test join-1.1 {JOIN on two files from examples/hp/} \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file {}]
        sqawk-tcl {
            select a1, b1, a2 from a inner join b on a2 = b2
            where b1 < 10000 order by b1
        } examples/hp/MD5SUMS examples/hp/du-bytes > $filename
        difference examples/hp/results.correct $filename
    } -result {}

    tcltest::test join-2.1 {JOIN on files from examples/three-files/,\
        FS setting} \
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
        difference examples/three-files/results.correct $filename
    } -result {}

    tcltest::test table-1.1 {Custom table names} \
            -setup $setup \
            -cleanup {unset filename1 filename2} \
            -body {
        set filename1 [make-temp-file "foo 1\nfoo 2\nfoo 3"]
        set filename2 [make-temp-file "bar 4\nbar 5\nbar 6"]
        sqawk-tcl {
            select foo2 from foo; select b2 from b
        } table=foo $filename1 $filename2
    } -result "1\n2\n3\n4\n5\n6"

    tcltest::test table-1.2 {Custom table names and prefixes} \
            -setup $setup \
            -cleanup {unset filename1 filename2} \
            -body {
        set filename1 [make-temp-file "foo 1\nfoo 2\nfoo 3"]
        set filename2 [make-temp-file "bar 4\nbar 5\nbar 6"]
        sqawk-tcl {
            select foo.x2 from foo; select baz2 from bar
        } table=foo prefix=x $filename1 table=bar prefix=baz $filename2
    } -result "1\n2\n3\n4\n5\n6"

    tcltest::test header-1.1 {Header row} \
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

    tcltest::test header-1.2 {Header row with spaces} \
            -setup $setup \
            -cleanup {unset content filename} \
            -body {
        set content {}
        append content "id,a column with a long name,\"even worse - quotes!\"\n"
        append content "1,foo,!\n"
        append content "2,bar,%\n"
        append content "3,baz,$\n"
        set filename [make-temp-file $content]
        sqawk-tcl {
            select "a column with a long name" from a;
            select `"even worse - quotes!"` from a
        } FS=, header=1 $filename
    } -result "foo\nbar\nbaz\n!\n%\n$"

    variable header3File [make-temp-file "001 a\n002 b\n003 c\n"]

    tcltest::test header-3.1 {"columns" per-file option} \
            -setup $setup \
            -body {
        variable header3File
        sqawk-tcl {select hello, a2 from a} columns=hello $header3File
    } -result "1 a\n2 b\n3 c"

    tcltest::test header-3.2 {"columns" per-file option} \
            -setup $setup \
            -body {
        variable header3File
        sqawk-tcl {select a1, a2 from a} columns=,,world $header3File
    } -result "1 a\n2 b\n3 c"

    tcltest::test header-3.3 {"columns" per-file option} \
            -setup $setup \
            -body {
        variable header3File
        sqawk-tcl {select "hello world" from a} {columns=hello world} \
                $header3File
    } -result 1\n2\n3

    tcltest::test header-3.4 {"columns" per-file option} \
            -setup $setup \
            -body {
        variable header3File
        sqawk-tcl {select world from a} columns=hello,world $header3File
    } -result a\nb\nc

    tcltest::test header-3.5 {"columns" per-file option} \
            -setup $setup \
            -body {
        variable header3File
        sqawk-tcl {select world from a} columns=hello,world,of,tables \
                $header3File
    } -result a\nb\nc \

    tcltest::test header-3.6 {"columns" per-file option} \
            -setup $setup \
            -body {
        variable header3File
        sqawk-tcl {select hello from a} header=1 columns=hello,world \
                $header3File
    } -result 2\n3

    tcltest::test header-3.7 {"columns" per-file option} \
            -setup $setup \
            -body {
        variable header3File
        sqawk-tcl {select hello, a from a} header=1 columns=hello \
                $header3File
    } -result "2 b\n3 c"

    tcltest::test header-3.8 {"columns" per-file option} \
            -setup $setup \
            -body {
        variable header3File
        sqawk-tcl {select a from a} header=1 columns= $header3File
    } -result b\nc

    tcltest::test field-mapping-1.1 {::sqawk::parsers::awk::valid-range?} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        source -encoding utf-8 sqawk.tcl
        set result {}
        lappend result [::sqawk::parsers::awk::valid-range? 0 1]
        lappend result [::sqawk::parsers::awk::valid-range? -5 1]
        lappend result [::sqawk::parsers::awk::valid-range? 1 0]
        lappend result [::sqawk::parsers::awk::valid-range? 5 end]
        lappend result [::sqawk::parsers::awk::valid-range? end 5]
        lappend result [::sqawk::parsers::awk::valid-range? start end]
        lappend result [::sqawk::parsers::awk::valid-range? start 5]
        lappend result [::sqawk::parsers::awk::valid-range? blah blah]
        lappend result [::sqawk::parsers::awk::valid-range? 999 9999]
    } -result {1 0 0 1 0 0 0 0 1}

    tcltest::test field-mapping-1.2 {::sqawk::parsers::awk::in-range?} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        source -encoding utf-8 sqawk.tcl
        set result {}
        lappend result [::sqawk::parsers::awk::in-range? 5 {0 1}]
        lappend result [::sqawk::parsers::awk::in-range? 5 {0 5}]
        lappend result [::sqawk::parsers::awk::in-range? 5 {0 99}]
        lappend result [::sqawk::parsers::awk::in-range? 0 {0 0}]
        lappend result [::sqawk::parsers::awk::in-range? 0 {1 1}]
        lappend result [::sqawk::parsers::awk::in-range? 1 {0 0}]
        lappend result [::sqawk::parsers::awk::in-range? 3 {5 end}]
        lappend result [::sqawk::parsers::awk::in-range? 5 {5 end}]
        lappend result [::sqawk::parsers::awk::in-range? 7 {5 end}]
    } -result {0 3 2 1 0 0 0 1 2}

    tcltest::test field-mapping-1.3 {::sqawk::parsers::awk::parseFieldMap} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        source -encoding utf-8 sqawk.tcl
        set result {}
        lappend result [::sqawk::parsers::awk::parseFieldMap auto]
        lappend result [::sqawk::parsers::awk::parseFieldMap 1,2]
        lappend result [::sqawk::parsers::awk::parseFieldMap 1,1-2,3,5-end]
        } -result [list \
            auto \
            {{1 1} {2 2}} \
            {{1 1} {1 2} {3 3} {5 end}} \
    ]

    tcltest::test field-mapping-2.1 {::sqawk::parsers::awk::map} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        source -encoding utf-8 sqawk.tcl
        set result {}
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {{1 99}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {{1 end}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {{1 1}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {{1 2}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {{4 5}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {{1 1} {2 2} {3 3}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {{1 1} {2 2} {3 end}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {{1 1} {2 3} {3 3}}]
    } -result [list \
            startABfooABbar \
            startABfooABbar \
            start \
            startABfoo \
            {{}} \
            {start foo bar} \
            {start foo bar} \
            {start fooABbar bar} \
    ]

    tcltest::test field-mapping-2.2 {::sqawk::parsers::awk::map} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        source -encoding utf-8 sqawk.tcl
        set result {}
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 99}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 end}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 1}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 2}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{4 5}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 1} {2 2} {3 3}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 1} {2 2} {3 end}}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 1} {2 3} {3 3}}]
    } -result [list \
            startABfooABbarAB \
            startABfooABbarAB \
            start \
            startABfoo \
            {{}} \
            {start foo bar} \
            {start foo barAB} \
            {start fooABbar bar} \
    ]

    tcltest::test field-mapping-2.3 {::sqawk::parsers::awk::map auto} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        source -encoding utf-8 sqawk.tcl
        set result {}
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar {}} {auto}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {auto}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 1} auto}]
        lappend result [::sqawk::parsers::awk::map \
                {start AB foo AB bar AB} {{1 1} {2 2} auto}]
    } -result [list \
            {start foo bar} \
            {start foo bar} \
            {start foo bar} \
            {start foo bar} \
    ]

    tcltest::test field-mapping-2.3 {::sqawk::parsers::awk::map} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        source -encoding utf-8 sqawk.tcl
        set result {}
        lappend result [::sqawk::parsers::awk::map \
                {foo { } 1 {   } foo { } 2 {   } foo { } 3 {}} \
                {{1 2} {3 4} {5 6}}]
        lappend result [::sqawk::parsers::awk::map \
                {bar {    } 4 { } bar {    } 5 { } bar {    } 6 {}} \
                {{1 2} {3 4} {5 6}}]
    } -result {{{foo 1} {foo 2} {foo 3}} {{bar    4} {bar    5} {bar    6}}}

    tcltest::test field-mapping-2.4 {::sqawk::parsers::awk::map} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        source -encoding utf-8 sqawk.tcl
        set result {}
        lappend result [::sqawk::parsers::awk::map \
                {foo { } 1 {   } foo { } 2 {   } foo { } 3 {}} \
                {{2 2} {4 4} {6 6}}]
        lappend result [::sqawk::parsers::awk::map \
                {bar {    } 4 { } bar {    } 5 { } bar {    } 6 {}} \
                {{2 2} {4 4} {6 6}}]
    } -result {{1 2 3} {4 5 6}}

    variable merge2File [make-temp-file \
            "foo 1   foo 2   foo 3\nbar    4 bar    5 bar    6\n"]

    tcltest::test field-mapping-3.1 {merge fields} \
            -setup $setup \
            -body {
        variable merge2File
        sqawk-tcl -OFS - {
            select a1, a2, a3 from a
        } {fields=1-2,3-4,5-6} $merge2File
    } -result "foo 1-foo 2-foo 3\nbar    4-bar    5-bar    6"

    tcltest::test field-mapping-3.2 {skip fields} \
            -setup $setup \
            -body {
        variable merge2File
        sqawk-tcl -OFS - {
            select a1, a2 from a
        } {fields=3,6} $merge2File
    } -result "foo-3\nbar-6"

    tcltest::test field-mapping-3.3 {skip and merge fields} \
            -setup $setup \
            -body {
        variable merge2File
        sqawk-tcl -OFS - {
            select a1, a2 from a
        } {fields=1-2,5-6} $merge2File
    } -result "foo 1-foo 3\nbar    4-bar    6"

    tcltest::test format-1.1 {CSV input} \
            -constraints utf8 \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file \
                "1,2,\"Hello, World!\"\nΑλαμπουρνέζικα,3,4\n5,6,7"]
        sqawk-tcl -OFS - {
            select a1, a2, a3 from a
        } format=csv $filename
    } -result "1-2-Hello, World!\nΑλαμπουρνέζικα-3-4\n5-6-7"

    tcltest::test format-1.2 {CSV input} \
            -constraints utf8 \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file \
                "1;2;\"Hello, World!\"\nΑλαμπουρνέζικα;3;4\n5;6;7"]
        sqawk-tcl -OFS - {
            select a1, a2, a3 from a
        } format=csvalt {csvsep=;} $filename
    } -result "1-2-Hello, World!\nΑλαμπουρνέζικα-3-4\n5-6-7"

    tcltest::test output-1.1 {Default output format} \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file "line 1\nline 2\nline 3"]
        sqawk-tcl -output awk {select a0 from a} $filename
    } -result "line 1\nline 2\nline 3"

    variable output2File [make-temp-file "a,b\n1,2"]

    tcltest::test output-2.1 {CSV output} \
            -setup $setup \
            -body {
        variable output2File
        sqawk-tcl -output awk {select a1 from a} $output2File
    } -result "a,b\n1,2"

    tcltest::test output-2.2 {CSV output} \
            -setup $setup \
            -body {
        variable output2File
        sqawk-tcl -output csv {select a1 from a} $output2File
    } -result "\"a,b\"\n\"1,2\""

    variable output3File [make-temp-file "1\t2\tHello, World!\t "]

    tcltest::test output-3.1 {Tcl output} \
            -setup $setup \
            -body {
        variable output3File
        sqawk-tcl \
                -FS \t \
                -output tcl \
                {select a1,a2,a3,a4 from a} $output3File
    } -result {{1 2 {Hello, World!} { }}}

    tcltest::test output-3.2 {Tcl output} \
            -setup $setup \
            -body {
        variable output3File
        sqawk-tcl \
                -FS \t \
                -output tcl,dicts=1 \
                {select a1,a2,a3,a4 from a} $output3File
    } -result {{a1 1 a2 2 a3 {Hello, World!} a4 { }}}

    variable output4File [make-temp-file "a,b,c\nd,e,f\ng,h,i"]

    tcltest::test output-4.1 {Table output} \
            -constraints utf8 \
            -setup $setup \
            -body {
        variable output4File
        sqawk-tcl \
                -FS , \
                -output table \
                {select a1,a2,a3 from a} $output4File
    } -result ┌─┬─┬─┐\n│a│b│c│\n├─┼─┼─┤\n│d│e│f│\n├─┼─┼─┤\n│g│h│i│\n└─┴─┴─┘

    tcltest::test output-4.2 {Table output} \
            -constraints utf8 \
            -setup $setup \
            -body {
        variable output4File
        sqawk-tcl \
                -FS , \
                -output {table,alignments=left center right} \
                {select a1,a2,a3 from a} $output4File
    } -result ┌─┬─┬─┐\n│a│b│c│\n├─┼─┼─┤\n│d│e│f│\n├─┼─┼─┤\n│g│h│i│\n└─┴─┴─┘

    tcltest::test output-4.3 {Table output} \
            -constraints utf8 \
            -setup $setup \
            -body {
        variable output4File
        sqawk-tcl \
                -FS , \
                -output {table,alignments=l c r} \
                {select a1,a2,a3 from a} $output4File
    } -result ┌─┬─┬─┐\n│a│b│c│\n├─┼─┼─┤\n│d│e│f│\n├─┼─┼─┤\n│g│h│i│\n└─┴─┴─┘

    tcltest::test output-4.4 {Table output} \
            -constraints utf8 \
            -setup $setup \
            -body {
        variable output4File
        sqawk-tcl \
                -FS , \
                -output {table,align=left center right} \
                {select a1,a2,a3 from a} $output4File
    } -result ┌─┬─┬─┐\n│a│b│c│\n├─┼─┼─┤\n│d│e│f│\n├─┼─┼─┤\n│g│h│i│\n└─┴─┴─┘

    tcltest::test output-4.5 {Table output} \
            -setup $setup \
            -body {
        variable output4File
        sqawk-tcl \
                -FS , \
                -output {table,align=l c r,alignments=l c r} \
                {select a1,a2,a3 from a} $output4File
    }       -returnCodes 1 \
            -result "can't use the synonym options \"align\" and \"alignments\"\
                    together*" \
            -match glob

    tcltest::test output-5.1 {JSON output} \
            -setup $setup \
            -body {
        variable output4File
        sqawk-tcl \
                -FS , \
                -output json \
                {select a1,a2,a3 from a} $output4File
    } -result [format {[%s,%s,%s]} \
            {{"a1":"a","a2":"b","a3":"c"}} \
            {{"a1":"d","a2":"e","a3":"f"}} \
            {{"a1":"g","a2":"h","a3":"i"}}]

    tcltest::test output-5.2 {JSON output} \
            -setup $setup \
            -body {
        variable output4File
        sqawk-tcl \
                -FS , \
                -output json,arrays=1 \
                {select a1,a2,a3 from a} $output4File
    } -result {[["a","b","c"],["d","e","f"],["g","h","i"]]}

    variable trim1File [make-temp-file "   a  \n"]

    tcltest::test trim-1.1 {trim option} \
            -setup $setup \
            -body {
        variable trim1File
        sqawk-tcl {select a1 from a} $trim1File
    } -result {}

    tcltest::test trim-1.2 {trim option} \
            -setup $setup \
            -body {
        variable trim1File
        sqawk-tcl {select a1 from a} trim=left $trim1File
    } -result a

    tcltest::test trim-1.3 {trim option} \
            -setup $setup \
            -body {
        variable trim1File
        sqawk-tcl {select a1 from a} trim=both $trim1File
    } -result a

    tcltest::test a0-1.1 {Verbatim reproduction of input in a0} \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file "test:\n\ttclsh tests.tcl\n\"\{"]
        sqawk-tcl {select a0 from a} $filename
    } -result "test:\n\ttclsh tests.tcl\n\"\{"

    tcltest::test a0-1.2 {Explicitly enable a0} \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file "test:\n\ttclsh tests.tcl\n\"\{"]
        sqawk-tcl {select a0 from a} F0=yes $filename
    } -result "test:\n\ttclsh tests.tcl\n\"\{"

    tcltest::test a0-1.3 {Disable a0 and try to select it} \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file "test:\n\ttclsh tests.tcl\n\"\{"]
        sqawk-tcl {select a0 from a} F0=off $filename
    } -returnCodes 1 -match glob -result {no such column: a0*}

    tcltest::test a0-1.4 {Disable a0 and do unrelated things} \
            -setup $setup \
            -cleanup {unset filename} \
            -body {
        set filename [make-temp-file "1 2 3\n4 5 6"]
        sqawk-tcl {select a1, a2 from a} F0=off $filename
    } -result "1 2\n4 5"

    tcltest::test empty-fields-1.1 {Empty fields} \
            -setup $setup \
            -body {
        sqawk-tcl -FS - {select a1, a2 from a} << "0-1\n\na-b\n\nc-d\n"
    } -result "0 1\n \na b\n \nc d"

    variable emptyLines1File [make-temp-file "\n\n\n\n"]

    tcltest::test empty-lines-1.1 {Empty lines} \
            -setup $setup \
            -body {
        variable emptyLines1File
        sqawk-tcl {select a1 from a} $emptyLines1File
    } -result "\n\n\n"

    tcltest::test empty-lines-1.2 {Empty lines} \
            -setup $setup \
            -body {
        variable emptyLines1File
        sqawk-tcl {select a1 from a} format=csv $emptyLines1File
    } -result "\n\n\n"

    variable datatypes1File [make-temp-file "001 a\n002 b\nc"]

    tcltest::test datatypes-1.1 {Datatypes} \
            -setup $setup \
            -body {
        variable datatypes1File
        sqawk-tcl {select a1,a2 from a} $datatypes1File
    } -result "1 a\n2 b\nc "

    tcltest::test datatypes-1.2 {Datatypes} \
            -constraints printfInSqlite3 \
            -setup $setup \
            -body {
        variable datatypes1File
        sqawk-tcl {select printf("%03d",a1),a2 from a} $datatypes1File
    } -result "001 a\n002 b\n000 "

    tcltest::test datatypes-1.3 {Datatypes} \
            -setup $setup \
            -body {
        variable datatypes1File
        sqawk-tcl {select a1,a2 from a} datatypes=real,text $datatypes1File
    } -result "1.0 a\n2.0 b\nc "

    tcltest::test datatypes-1.4 {Datatypes} \
            -setup $setup \
            -body {
        variable datatypes1File
        sqawk-tcl {select a1,a2 from a} datatypes=null,blob $datatypes1File
    } -result "001 a\n002 b\nc "

    tcltest::test datatypes-1.5 {Datatypes} \
            -setup $setup \
            -body {
        variable datatypes1File
        sqawk-tcl {select a1,a2 from a} datatypes=text,text $datatypes1File
    } -result "001 a\n002 b\nc "

    # NF tests

    variable nf1File [make-temp-file "A B\nA B C\nA B C D\n"]

    tcltest::test nf-1.1 {NF mode "crop"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 0 \
                -MNF crop \
                -output tcl \
                {select * from a} $nf1File
    } -result {{1 0 {A B}} {2 0 {A B C}} {3 0 {A B C D}}}

    tcltest::test nf-1.2 {NF mode "crop"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 1 \
                -MNF crop \
                -output tcl \
                {select * from a} $nf1File
    } -result {{1 1 {A B} A} {2 1 {A B C} A} {3 1 {A B C D} A}}

    tcltest::test nf-1.3 {NF mode "crop"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 2 \
                -MNF crop \
                -output tcl \
                {select * from a} $nf1File
    } -result {{1 2 {A B} A B} {2 2 {A B C} A B} {3 2 {A B C D} A B}}

    tcltest::test nf-1.4 {NF mode "crop"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 3 \
                -MNF crop \
                -output tcl \
                {select * from a} $nf1File
    } -result {{1 2 {A B} A B {}} {2 3 {A B C} A B C} {3 3 {A B C D} A B C}}

    tcltest::test nf-1.5 {NF mode "crop"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 0 \
                -MNF crop \
                -output tcl \
                {select * from a} F0=false $nf1File
    } -result {{1 0} {2 0} {3 0}}

    tcltest::test nf-1.6 {NF mode "crop"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 1 \
                -MNF crop \
                -output tcl \
                {select * from a} F0=false $nf1File
    } -result {{1 1 A} {2 1 A} {3 1 A}}

    tcltest::test nf-1.7 {NF mode "crop"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 2 \
                -MNF crop \
                -output tcl \
                {select * from a} F0=false $nf1File
    } -result {{1 2 A B} {2 2 A B} {3 2 A B}}

    tcltest::test nf-1.8 {NF mode "crop"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 3 \
                -MNF crop \
                -output tcl \
                {select * from a} F0=false $nf1File
    } -result {{1 2 A B {}} {2 3 A B C} {3 3 A B C}}


    variable nf2File [make-temp-file "A B C D\nA B C\nA B\n"]

    tcltest::test nf-2.1 {NF mode "crop" 2} \
            -setup $setup \
            -body {
        variable nf2File
        sqawk-tcl \
                -FS " " \
                -NF 2 \
                -MNF crop \
                -output tcl \
                {select * from a} $nf2File
    } -result {{1 2 {A B C D} A B} {2 2 {A B C} A B} {3 2 {A B} A B}}

    tcltest::test nf-2.2 {NF mode "crop" 2} \
            -setup $setup \
            -body {
        variable nf2File
        sqawk-tcl \
                -FS " " \
                -NF 3 \
                -MNF crop \
                -output tcl \
                {select * from a} $nf2File
    } -result {{1 3 {A B C D} A B C} {2 3 {A B C} A B C} {3 2 {A B} A B {}}}

    tcltest::test nf-2.3 {NF mode "crop" 2} \
            -setup $setup \
            -body {
        variable nf2File
        sqawk-tcl \
                -FS " " \
                -NF 4 \
                -MNF crop \
                -output tcl \
                {select * from a} $nf2File
    } -result \
        {{1 4 {A B C D} A B C D} {2 3 {A B C} A B C {}} {3 2 {A B} A B {} {}}}

    tcltest::test nf-3.1 {NF mode "expand"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 0 \
                -MNF expand \
                -output tcl \
                {select * from a} $nf1File
    } -result \
        {{1 2 {A B} A B {} {}} {2 3 {A B C} A B C {}} {3 4 {A B C D} A B C D}}

    tcltest::test nf-3.2 {NF mode "expand"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 1 \
                -MNF expand \
                -output tcl \
                {select * from a} $nf1File
    } -result \
        {{1 2 {A B} A B {} {}} {2 3 {A B C} A B C {}} {3 4 {A B C D} A B C D}}

    tcltest::test nf-3.3 {NF mode "expand"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 2 \
                -MNF expand \
                -output tcl \
                {select * from a} $nf1File
    } -result \
        {{1 2 {A B} A B {} {}} {2 3 {A B C} A B C {}} {3 4 {A B C D} A B C D}}

    tcltest::test nf-3.4 {NF mode "expand"} \
            -setup $setup \
            -body {
        variable nf1File
        sqawk-tcl \
                -FS " " \
                -NF 3 \
                -MNF expand \
                -output tcl \
                {select * from a} $nf1File
    } -result \
        {{1 2 {A B} A B {} {}} {2 3 {A B C} A B C {}} {3 4 {A B C D} A B C D}}

    tcltest::test nf-4.1 {NF mode "error"} \
            -setup $setup \
            -cleanup {unset content filename} \
            -body {
        set content {}
        append content "A B\n"
        append content "A B C\n"
        set filename [make-temp-file $content]
        sqawk-tcl \
            -FS " " \
            -NF 2 \
            -MNF error \
            -output tcl \
            {select * from a} $filename
    } -returnCodes 1 -match glob -result {table a has no column named a3*}

    tcltest::test nf-5.1 {invalid NF mode} \
            -setup $setup \
            -cleanup {unset content filename} \
            -body {
        set content {}
        append content "A B\n"
        append content "A B C\n"
        set filename [make-temp-file $content]
        sqawk-tcl \
            -FS " " \
            -NF 2 \
            -MNF foo \
            -output tcl \
            {select * from a} $filename
    } -returnCodes 1 -match glob -result {invalid MNF value: "foo"*}

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

    tcltest::test tabulate-1.1 {Tabulate as application} \
            -constraints utf8 \
            -setup $setup \
            -cleanup {unset result} \
            -body $tabulateAppTestBody \
            -result $tabulateAppTestOutput

    proc tabulate-tcl args {
        exec jimsh lib/tabulate.tcl {*}$args
    }

    tcltest::test tabulate-1.2 {Tabulate as application with Jim Tcl} \
            -setup $setup \
            -cleanup {unset result} \
            -constraints {jimsh utf8} \
            -body $tabulateAppTestBody \
            -result $tabulateAppTestOutput

    rename tabulate-tcl {}

    tcltest::test tabulate-2.1 {Tabulate as library} \
            -constraints utf8 \
            -setup $setup \
            -body {
        source -encoding utf-8 [file join $path lib tabulate.tcl]
        return \n[::tabulate::tabulate -data {{a b c} {d e f}}]\n
    } -result {
┌─┬─┬─┐
│a│b│c│
├─┼─┼─┤
│d│e│f│
└─┴─┴─┘
}

    tcltest::test tabulate-2.2 {Tabulate as library} \
            -setup $setup \
            -body {
        source -encoding utf-8 [file join $path lib tabulate.tcl]
        return  \n[::tabulate::tabulate \
                -data {{a b c} {d e f}} \
                -style $::tabulate::style::loFi]\n
    } -result {
+-+-+-+
|a|b|c|
+-+-+-+
|d|e|f|
+-+-+-+
}

    tcltest::test tabulate-2.3 {Tabulate as library} \
            -constraints utf8 \
            -setup $setup \
            -body {
        source -encoding utf-8 [file join $path lib tabulate.tcl]
        return \n[::tabulate::tabulate \
                -margins 1 \
                -data {{a b c} {d e f}}]\n
    } -result {
┌───┬───┬───┐
│ a │ b │ c │
├───┼───┼───┤
│ d │ e │ f │
└───┴───┴───┘
}

    tcltest::test tabulate-2.4 {Tabulate as library} \
            -constraints utf8 \
            -setup $setup \
            -body {
        source -encoding utf-8 [file join $path lib tabulate.tcl]
        return \n[::tabulate::tabulate \
                -alignments {left center right} \
                -data {{hello space world} {foo bar baz}}]\n
    } -result {
┌─────┬─────┬─────┐
│hello│space│world│
├─────┼─────┼─────┤
│foo  │ bar │  baz│
└─────┴─────┴─────┘
}

    tcltest::test tabulate-2.5 {Tabulate as library} \
            -constraints utf8 \
            -setup $setup \
            -body {
        source -encoding utf-8 [file join $path lib tabulate.tcl]
        return \n[::tabulate::tabulate \
                -align {left center right} \
                -data {{hello space world} {foo bar baz}}]\n
    } -result {
┌─────┬─────┬─────┐
│hello│space│world│
├─────┼─────┼─────┤
│foo  │ bar │  baz│
└─────┴─────┴─────┘
}

    tcltest::test tabulate-2.6 {Tabulate as library} \
            -setup $setup \
            -body {
        source -encoding utf-8 [file join $path lib tabulate.tcl]
        return \n[::tabulate::tabulate \
                -alignments {left center right} \
                -align {left center right} \
                -data {{hello space world} {foo bar baz}}]\n
    }       -returnCodes 1 \
            -result {can't use the flags "-alignments", "-align" together}

    tcltest::test tabulate-3.0 {format-flag-synonyms} \
            -setup $setup \
            -cleanup {unset result} \
            -body {
        set result {}
        lappend result [::tabulate::options::format-flag-synonyms -foo]
        lappend result [::tabulate::options::format-flag-synonyms {-foo -bar}]
        lappend result [::tabulate::options::format-flag-synonyms \
                {-foo -bar -baz -quux}]
        return $result
    } -result {{"-foo"} {"-foo" ("-bar")} {"-foo" ("-bar", "-baz", "-quux")}}

    # Exit with a nonzero status if there are failed tests.
    set failed [expr {$tcltest::numTests(Failed) > 0}]

    tcltest::cleanupTests
    if {$failed} {
        exit 1
    }
}
