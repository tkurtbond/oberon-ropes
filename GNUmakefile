VOC=voc
VOCFLAGS=-f
VOCMAIN=-m

PROGRAMS=Simple Commands

.PHONY: all clean

all: $(PROGRAMS)

# The example programs all import ArgParser, so they need its symbol
# file (built along with ArgParser.o) and are rebuilt when it changes.
$(PROGRAMS): ArgParser.o


%: %.Mod
	$(VOC) $(VOCFLAGS) $(VOCMAIN) $<

%.o : %.Mod
	$(VOC) $(VOCFLAGS) -s $<


clean:
	-rm -fv $(PROGRAMS) *.c *.h *.o *.sym
	-rm -rfv *.dSYM
