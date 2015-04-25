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
    option -header {}

    destructor {
        [$self cget -database] eval "DROP TABLE [$self cget -dbtable]"
    }

    # Return column name for column number $i, custom (if present) or
    # automatically generated.
    method column-name i {
        set customColName [lindex [$self cget -header] $i-1]
        if {($i > 0) && ($customColName ne "")} {
            set colName $customColName
        } else {
            set colName [$self cget -columnprefix]$i
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
            lappend fields "[$self column-name $i] INTEGER"
        }
        [$self cget -database] eval [subst $command]
    }

    # Insert each row from the list $rows into the database table in a
    # transaction.
    method insert-rows rows {
        set db [$self cget -database]
        set colPrefix [$self cget -columnprefix]
        set tableName [$self cget -dbtable]

        set commands {}

        set rowInsertCommand {
            INSERT INTO $tableName ($insertColumnNames)
            VALUES ($insertValues)
        }

        set maxNF [$self cget -maxnf]
        for {set i 0} {$i <= $maxNF} {incr i} {
            set columnNames($i) [$self column-name $i]
        }

        $db transaction {
            foreach row $rows {
                set nf [llength $row]
                set insertColumnNames "${colPrefix}nf,${colPrefix}0"
                set insertValues {$nf,$row}
                if {$nf > 0} {
                    append insertColumnNames ,
                    append insertValues ,
                }
                set i 1
                foreach field $row {
                    set lastRow [expr { $i == $nf }]
                    set $columnNames($i) $field
                    append insertColumnNames $columnNames($i)
                    if {!$lastRow} {
                        append insertColumnNames ,
                    }
                    append insertValues "\$$columnNames($i)"
                    if {!$lastRow} {
                        append insertValues ,
                    }
                    incr i
                }
                $db eval [subst $rowInsertCommand]
            }
        }
    }
}
