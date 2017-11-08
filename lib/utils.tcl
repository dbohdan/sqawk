# Sqawk, an SQL Awk.
# Copyright (C) 2015, 2016, 2017 dbohdan
# License: MIT

namespace eval ::sqawk {}

# If key $key is absent in the dictionary variable $dictVarName set it to
# $value.
proc ::sqawk::dict-ensure-default {dictVarName key value} {
    upvar 1 $dictVarName dictionary
    set dictionary [dict merge [list $key $value] $dictionary]
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

# Override the values for the existing keys in $dictionary but do add any new
# keys to it.
proc ::sqawk::override-keys {dictionary override} {
    dict for {key _} $dictionary {
        if {[dict exists $override $key]} {
            dict set dictionary $key [dict get $override $key]
        }
    }
    return $dictionary
}
