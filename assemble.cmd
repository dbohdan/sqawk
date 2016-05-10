@echo off
set tclsh=tclsh
if exist c:\Tcl\bin\tclsh.exe set tclsh=c:\Tcl\bin\tclsh.exe

rem Allow the user to override which Tcl binary we use.
set arg=%1%
if "%arg%"=="" goto do_assemble
if "%arg:~0,7%"=="/tclsh:" (
    set tclsh=%arg:~7%
)

:do_assemble
%tclsh% tools/assemble.tcl sqawk-dev.tcl > sqawk.tcl
