![A squawk](squawk.jpg)

**Sqawk** is an [Awk](http://awk.info/)-like program that can process multiple files at once and uses SQL syntax. It is powered by SQLite.

# Usage

    sqawk [options] query < filename

or

    sqawk [options] query filename1 [filename2 ...]

## Options

| Option | Example | Comment |
|--------|---------|---------|
| -FS value | `-FS '[ \t]+'` | Input field separator (one for all input files). |
| -RS value | `-RS '\n'` | Input record separator (one for all input files). |
| -FSx value | `-FSx '{,[ ]*} {[ \t]+}`' | A list of field separators with one for each input file. Each list item must be enclosed in `{...}`. |
| -RSx value | `-RSx '{\n} {\n}'` | A list of record separators with one for each input file. Each list item must be enclosed in `{...}`. |
| -OFS value | `-OFS ' '` | Output field separator. |
| -ORS value | `-ORS '\n'` | Output record separator. |
| -NF value | `-NF 10` | The maximum number of fields per record. Increase this if you get the error `table x has no column named x51`. |
| -v | | Print the Sqawk version and exit. |
| -1 | | Do not split records into fields. Same as `-F '^$'`. Allows you to avoid adjusting `-NF` and improves the performance somewhat for when you only want to operate on lines. |

## SQL

The table names are `a` for the first input file, `b` for the second, `c` for the third, etc. The table name is used as a prefix in its fields' names, e.g., the fields are named `a1`, `a2`, etc. in `a`, `b1`, `b2`, etc. in `b` and so on. `a0` is the raw input text of the whole record for each record (i.e., one line of input with the default record separator of `\n`). `anr` in `a`, `bnr` in `b` and so on contains the record number and is the primary key of its respective  table. `anf`, `bnf` and so on contains the field count for a given record.

# Examples

## Sum up numbers

    find . -iname '*.jpg' -type f -printf '%s\n' | sqawk 'select sum(a1)/1024/1024 from a'

## Line count

    sqawk -1 'select count(*) from a' < file.txt

## Find lines that match a pattern

    ls | sqawk -1 'select a0 from a where glob("*win*", lower(a0))'

## Shuffle lines

    sqawk -1 'select a1 from a order by random()' < file

## Find duplicate lines

Print them and how many times they are repeated.

    sqawk -1 -OFS ' -- ' 'select a0, count(*) from a group by a0 having count(*) > 1' < file

### Sample output

    13 -- 2
    16 -- 3
    83 -- 2
    100 -- 2

## Remove blank lines

    sqawk -1 -RS '[\n]+' 'select a0 from a' < file

## Combine data from two files

### Commands

This example uses metadata for the files from the [happypenguin.com 2013 data dump](https://archive.org/details/happypenguin_xml_dump_2013).

    # Generate input files -- see below
    cd happypenguin_dump/screenshots
    md5sum * > MD5SUMS
    ls -la > list
    # Perform query
    sqawk 'select a.a1, b.b5, a.a2 from a inner join b on a.a2 = b.b9 where b.b5 < 10000 order by b.b5' MD5SUMS list

You don't have to download the data yourself to generate `MD5SUMS` and `list`; the files  can be found in the directory `[examples/](./examples/)`.

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
1e958dfe8f99de90bb8a9520a0181f51  01newscreenie.jpeg
f56fb95efa84fbfdd8e01222b4a58029  02_characterselect.jpg
[...]
```

#### list

```
drwxr-xr-x. 2 dbohdan dbohdan   94208 Apr  7  2013 .
drwxr-xr-x. 4 dbohdan dbohdan    4096 Apr 14  2014 ..
-rw-r--r--. 1 dbohdan dbohdan  136229 Apr  7  2013 0005.jpg
-rw-r--r--. 1 dbohdan dbohdan  112600 Apr  7  2013 001.jpg
-rw-r--r--. 1 dbohdan dbohdan   26651 Apr  7  2013 0.0.6-settings.png
-rw-r--r--. 1 dbohdan dbohdan  155579 Apr  7  2013 010_2.jpg
-rw-r--r--. 1 dbohdan dbohdan   41485 Apr  7  2013 0.10-planets.jpg
-rw-r--r--. 1 dbohdan dbohdan 2758972 Apr  7  2013 012771602077.png
-rw-r--r--. 1 dbohdan dbohdan  426774 Apr  7  2013 014tiles.png
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
1eee29eaef2ae740d04ad4ee6d140db7 1575 thrust-0.89f.gif
19edfd5a70c9e029b9c601ccb17c4d12 1665 xrockman.png
4e1105deeeba96e7b935aa07e2066d89 1741 xroarsnap.png
[...]
```

# Installation

Sqawk requires Tcl 8.5 or newer, Tcllib and SQLite version 3 bindings for Tcl installed.

To install these dependencies on **Debian** and **Ubuntu** run the following command:

    sudo apt-get install tcl tcllib libsqlite3-tcl

On **Fedora**, **RHEL** and **CentOS**:

    su -
    yum install tcl tcllib sqlite-tcl

On **Windows** the easiest option is to install [ActiveTcl](http://www.activestate.com/activetcl/downloads) from ActiveState.

On **OS X** use [MacPorts](https://www.macports.org/) or install [ActiveTcl](http://www.activestate.com/activetcl/downloads) for Mac. With MacPorts:

    sudo port install tcllib tcl-sqlite3

Once you have the dependencies installed run

    git clone https://github.com/dbohdan/sqawk
    cd sqawk
    sh ./examples/test.sh
    sudo make install ;# install to /usr/local/bin (not on Windows)

# License

MIT.

`squawk.jpg` photograph by [Terry Foote](https://en.wikipedia.org/wiki/User:Terry_Foote) at [English Wikipedia](https://en.wikipedia.org/wiki/). It is licensed under [CC BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/).
