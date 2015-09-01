#!/bin/sh
set -e

is_installed() {
  dpkg-query -Wf'${db:Status-abbrev}' "$1" 2>/dev/null | grep -q '^i'
}

# Install the Tcl packages if needed.
if ! is_installed tcl || ! is_installed tcllib || ! is_installed libsqlite3-tcl
then
  apt-get update
  apt-get -y install tclsh tcllib libsqlite3-tcl
fi

# Install or reinstall Sqawk.
rm -rf /tmp/sqawk
cp -r /sqawk /tmp/sqawk
cd /tmp/sqawk
make test
make install

# Check if Sqawk works and reports its version correctly.
reported_version="$(sqawk -v)"
source_version="$(awk '/version/{print $3}' /tmp/sqawk/sqawk.tcl | head -n 1)"

if test "$reported_version" = "$source_version"
then
  echo "Sqawk version: $reported_version"
else
  echo "error: reported version doesn't match source code version:"
  echo "\"$reported_version\" != \"$source_version\""
  exit 1
fi
