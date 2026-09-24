# A Rope Implementation for Oberon

`Rope.Mod` is a rope (a string represented as a tree of pieces) for
Oberon-2, built with voc (Vishap Oberon). `RopeTest.Mod` is its
in-process self-test, and `RopeTool.Mod` is a command-line demo with a
command for each exported operation.

`Rope.Mod` is the model for the Ada port,
[`Ropes`](https://github.com/tkurtbond/Ropes), and many of that port's
additions have been ported back here.

It moved here, with its history, from
[`oberon-tools`](https://github.com/tkurtbond/oberon-tools).
`ArgParser.Mod`, which `RopeTool` uses to parse its command line, is a
copy of the one there.

## Building and testing

```sh
make                 # build RopeTool and RopeTest with voc
make test            # build, then run the fixtures in tests/
```
