VOC=voc
VOCFLAGS=-f
VOCMAIN=-m

PROGRAMS=RopeTool RopeTest

.PHONY: all clean test test-verbose

all: $(PROGRAMS)

# RopeTool imports ArgParser, so it needs its symbol file (built along with
# ArgParser.o) and is rebuilt when it changes.
RopeTool: ArgParser.o

# RopeTool and RopeTest both import Rope, so they need its symbol file too.
RopeTool RopeTest: Rope.o


%: %.Mod
	$(VOC) $(VOCFLAGS) $(VOCMAIN) $<

%.o : %.Mod
	$(VOC) $(VOCFLAGS) -s $<


# Run the fixtures in tests/ against the programs and report how
# many passed and failed.  See tests/run-tests.sh for the fixture format.
test: all
	./tests/run-tests.sh

# Like test, but announces each test and its outcome as it goes.
test-verbose: all
	./tests/run-tests.sh -v

clean:
	-rm -fv $(PROGRAMS) *.c *.h *.o *.sym
	-rm -rfv *.dSYM
