#!/bin/sh
set -e

dir=$(dirname "$(readlink -f $0)")
temp_file="/tmp/sqawk-test-results"
sqawk=$(readlink -f "$dir"/../sqawk.tcl)

cd "$dir"

run_test() {
    test_dir="$1"
    cd "$test_dir"
    echo "* running test from directory \"$test_dir/\""
    tail -n 1 command
    sh command "$sqawk" > "$temp_file"
    diff "$temp_file" results.correct && echo ok
    cd ..
}

run_test "hp"
run_test "three-files"

rm "$temp_file"
