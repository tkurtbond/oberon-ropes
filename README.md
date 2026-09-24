# A Rope Implementation for Oberon

`Ropes.Mod` is a rope (a string represented as a tree of pieces) for
Oberon-2, built with voc (Vishap Oberon). `RopeTest.Mod` is its
in-process self-test, and `RopeTool.Mod` is a command-line demo with a
command for each exported operation.

`Ropes.Mod` is the model for the Ada port,
[`Ropes`](https://github.com/tkurtbond/Ropes), and many of that port's
additions have been ported back here.

It moved here, with its history, from
[`oberon-tools`](https://github.com/tkurtbond/oberon-tools).

## Building and testing

`RopeTool` uses `ArgParser.Mod` to parse its command line. It has its
own repo,
[`oberon-argparser`](https://github.com/tkurtbond/oberon-argparser),
where `make install` installs it, so it isn't here: the `GNUmakefile`
finds it in `OBERON_MODULES`, a colon-separated list of directories
(default `/usr/local/sw/versions/oberon/include`), and
builds it here along with the programs.

```sh
make                 # build RopeTool and RopeTest with voc
make test            # build, then run the fixtures in tests/
make install         # copy Ropes.Mod to OBERON_MODULES, for other repos
make uninstall       # remove it from OBERON_MODULES
```
