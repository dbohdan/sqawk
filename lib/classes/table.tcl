# Sqawk, an SQL Awk.
# Copyright (C) 2015 Danyil Bohdan
# License: MIT

namespace eval ::sqawk {}

# Creates and populates an SQLite3 table with a specific format.
::snit::type ::sqawk::table {
    option -database
    option -dbtable
    option -columnprefix
    option -maxnf
    option -modenf {}
    option -header {}
    option -datatypes {}

    destructor {
        [$self cget -database] eval "DROP TABLE [$self cget -dbtable]"
    }

    # Return the column name for column number $i, custom (if present) or
    # automatically generated.
    method column-name i {
        set customColName [lindex [$self cget -header] $i-1]
        if {($i > 0) && ($customColName ne "")} {
            return $customColName
        } else {
            return [$self cget -columnprefix]$i
        }
    }

    # Return the column datatype for column number $i, custom (if present) or
    # "INTEGER" otherwise.
    method column-datatype i {
        set customColDatatype [lindex [$self cget -datatypes] $i-1]
        if {$i == 0} {
            return TEXT
        } elseif {$customColDatatype ne ""} {
            return $customColDatatype
        } else {
            return INTEGER
        }
    }

    # Create a database table for the table object.
    method initialize {} {
        set fields {}
        set colPrefix [$self cget -columnprefix]
        set command {
            CREATE TABLE [$self cget -dbtable] (
                ${colPrefix}nr INTEGER PRIMARY KEY,
                ${colPrefix}nf INTEGER,
                [join $fields ","]
            )
        }
        set maxNF [$self cget -maxnf]
        for {set i 0} {$i <= $maxNF} {incr i} {
            lappend fields "[$self column-name $i] [$self column-datatype $i]"
        }
        [$self cget -database] eval [subst $command]
    }

    # Insert each row from the list $rows into the database table in a
    # transaction.
    method insert-rows rows {
        set db [$self cget -database]
        set colPrefix [$self cget -columnprefix]
        set tableName [$self cget -dbtable]

        set maxNF [$self cget -maxnf]
        set modeNF [$self cget -modenf]
        set curNF 0
        set insertColumnNames [list "${colPrefix}nf"]
        set insertValues [list {$nf}]

        $db transaction {
            foreach row $rows {
                set nf [llength $row]
                # Crop (truncate row) if needed.
                if {$modeNF eq "crop" && $nf >= $maxNF} {
                    set nf [llength [set row [lrange $row 0 $maxNF]]]
                }
                # Prepare the command. If the current row contains more fields
                # than exist alter the table adding columns.
                if {$nf != $curNF &&
                        [catch {set stat $rowInsertCommand($nf)}]} {
                    if {$curNF < $nf} {
                        set i $curNF
                        while {$i < $nf} {
                            lappend insertColumnNames [$self column-name $i]
                            lappend insertValues "\$cv($i)"
                            incr i
                        }
                    } else {
                        set insertColumnNames [lrange $insertColumnNames 0 $nf]
                        set insertValues [lrange $insertValues 0 $nf]
                    }
                    # Expand (alter) table if needed.
                    if {$modeNF eq "expand" && $nf - 1 > $maxNF} {
                        for {set i $maxNF; incr i} {$i < $nf} {incr i} {
                            $db eval "ALTER TABLE $tableName ADD COLUMN
                                    [$self column-name $i]
                                    [$self column-datatype $i]"
                        }
                        $self configure -maxnf [set maxNF [incr i -1]]
                    }
                    set curNF $nf
                    # Create a prepared statement (will be cached by "eval").
                    set stat [set rowInsertCommand($curNF) "
                    INSERT INTO $tableName ([join $insertColumnNames ,])
                    VALUES ([join $insertValues ,])
                    "]
                }
                # Puts fields into the array cv.
                set i 0
                foreach field $row {
                    set cv($i) $field
                    incr i
                }
                $db eval $stat
            }
        }
    }
}
