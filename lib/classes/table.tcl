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

        set maxNF [$self cget -maxnf]
        set modeNF [$self cget -modenf]
        set curNF 0
        set insertColumnNames [list "${colPrefix}nf"]
        set insertValues [list {$nf}]

        set sub_rowInsertCommand {
            # prepare statement (column names / variables for binding):
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
            # expand (alter) table if needed:
            if {$modeNF eq "expand" && $nf - 1 > $maxNF} {
                for {set i $maxNF; incr i} {$i < $nf} {incr i} {
                  $db eval "ALTER TABLE $tableName ADD COLUMN [$self column-name $i] INTEGER"
                }
                $self configure -maxnf [set maxNF [incr i -1]]
            }
            set curNF $nf
            # create prepared statement (will be cached by "eval"):
            set stat [set rowInsertCommand($curNF) "
            INSERT INTO $tableName ([join $insertColumnNames ,])
            VALUES ([join $insertValues ,])
            "]
        }

        $db transaction {
            foreach row $rows {
                set nf [llength $row]
                # crop (truncate row) if needed:
                if {$modeNF eq "crop" && $nf >= $maxNF} {
                    set nf [llength [set row [lrange $row 0 $maxNF]]]
                }
                # first prepare or if current row contains more fields as created - alter table (expand columns):
                if {$nf != $curNF && [catch {set stat $rowInsertCommand($nf)}]} $sub_rowInsertCommand
                # bind - set fileds to variables array:
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
