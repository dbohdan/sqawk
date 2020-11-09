prefix      = /usr/local

exec_prefix = $(prefix)
bindir      = $(exec_prefix)/bin
datarootdir = $(prefix)/share
datadir     = $(datarootdir)
mandir      = $(datarootdir)/man
man1dir     = $(mandir)/man1

INSTALL         = install
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA    = $(INSTALL) -m 644

DESTDIR =

default: sqawk

install: installdirs
	$(INSTALL_PROGRAM) sqawk.tcl $(DESTDIR)$(bindir)/sqawk

installdirs:
	mkdir -p $(DESTDIR)$(bindir)

sqawk:
	tclsh tools/assemble.tcl sqawk-dev.tcl > sqawk.tcl
	chmod +x sqawk.tcl

test: sqawk
	tclsh tests.tcl

uninstall:
	rm $(DESTDIR)$(bindir)/sqawk

.PHONY: install installdirs sqawk test uninstall
