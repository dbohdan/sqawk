#!/bin/sh
if ! dpkg -s tcl >/dev/null \
    && dpkg -s tcllib >/dev/null \
    && dpkg -s libsqlite3-tcl >/dev/null; then
  sudo apt-get update
  sudo apt-get -y install tclsh tcllib libsqlite3-tcl
fi

mkdir -p /opt
rm -rf /opt/sqawk
cp -r /sqawk /opt/sqawk
cd /opt/sqawk
make
sudo make install
