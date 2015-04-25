# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk {}

# If key $key is absent in the dictionary variable $dictVarName set it to
# $value.
proc ::sqawk::dict-ensure-default {dictVarName key value} {
    upvar 1 $dictVarName dictionary
    set dictionary [dict merge [list $key $value] $dictionary]
}

# Remove and return $n elements from the list stored in the variable $varName.
proc ::sqawk::lshift! {varName {n 1}} {
    upvar 1 $varName list
    set result [lrange $list 0 $n-1]
    set list [lrange $list $n end]
    return $result
}

# Return a subdictionary of $dictionary with only the keys in $keyList and the
# corresponding values.
proc ::sqawk::filter-keys {dictionary keyList {mustExist 1}} {
    set result {}
    foreach key $keyList {
        if {!$mustExist && ![dict exists $dictionary $key]} {
            continue
        }
        dict set result $key [dict get $dictionary $key]
    }
    return $result
}
