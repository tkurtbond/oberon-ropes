VOC=voc
VOCFLAGS=-f
VOCMAIN=-m

# Modules shared between repos, such as ArgParser.Mod, are in the
# directories in OBERON_MODULES (separated by colons), not here.  make
# finds them through vpath, and voc writes their .sym, .c, .h and .o files
# here, next to the programs that import them.  A .Mod here overrides one
# there.
OBERON_MODULES ?= /usr/local/sw/versions/oberon/include
vpath %.Mod $(OBERON_MODULES)

# make install copies Ropes.Mod to the first directory in OBERON_MODULES, so
# other repos can use it the same way.
INSTALLDIR = $(firstword $(subst :, ,$(OBERON_MODULES)))
MODULES = Ropes.Mod

# Only the programs need ArgParser, and Err, which ArgParser uses and the
# ArgParser repo installs with it, so clean, install and uninstall don't
# check for them.
SHARED_MODULES = ArgParser.Mod Err.Mod
ifneq ($(if $(MAKECMDGOALS),$(filter-out clean install uninstall,$(MAKECMDGOALS)),all),)
$(foreach m,$(SHARED_MODULES),$(if $(wildcard $(addsuffix /$(m),$(subst :, ,$(OBERON_MODULES)))),,$(error $(m) is not in OBERON_MODULES ($(OBERON_MODULES)); run make install in ~/Repos/Oberon/ArgParser)))
endif

PROGRAMS=RopeTool RopeTest

.PHONY: all clean test test-verbose install uninstall

all: $(PROGRAMS)

# RopeTool imports ArgParser, so it needs its symbol file (built along with
# ArgParser.o) and is rebuilt when it changes.
RopeTool: ArgParser.o

# ArgParser writes its errors to standard error with Err.
ArgParser.o: Err.o

# RopeTool and RopeTest both import Ropes, so they need its symbol file too.
RopeTool RopeTest: Ropes.o


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

# Install only a module that compiles.
install: $(MODULES:.Mod=.o)
	install -d $(INSTALLDIR)
	install -m 644 $(MODULES) $(INSTALLDIR)

# Remove what make install copied, and only that.
uninstall:
	rm -f $(addprefix $(INSTALLDIR)/,$(MODULES))

clean:
	-rm -fv $(PROGRAMS) *.c *.h *.o *.sym
	-rm -rfv *.dSYM
