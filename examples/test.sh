#!/bin/sh
set -e
dir="$(dirname $(readlink -f $0))"
tempfilename="/tmp/sqawk-test-results"
cd "$dir"
../sqawk.tcl "select a.a1, b.b5, a.a2 from a inner join b on a.a2 = b.b9 where b.b5 < 10000 order by b.b5" MD5SUMS list > $tempfilename
diff $tempfilename results.correct
rm $tempfilename
