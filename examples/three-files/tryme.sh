#!/bin/sh
dir="$(dirname "$(readlink -f "$0")")"
sqawk="$dir/../../sqawk.tcl"
pushd $dir > /dev/null
"$sqawk" -FS , 'select a1, a2, b2, c2 from a inner join b on a1 = b1 inner join c on a1 = c1' 1 2 3
popd > /dev/null
