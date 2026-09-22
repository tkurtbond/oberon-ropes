VOC=voc
VOCFLAGS=-f
VOCMAIN=-m

PROGRAMS=Simple Commands OneName OModPath RopeTool RopeTest

.PHONY: all clean test test-verbose

all: $(PROGRAMS)

# All the example programs except RopeTest import ArgParser, so they need
# its symbol file (built along with ArgParser.o) and are rebuilt when it
# changes.
$(filter-out RopeTest,$(PROGRAMS)): ArgParser.o

# OModPath also writes to standard error, with Err, and tests whether files
# exist, with FileTest.  They are Err.Mod and FileTest.Mod here for voc, and
# poc-rtl/Err.Mod and poc-rtl/FileTest.Mod for poc.
OModPath: Err.o FileTest.o

# RopeTool and RopeTest both import Rope, so they need its symbol file too.
# Rope.Mod, RopeTool.Mod and RopeTest.Mod are voc-only for now: they are
# not built by pocGNUmakefile.
RopeTool RopeTest: Rope.o


%: %.Mod
	$(VOC) $(VOCFLAGS) $(VOCMAIN) $<

%.o : %.Mod
	$(VOC) $(VOCFLAGS) -s $<


# Run the fixtures in tests/ against the example programs and report how
# many passed and failed.  See tests/run-tests.sh for the fixture format.
test: all
	./tests/run-tests.sh

# Like test, but announces each test and its outcome as it goes.
test-verbose: all
	./tests/run-tests.sh -v

clean:
	-rm -fv $(PROGRAMS) *.c *.h *.o *.sym
	-rm -rfv *.dSYM
