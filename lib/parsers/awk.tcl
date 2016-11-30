# Sqawk, an SQL Awk.
# Copyright (C) 2015, 2016 Danyil Bohdan
# License: MIT

namespace eval ::sqawk::parsers::awk {
    variable formats {
        raw awk
    }
    variable options {
        FS {}
        RS {}
        merge {}
        skip {}
        trim none
    }
}

# Find out if $number is in a range in $rangeList. Returns 1-3 if it is and 0 if
# it isn't.
proc ::sqawk::parsers::awk::in-range? {number rangeList} {
    foreach {first last} $rangeList {
        if {$first == $number} {
            return 1
        }
        if {($first < $number) && ($number < $last)} {
            return 2
        }
        if {$number == $last} {
            return 3
        }
    }
    return 0
}

# Split $str on separators that match $regexp. Returns the resulting list of
# fields and the list of separators between them.
proc ::sqawk::parsers::awk::sepsplit {str regexp} {
    if {$str eq {}} {
        return {}
    }
    if {$regexp eq {}} {
        return [split $str {}]
    }

    # Split $str into a list of fields and separators.
    set fieldsAndSeps {}
    set offset 0
    while {[regexp -start $offset -indices -- $regexp $str match]} {
        lassign $match matchStart matchEnd
        lappend fieldsAndSeps [string range $str $offset     $matchStart-1]
        lappend fieldsAndSeps [string range $str $matchStart $matchEnd]

        set offset [expr {$matchEnd + 1}]
    }
    # Handle the remainder of $str after all the separators.
    set tail [string range $str $offset end]
    if {$tail ne {}} {
        lappend fieldsAndSeps $tail
        lappend fieldsAndSeps {}
    }

    return $fieldsAndSeps
}

# Returns $record trimmed according to $mode.
proc ::sqawk::parsers::awk::trim-record {record mode} {
    switch -exact -- $mode {
        both    { set record [string trim $record]      }
        left    { set record [string trimleft $record]  }
        right   { set record [string trimright $record] }
        none    {}
        default { error "unknown mode: \"$mode\""       }
    }
    return $record
}

# Return 1 if $from-$to is a valid field range and 0 otherwise.
proc ::sqawk::parsers::awk::valid-range? {from to} {
    return [expr {
        [string is integer -strict $from] &&
        (0 <= $from) &&
        (($to eq {end}) || [string is integer -strict $to]) &&
        ($from <= $to)
    }]
}

# Return 1 if two lists of ranges have overlapping ranges and 0 otherwise.
# O(N*M).
proc ::sqawk::parsers::awk::overlap? {ranges1 ranges2} {
    foreach {from1 to1} $ranges1 {
        foreach {from2 to2} $ranges2 {
            if {($from1 <= $to2) && ($from2 <= $to1)} {
                return 1
            }
        }
    }

    return 0
}

# Merge fields in $mergeRanges and remove those in $skipRanges provided the two
# lists of ranges do not overlap. (The check can be disabled at your own risk.)
proc ::sqawk::parsers::awk::skipmerge {fieldsAndSeps skipRanges mergeRanges
        {checkOverlap 1}} {
    if {$checkOverlap &&
            [::sqawk::parsers::awk::overlap? $skipRanges $mergeRanges]} {
        error {skip and merge ranges overlap;\
                can't skip and merge the same field}
    }
    set columns {}
    set i 0
    set prevSep {}
    foreach {field sep} $fieldsAndSeps {
        set skip [::sqawk::parsers::awk::in-range? $i $skipRanges]
        set merge [::sqawk::parsers::awk::in-range? $i $mergeRanges]
        if {$skip} {
            # Skipping.
        } elseif {$merge > 1} {
            if {$columns eq {}} {
                lappend columns {}
            }
            lset columns end [lindex $columns end]${prevSep}$field
        } else {
            lappend columns $field
        }

        set prevSep $sep
        incr i
    }
    if {[info exists merge] && $merge == 2} {
        lset columns end [lindex $columns end]$prevSep
    }

    return $columns
}

# Takes a range string like {1-2,3-4,5-6} or {1 2 3 4 5 6} and returns a list
# like {0 1 2 3 4 5}.
proc ::sqawk::parsers::awk::normalizeRanges ranges {
    set rangeRegexp {[0-9]+-(end|[0-9]+)}
    set overallRegexp ^(?:$rangeRegexp,)*$rangeRegexp\$
    if {[regexp $overallRegexp $ranges]} {
        set ranges [string map {- { } , { }} $ranges]
    }
    set rangesFromZero {}
    foreach x $ranges {
        lappend rangesFromZero [expr {$x eq {end} ? $x : $x - 1}]
    }
    return $rangesFromZero
}

# Convert raw text data into a list of database rows using regular
# expressions.
proc ::sqawk::parsers::awk::parse {data options} {
    # Parse $args.
    set RS [dict get $options RS]
    set FS [dict get $options FS]
    set skipRanges [dict get $options skip]
    set mergeRanges [dict get $options merge]
    set trim [dict get $options trim]

    # Split the raw data into records.
    set records [::textutil::splitx $data $RS]
    # Remove final record if empty (typically due to a newline at the end of
    # the file).
    if {[lindex $records end] eq {}} {
        set records [lrange $records 0 end-1]
    }


    # Split records into fields.
    set rows {}
    if {($skipRanges eq {}) && ($mergeRanges eq {})} {
        foreach record $records {
            set record [::sqawk::parsers::awk::trim-record $record $trim]
            lappend rows [list $record {*}[::textutil::splitx $record $FS]]
        }
    } else {
        set skipRangesFromZero [::sqawk::parsers::awk::normalizeRanges \
                $skipRanges]
        set mergeRangesFromZero [::sqawk::parsers::awk::normalizeRanges \
                $mergeRanges]
        if {[::sqawk::parsers::awk::overlap? \
                $skipRangesFromZero $mergeRangesFromZero]} {
            error {skip and merge ranges overlap;\
                    can't skip and merge the same field}
        }

        foreach record $records {
            set record [::sqawk::parsers::awk::trim-record $record $trim]
            set columns [::sqawk::parsers::awk::skipmerge \
                    [::sqawk::parsers::awk::sepsplit $record $FS] \
                    $skipRangesFromZero \
                    $mergeRangesFromZero \
                    0]
            lappend rows [list $record {*}$columns]
        }
    }

    return $rows
}
