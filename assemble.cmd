@echo off
set tclsh=tclsh
if exist c:\Tcl\bin\tclsh.exe set tclsh=c:\Tcl\bin\tclsh.exe
%tclsh% tools/assemble.tcl sqawk-dev.tcl > sqawk.tcl
