![A squawk](squawk.jpg)

[![Travis CI build status](https://travis-ci.org/dbohdan/sqawk.svg?branch=master)](https://travis-ci.org/dbohdan/sqawk)
[![AppVeyor CI build status](https://ci.appveyor.com/api/projects/status/github/dbohdan/sqawk?branch=master&svg=true)](https://ci.appveyor.com/project/dbohdan/sqawk)

**Sqawk** is an [Awk](http://awk.info/)-like program that uses SQL and can combine data from multiple files. It is powered by SQLite.


# An example

Sqawk is invoked as follows:

    sqawk -foo bar script baz=qux filename
    
where the `script` is your SQL.

Here is an example of what it can do:

```sh
# List all login shells used on the system.
sqawk -ORS '\n' 'select distinct shell from passwd order by shell' FS=: columns=username,password,uid,gui,info,home,shell table=passwd /etc/passwd
```

or, equivalently,

```sh
# Do the same thing.
sqawk 'select distinct a7 from a order by a7' FS=: /etc/passwd
```

Sqawk lets you be verbose to better document your script but aims to provide good defaults that save you keystrokes in interactive use.

[Skip down](#more-examples) for more examples.


# Installation

Sqawk requires Tcl 8.5 or newer, Tcllib, and SQLite version 3 bindings for Tcl installed.

To install these dependencies on **Debian** and **Ubuntu** run the following command:

    sudo apt-get install tcl tcllib libsqlite3-tcl

On **Fedora**, **RHEL**, and **CentOS**:

    su -
    yum install tcl tcllib sqlite-tcl

On **FreeBSD** with [pkgng](https://wiki.freebsd.org/pkgng):

    sudo pkg install tcl86 tcllib tcl-sqlite3
    sudo ln -s /usr/local/bin/tclsh8.6 /usr/local/bin/tclsh

On **Windows** install [Magicsplat Tcl/Tk for Windows](http://www.magicsplat.com/tcl-installer/) (Windows 7 or later) or [ActiveTcl](https://www.activestate.com/activetcl/downloads) 8.5 from ActiveState (Windows XP/Vista).

On **macOS** use [MacPorts](https://www.macports.org/) or install [ActiveTcl](https://www.activestate.com/activetcl/downloads) for the Mac. With MacPorts:

    sudo port install tcllib tcl-sqlite3

Once you have the dependencies installed on \*nix, run

    git clone https://github.com/dbohdan/sqawk
    cd sqawk
    make
    make test
    sudo make install

or on Windows,

    git clone https://github.com/dbohdan/sqawk
    cd sqawk
    assemble.cmd
    tclsh tests.tcl


# Usage

`sqawk [globaloptions] script [option=value ...] < filename`

or

`sqawk [globaloptions] script [option=value ...] filename1 [[option=value ...] filename2 ...]`

One of the filenames can be `-` for the standard input.

## SQL

A Sqawk `script` consists of one or more statements in the SQLite version 3 [dialect](https://www.sqlite.org/lang.html) of SQL.

The default table names are `a` for the first input file, `b` for the second, `c` for the third, etc. You can change the table name for any file with a [file option](#per-file-options). The table name is used as a prefix in its columns' names; by default, the columns are named `a1`, `a2`, etc. in the table `a`; `b1`, `b2`, etc. in `b`; and so on. `a0` is the raw input text of the whole record for each record (i.e., one line of input with the default record separator of `\n`). `anr` in `a`, `bnr` in `b`, and so on contains the record number and is the primary key of its respective table. `anf`, `bnf`, and so on contain the field count for a given record.

## Options

### Global options

These options affect all files.

| Option | Example | Comment |
|--------|---------|---------|
| -FS value | `-FS '[ \t]+'` | The input field separator regular expression for the default `awk` parser (for all input files). |
| -RS value | `-RS '\n'` | The input record separator regular expression for the default `awk` parser (for all input files). |
| -OFS value | `-OFS ' '` | The output field separator string for the default `awk` serializer. |
| -ORS value | `-ORS '\n'` | The output record separator string for the default `awk` serializer. |
| -NF value | `-NF 10` | The maximum number of fields per record. The corresponding number of columns is added to the target table at the start (e.g., `a0`, `a1`, `a2`,&nbsp;...&nbsp;, `a10` for ten fields). Increase this if you get errors like `table x has no column named x51` with `MNF` set to `error`. |
| -MNF value | `-MNF expand`, `-MNF crop`, `-MNF error` | The NF mode. This option tells Sqawk what to do if a record exceeds the maximum number of fields: `expand`, the default, will increase `NF` automatically and add columns to the table during import if the record contains more fields than available; `crop` will truncate the record to `NF` fields (i.e., the fields for which there aren't enough table columns will be omitted); `error` makes Sqawk quit with an error message like `table x has no column named x11`. |
| -dbfile value | `-dbfile test.db` | The SQLite database file in which Sqawk will store the parsed data. Defaults to the special filename `:memory:`, which instructs SQLite to hold the data in RAM only. Using an actual file instead of `:memory:` is slower, but makes it possible to process larger datasets. The database file is opened if it exists and created if it doesn't. Once created by Sqawk, the file can be opened in other applications including the [sqlite3 CLI](https://sqlite.org/cli.html). If you run Sqawk more than once with the same database file it will reuse the table names each time it is run, i.e., by default it will use `a` for the first input source, `b` for the second, etc. For example, `sqawk -dbfile test.db 'select 0' foo; sqawk -dbfile test.db 'select 1' bar` will insert the data from both `foo` and `bar` into the table `a` in `test.db`; you can avoid this with `sqawk -dbfile test.db 'select 0' table=foo foo; sqawk -dbfile test.db 'select 1' table=bar bar`. If it is what you want, however, you can insert the data from both files into the same table in one invocation: `sqawk 'select * from a' foo table=a bar`. |
| -noinput | `-noinput` | Do not read from the standard input if Sqawk is given no filename arguments. |
| -output value | `-output awk` | The output format. See [Output formats](#output-formats). |
| -v | | Print the Sqawk version and exit. |
| -1 | | Do not split records into fields. The same as `-FS 'x^'` (`x^` is a regular expression that matches nothing). Improves the performance somewhat for when you only want to operate on whole records (lines). |

#### Output formats

The following are the possible values for the command line option `-output`. Some formats have format options to further customize the output. The options are appended to the format name and separated from the format name and each other with commas, e.g., `-output json,arrays=0,indent=1`.

| Format name | Format options | Examples | Comment |
|-------------|----------------|----------|---------|
| awk | none | `-output awk` | The default serializer, `awk`, mimics its namesake, Awk. When it is selected, the output consists of the rows returned by your query separated with the output record separator (-ORS). Each row in turn consists of columns separated with the output field separator (-OFS). |
| csv | none | `-output csv` | Output CSV. |
| json | `arrays` (defaults to `0`), `indent` (defaults to `0`) | `-output json,indent=0,arrays=1` | Output the result of the query as JSON. If `arrays` is `0`, the result is an array of JSON objects with the column names as keys; if `arrays` is `1`, the result is an array of arrays. The values are all represented as strings in either case. If `indent` is `1`, each object (but not array) will be indented for readability. |
| table | `alignments` or `align`, `margins`, `style` | `-output table,align=center left right`, `-output table,alignments=c l r` | Output plain text tables. The `table` serializer uses [Tabulate](https://wiki.tcl-lang.org/41682) to format the output as a table using box-drawing characters. Note that the default Unicode table output will not display correctly in `cmd.exe` on Windows even after `chcp 65001`. Use `style=loFi` to draw tables with plain ASCII characters instead. |
| tcl | `dicts` (defaults to `0`) | `-output tcl,dicts=1` | Dump raw Tcl data structures. With the `tcl` serializer Sqawk outputs a list of lists if `dicts` is `0` and a list of dictionaries with the column names as keys if `dicts` is `1`. |

### Per-file options

These options are set before a filename and only affect one input source (file).

| Option | Example | Comment |
|--------|---------|---------|
| columns | `columns=id,name,sum`, `columns=id,a long name with spaces` | Give custom names to the table columns for the next file. If there are more columns than custom names, the columns after the last one with a custom name will be named automatically in the same manner as with the option `header=1` (see below). Custom column names override names taken from the header. If you give a column an empty name, it will be named automatically or will retain its name from the header. |
| datatypes | `datatypes=integer,real,text` | Set the [datatypes](https://www.sqlite.org/datatype3.html) for the columns, starting with the first (`a1` if your table is named `a`). The datatype for each column for which the datatype is not explicitly given is `INTEGER`. The datatype of `a0` is always `TEXT`. |
| format | `format=csv csvsep=;` | Set the input format for the next source of input. See [Input formats](#input-formats). |
| header | `header=1` | Can be `0`/`false`/`no`/`off` or `1`/`true`/`yes`/`on`. Use the first row of the file as a source of column names. If the first row has five fields, then the first five columns will have custom names, and all the following columns will have automatically generated names (e.g., `name`, `surname`, `title`, `office`, `phone`, `a6`, `a7`, ...). |
| prefix | `prefix=x` | The column name prefix in the table. Defaults to the table name. For example, with `table=foo` and `prefix=bar` you will have columns named `bar1`, `bar2`, `bar3`, etc. in the table `foo`. |
| table | `table=foo` | The table name. By default, the tables are named `a`, `b`, `c`, ... Specifying, e.g., `table=foo` for the second file only will result in the tables having the names `a`, `foo`, `c`, ... |
| F0 | `F0=no`, `F0=1` | Can be `0`/`false`/`no`/`off` or `1`/`true`/`yes`/`on`. Enable the zeroth column of the table that stores the input verbatim. Disabling this column lowers memory usage. |
| NF | `NF=20` | The same as the [global option](#global-options) -NF, but for one file (table). |
| MNF | `MNF=crop` | The same as the [global option](#global-options) -MNF, but for one file (table). |

#### Input formats

A format option (`format=x`) selects the input parser with which Sqawk will parse the next input source. Formats can have multiple synonymous names or multiple names that configure the parser in different ways. Selecting an input format can enable additional per-file options that only work for that format.

| Format | Additional options | Examples | Comment |
|--------|--------------------|--------- |---------|
| `awk` | `FS`, `RS`, `trim`, `fields` | `RS=\n`, `FS=:`, `trim=left`, `fields=1,2,3-5,auto` | The default input parser. Splits the input first into records then into fields using regular expressions. The options `FS` and `RS` work the same as -FS and -RS respectively, but only apply to one file. The option `trim` removes whitespace at the beginning of each line of input (`trim=left`), at its end (`trim=right`), both (`trim=both`), or neither (`trim=none`, default). The option `fields` configures how the fields of the input are mapped to the columns of the corresponding database table. This option lets you discard some of the fields, which can save memory, and to merge the contents of others. For example, `fields=1,2,3-5,auto` tells Sqawk to insert the contents of the first field into the column `a1` (assuming table `a`), the second field into `a2`, the third through the fifth field into `a3`, and the rest of the fields starting with the sixth into the columns `a4`, `a5`, and so on, one field per column. If you merge several fields, the whitespace between them is preserved. |
| `csv`, `csv2`, `csvalt` | `csvsep`, `csvquote` | `format=csv csvsep=, 'csvquote="'` | Parse the input as CSV. Using `format=csv2` or `format=csvalt` enables the [alternate mode](http://core.tcl.tk/tcllib/doc/trunk/embedded/www/tcllib/files/modules/csv/csv.html#section3) meant for parsing CSV files exported by Microsoft Excel. `csvsep` sets the field separator; it defaults to `,`. `csvquote` selects the character with which the fields that contain the field separator are quoted; it defaults to `"`. Note that some characters (e.g., numbers and most letters) can't be be used as `csvquote`. |
| `tcl` | `dicts` | `format=tcl dicts=true` | The value for `dicts` can be `0`/`false`/`no`/`off` or `1`/`true`/`yes`/`on`. The input is treated as a Tcl list of either lists (`dicts=0`, default) or dictionaries (`dicts=1`). When `dicts` is `0`, each list becomes a record and each of its elements a field. If the table for the input file is `a`, its column `a0` will contain the full list, `a1` will contain the first element, `a2` the second element, and so on. When `dicts` is `1`, the first record contains every unique key found in all of the dictionaries. It is intended for use with the [file option](#per-file-options) `header=1`. The keys are in the same order they are in the first dictionary of the input. (Tcl dictionaries are ordered.) If some keys that aren't in the first dictionary but are in the subsequent ones, they follow those that are in the first dictionary in alphabetical order. Records from the second on contain the input dictionaries' values. They are mapped to fields according to how the keys are mapping in the first record. |


# More examples

## Sum up numbers

    find . -iname '*.jpg' -type f -printf '%s\n' | sqawk 'select sum(a1)/1024.0/1024 from a'

## Line count

    sqawk -1 'select count(*) from a' < file.txt

## Find lines that match a pattern

    ls | sqawk -1 'select a0 from a where a0 like "%win%"'

## Shuffle lines

    sqawk -1 'select a1 from a order by random()' < file

## Pretty-print data as a table

    ps | sqawk -output table \
         'select a1,a2,a3,a4 from a' \
         trim=left \
         fields=1,2,3,4-end

### Sample output

```
┌─────┬─────┬────────┬───────────────┐
│ PID │ TTY │  TIME  │      CMD      │
├─────┼─────┼────────┼───────────────┤
│11476│pts/3│00:00:00│       ps      │
├─────┼─────┼────────┼───────────────┤
│11477│pts/3│00:00:00│tclkit-8.6.3-mk│
├─────┼─────┼────────┼───────────────┤
│20583│pts/3│00:00:02│      zsh      │
└─────┴─────┴────────┴───────────────┘
```

## Convert input to JSON objects


    ps a | sqawk -output json,indent=1 \
                 'select PID, TTY, STAT, TIME, COMMAND from a' \
                 trim=left \
                 fields=1,2,3,4,5-end \
                 header=1

### Sample output

```
[{
    "PID"     : "1171",
    "TTY"     : "tty7",
    "STAT"    : "Rsl+",
    "TIME"    : "191:10",
    "COMMAND" : "/usr/lib/xorg/Xorg -core :0 -seat seat0 -auth /var/run/lightdm/root/:0 -nolisten tcp vt7 -novtswitch"
},{
    "PID"     : "1631",
    "TTY"     : "tty1",
    "STAT"    : "Ss+",
    "TIME"    : "0:00",
    "COMMAND" : "/sbin/agetty --noclear tty1 linux"
}, <...>, {
    "PID"     : "26583",
    "TTY"     : "pts/1",
    "STAT"    : "R+",
    "TIME"    : "0:00",
    "COMMAND" : "ps a"
},{
    "PID"     : "26584",
    "TTY"     : "pts/1",
    "STAT"    : "R+",
    "TIME"    : "0:00",
    "COMMAND" : "tclsh /usr/local/bin/sqawk -output json,indent=1 select PID, TTY, STAT, TIME, COMMAND from a trim=left fields=1,2,3,4,5-end header=1"
}]
```

## Find duplicate lines

Print duplicate lines and how many times they are repeated.

    sqawk -1 -OFS ' -- ' 'select a0, count(*) from a group by a0 having count(*) > 1' < file

### Sample output

    13 -- 2
    16 -- 3
    83 -- 2
    100 -- 2

## Remove blank lines

    sqawk -1 -RS '[\n]+' 'select a0 from a' < file

## Sum up numbers with the same key

    sqawk -FS , -OFS , 'select a1, sum(a2) from a group by a1' data

This is the equivalent of the Awk code

    awk 'BEGIN {FS = OFS = ","} {s[$1] += $2} END {for (key in s) {print key, s[key]}}' data

### Input

```
1015,5
1015,4
1035,17
1035,11
1009,1
1009,4
1026,9
1004,5
1004,5
1009,1
```

### Output

```
1004,10
1009,6
1015,9
1026,9
1035,28
```

## Combine data from two files

### Commands

This example joins the data from two metadata files generated from the [happypenguin.com 2013 data dump](https://archive.org/details/happypenguin_xml_dump_2013). You do not need to download the data dump to try the query; `MD5SUMS` and `du-bytes` are included in the directory [`examples/hp/`](./examples/hp/).

    # Generate input files -- see below
    cd happypenguin_dump/screenshots
    md5sum * > MD5SUMS
    du -b * > du-bytes
    # Perform query
    sqawk 'select a1, b1, a2 from a inner join b on a2 = b2 where b1 < 10000 order by b1' MD5SUMS du-bytes

### Input files

#### MD5SUMS

```
d2e7d4d1c7587b40ef7e6637d8d777bc  0005.jpg
4e7cde72529efc40f58124f13b43e1d9  001.jpg
e2ab70817194584ab6fe2efc3d8987f6  0.0.6-settings.png
9d2cfea6e72d00553fb3d10cbd04f087  010_2.jpg
3df1ff762f1b38273ff2a158e3c1a6cf  0.10-planets.jpg
0be1582d861f9d047f4842624e7d01bb  012771602077.png
60638f91b399c78a8b2d969adeee16cc  014tiles.png
7e7a0b502cd4d63a7e1cda187b122b0b  017.jpg
[...]
```

#### du-bytes

```
136229  0005.jpg
112600  001.jpg
26651   0.0.6-settings.png
155579  010_2.jpg
41485   0.10-planets.jpg
2758972 012771602077.png
426774  014tiles.png
165354  017.jpg
[...]
```

### Output

```
d50700db41035eb74580decf83f83184 615 z81.png
e1b64d03caf4615d54e9022d5b13a22d 677 init.png
a0fb29411c169603748edcc02c0e86e6 823 agendaroids.gif
3b0c65213e121793d4458e09bb7b1f58 970 screen01.gif
05f89f23756e8ea4bc5379c841674a6e 999 retropong.png
a49a7b5ac5833ec365ed3cb7031d1d84 1458 fncpong.png
80616256c790c2a831583997a6214280 1516 el2_small.jpg
[...]
1c8a3cb2811e9c20572e8629c513326d 9852 7.png
c53a88c68b73f3c1632e3cdc7a0b4e49 9915 choosing_building.PNG
bf60508db16a92a46bbd4107f15730cd 9946 glad_shot01.jpg
```


# License

MIT.

`squawk.jpg` photograph by [Terry Foote](https://en.wikipedia.org/wiki/User:Terry_Foote) at [English Wikipedia](https://en.wikipedia.org/wiki/). It is licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).
