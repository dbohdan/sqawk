test:
	tclsh tests.tcl
	sh ./examples/test.sh
install:
	cp sqawk.tcl /usr/local/bin/sqawk
	chmod +x /usr/local/bin/sqawk
