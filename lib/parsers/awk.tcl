# Sqawk, an SQL Awk.
# Copyright (C) 2015, 2016, 2017 dbohdan
# License: MIT

namespace eval ::sqawk::parsers::awk {
    variable formats {
        raw awk
    }
    variable options {
        FS {}
        RS {}
        fields auto
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
            foreach {field _} [lrange $fieldsAndSeps \
                    [expr {$currentColumn*2}] end] {
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
proc ::sqawk::parsers::awk::parse {data options} {
    # Parse $args.
    set RS [dict get $options RS]
    set FS [dict get $options FS]
    set fields [dict get $options fields]
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
    if {($fields eq {auto})} {
        foreach record $records {
            set record [::sqawk::parsers::awk::trim-record $record $trim]
            lappend rows [list $record {*}[::textutil::splitx $record $FS]]
        }
    } else {
        foreach record $records {
            set record [::sqawk::parsers::awk::trim-record $record $trim]
            set columns [::sqawk::parsers::awk::map \
                    [::sqawk::parsers::awk::sepsplit $record $FS] \
                    [::sqawk::parsers::awk::parseFieldMap $fields]]
            lappend rows [list $record {*}$columns]
        }
    }

    return $rows
}
