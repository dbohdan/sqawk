# Sqawk, an SQL Awk.
# Copyright (c) 2015, 2016, 2017, 2018 dbohdan
# License: MIT

namespace eval ::sqawk::parsers::awk {
    variable formats {
        awk
    }
    variable options {
        FS {}
        RS {}
        fields auto
        trim none
    }
}

# Split $str on separators that match $regexp. Returns a list consisting of
# fields and, if $includeSeparators is 1, the separators after each.
proc ::sqawk::parsers::awk::sepsplit {str regexp {includeSeparators 1}} {
    if {$str eq {}} {
        return {}
    }
    if {$regexp eq {}} {
        return [split $str {}]
    }
    # Thanks to KBK for the idea.
    if {[regexp $regexp {}]} {
        error "splitting on regexp \"$regexp\" would cause infinite loop"
    }

    # Split $str into a list of fields and separators.
    set fieldsAndSeps {}
    set offset 0
    while {[regexp -start $offset -indices -- $regexp $str match]} {
        lassign $match matchStart matchEnd
        lappend fieldsAndSeps \
                [string range $str $offset [expr {$matchStart - 1}]]
        if {$includeSeparators} {
            lappend fieldsAndSeps \
                    [string range $str $matchStart $matchEnd]
        }
        set offset [expr {$matchEnd + 1}]
    }
    # Handle the remainder of $str after all the separators.
    set tail [string range $str $offset end]
    if {$tail eq {}} {
        # $str ended on a separator.
        if {!$includeSeparators} {
            lappend fieldsAndSeps {}
        }
    } else {
        lappend fieldsAndSeps $tail
        if {$includeSeparators} {
            lappend fieldsAndSeps {}
        }
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

# Return a list of columns.
# The format of $fieldsAndSeps is {field1 sep1 field2 sep2 ...}.
# The format of $fieldMap is {range1 range2 ... rangeN ?"auto"?}.
# For each field range in $fieldMap add an item to the list that consists of
# the merged contents of the fields in $fieldsAndSeps that fall into this range.
# E.g., for the range {1 5} an item with the contents of fields 1 through 5 (and
# the separators between them) will be added. The string "auto" as rangeN in
# $fieldMap causes [map] to add one column per field for every field in
# $fieldsAndSeps starting with fieldN and then return immediately.
proc ::sqawk::parsers::awk::map {fieldsAndSeps fieldMap} {
    set columns {}
    set currentColumn 0
    foreach mapping $fieldMap {
        if {$mapping eq {auto}} {
            foreach {field _} \
                    [lrange $fieldsAndSeps [expr {$currentColumn*2}] end] {
                lappend columns $field
            }
            break
        } elseif {[regexp {^[0-9]+\s+(?:end|[0-9]+)$} $mapping]} {
            lassign $mapping from to
            set from [expr {($from - 1)*2}]
            if {$to ne {end}} {
                set to [expr {($to - 1)*2}]
            }
            lappend columns [join [lrange $fieldsAndSeps $from $to] {}]
        } else {
            error "unknown mapping: \"$mapping\""
        }

        incr currentColumn
    }

    return $columns
}

# Parse a string like 1,2,3-5,auto into a list where each item is either a
# field range or the string "auto".
proc ::sqawk::parsers::awk::parseFieldMap fields {
    set itemRegExp {(auto|([0-9]+)(?:-(end|[0-9]+))?)}
    set ranges {}
    set start 0
    set length [string length $fields]
    while {($start < $length - 1) &&
            [regexp -indices -start $start ${itemRegExp}(,|$) $fields \
                    overall item rangeFrom rangeTo]} {
        set item [string range $fields {*}$item]

        if {$item eq {auto}} {
            lappend ranges auto
        } elseif {[string is integer -strict $item]} {
            lappend ranges [list $item $item]
        } elseif {($rangeFrom ne {-1 -1}) && ($rangeTo ne {-1 -1})} {
            lappend ranges [list \
                    [string range $fields {*}$rangeFrom] \
                    [string range $fields {*}$rangeTo]]
        } else {
            error "can't parse item \"$item\""
        }
        lassign $overall _ start
    }
    return $ranges
}

# Convert raw text data into a list of database rows using regular
# expressions.
::snit::type ::sqawk::parsers::awk::parser {
    variable RS
    variable FS
    variable fieldMap
    variable trim

    variable ch
    variable len
    variable offset 0
    variable buf {}

    variable step [expr {1024 * 1024}]

    constructor {channel options} {
        set ch $channel

        set RS [dict get $options RS]
        set FS [dict get $options FS]
        set fieldMap [::sqawk::parsers::awk::parseFieldMap \
                [dict get $options fields]]
        set trim [dict get $options trim]

        # Thanks to KBK for the idea.
        if {[regexp $RS {}]} {
            error "splitting on RS regexp \"$RS\" would cause infinite loop"
        }
        if {[regexp $FS {}]} {
            error "splitting on FS regexp \"$FS\" would cause infinite loop"
        }
    }

    method next {} {
        # Truncate the buffer.
        if {$offset >= $step} {
            set buf [string range $buf $offset end]
            set offset 0
        }
        # Fill up the buffer until we have at least one record.
        while {!([set regExpMatched \
                        [regexp -start $offset -indices -- $RS $buf match]]
                || [eof $ch])} {
            append buf [read $ch $step]
        }
        set len [string length $buf]
        if {$regExpMatched} {
            lassign $match matchStart matchEnd
            set record [string range $buf $offset [expr {$matchStart - 1}]]
            set offset [expr {$matchEnd + 1}]
        } elseif {$offset < $len} {
            set record [string range $buf $offset end]
            set offset $len
        } else {
            return -code break {}
        }

        set record [::sqawk::parsers::awk::trim-record $record $trim]

        if {($fieldMap eq {auto})} {
            return [list \
                    $record {*}[::sqawk::parsers::awk::sepsplit $record $FS 0]]
        } else {
            set columns [::sqawk::parsers::awk::map \
                    [::sqawk::parsers::awk::sepsplit $record $FS] \
                    $fieldMap]
            return [list $record {*}$columns]
        }
    }
}
