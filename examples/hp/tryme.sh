#!/bin/sh
sqawk="$(dirname "$(readlink -f "$0")")/../../sqawk.tcl"
"$sqawk" 'select a1, b1, a2 from a inner join b on a2 = b2 where b1 < 10000 order by b1' MD5SUMS du-bytes
