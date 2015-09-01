# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk::parsers::awk {
    variable formats {
        raw awk
    }
    variable options {
        FS {}
        RS {}
        merge {}
        trim none
    }
}

# Find which part of the range $number is for the first range it falls into in
# out of the ranges in $rangeList. $rangeList should have the format {from1 to1
# from2 to2 ...}.
proc ::sqawk::parsers::awk::range-position {number rangeList} {
    foreach {first last} $rangeList {
        if {$number == $first} {
            if {$first == $last} {
                return both
            } else {
                return first
            }
        } elseif {$number == $last} {
            return last
        }
    }
    return none
}

# If $merge is false lappend $elem to the list stored in $varName. If $merge is
# true append it to the last element of the same list.
proc ::sqawk::parsers::awk::lappend-merge! {varName elem merge} {
    upvar 1 $varName list
    if {$merge} {
        lset list end [lindex $list end]$elem
    } else {
        lappend list $elem
    }
}

# Split $str on separators that match $regexp. Returns the resulting list of
# fields with field ranges in $mergeRanges merged together with the separators
# between them preserved.
#
# This procedure is based in part on ::textutil::split::splitx from Tcllib,
# which was originally developed by Bob Techentin and released into the public
# domain by him.
#
# ::textutil::split carries the following copyright notice:
# *****************************************************************************
#       Various ways of splitting a string.
#
# Copyright (c) 2000      by Ajuba Solutions.
# Copyright (c) 2000      by Eric Melski <ericm@ajubasolutions.com>
# Copyright (c) 2001      by Reinhard Max <max@suse.de>
# Copyright (c) 2003      by Pat Thoyts <patthoyts@users.sourceforge.net>
# Copyright (c) 2001-2006 by Andreas Kupries
#                                       <andreas_kupries@users.sourceforge.net>
#
# See the file "license.terms" for information on usage and redistribution of
# this file, and for a DISCLAIMER OF ALL WARRANTIES.
# *****************************************************************************
# The contents of "license.terms" can be found in the file "LICENSE.Tcllib" in
# the root directory of the project.
proc ::sqawk::parsers::awk::splitmerge {str regexp mergeRanges} {
    if {$str eq {}} {
        return {}
    }
    if {$regexp eq {}} {
        return [split $str {}]
    }

    set mergeRangesFiltered {}
    foreach {first last} $mergeRanges {
        if {$first < $last} {
            lappend mergeRangesFiltered $first $last
        }
    }

    # Split $str into a list of fields and separators.
    set fields {}
    set offset 0
    set merging 0
    set i 0
    set rangePos none
    while {[regexp -start $offset -indices -- $regexp $str match]} {
        lassign $match matchStart matchEnd
        set field [string range $str $offset $matchStart-1]

        set rangePos \
                [::sqawk::parsers::awk::range-position $i $mergeRangesFiltered]
        ::sqawk::parsers::awk::lappend-merge! fields $field $merging
        # Switch merging on the first field of a merge range and off on the
        # last.
        if {$rangePos eq {first}} {
            set merging 1
        } elseif {$rangePos eq {last}} {
            set merging 0
        }
        incr i

        set sep [string range $str $matchStart $matchEnd]
        # Append the separator if merging.
        if {$merging} {
            ::sqawk::parsers::awk::lappend-merge! fields $sep $merging
        }

        incr matchEnd
        set offset $matchEnd
    }
    # Handle the remainer of $str after all the separators.
    set tail [string range $str $offset end]
    if {$tail ne {}} {
        if {$rangePos eq {first}} {
            set merging 1
        }
        if {$rangePos eq {last}} {
            set merging 0
        }
        ::sqawk::parsers::awk::lappend-merge! fields $tail $merging
    }

    return $fields
}

# Trim the contents of the variable "record".
proc ::sqawk::parsers::awk::trim-record mode {
    upvar 1 record record
    switch -exact -- $mode {
        both { set record [string trim $record] }
        left { set record [string trimleft $record] }
        right { set record [string trimright $record] }
        none {}
        default { error "unknown mode: \"$mode\"" }
    }
}

# Convert raw text data into a list of database rows using regular
# expressions.
proc ::sqawk::parsers::awk::parse {data options} {
    # Parse $args.
    set RS [dict get $options RS]
    set FS [dict get $options FS]
    set mergeRanges [dict get $options merge]
    set trim [dict get $options trim]

    # Split the raw data into records.
    set records [::textutil::splitx $data $RS]
    # Remove final record if empty (typically due to a newline at the end of
    # the file).
    if {[lindex $records end] eq ""} {
        set records [lrange $records 0 end-1]
    }


    # Split records into fields.
    set rows {}
    if {$mergeRanges eq {}} {
        foreach record $records {
            ::sqawk::parsers::awk::trim-record $trim
            lappend rows [list $record {*}[::textutil::splitx $record $FS]]
        }
    } else {
        # Allow both the {1-2,3-4,5-6} and the {1 2 3 4 5 6} syntax for the
        # "merge" option.
        set rangeRegexp {[0-9]+-[0-9]+}
        set overallRegexp "^(?:$rangeRegexp,)*$rangeRegexp\$"
        if {[regexp $overallRegexp $mergeRanges]} {
            set mergeRanges [string map {- { } , { }} $mergeRanges]
        }
        foreach record $records {
            ::sqawk::parsers::awk::trim-record $trim
            lappend rows [list $record {*}[::sqawk::parsers::awk::splitmerge \
                    $record $FS $mergeRanges]]
        }
    }

    return $rows
}
