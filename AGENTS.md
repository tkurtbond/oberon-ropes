# AGENTS.md

Working notes for an agent in this repo, which holds Oberon-2 utility
programs and modules built with voc (Vishap Oberon). Most of what
follows is about `Rope.Mod`, `RopeTest.Mod` and `RopeTool.Mod`. Those
modules are the model for the Ada port at `~/Repos/Ada/Ropes`, and
several of that port's additions have been ported back here. Its
`PLAN.md` has a full entry for each backport: Phases 9, 10, 12, 14
and 26.

## Build / test

```sh
make                 # every program, with voc
make test            # build, then run tests/*.test; ends "N ok, M failed"
tests/run-tests.sh -o rope-hash rope-count   # selected fixtures, with their real output
```

- The `GNUmakefile` builds a library module with `voc -f -s` and a
  program with `voc -f -m`.
- A new module that a program imports needs a `Program: Module.o` line
  in the `GNUmakefile`, as `RopeTool RopeTest: Rope.o` does.
- A new program goes in `PROGRAMS` and in `.gitignore`.
- `pocGNUmakefile` builds some of the programs with poc into
  `poc-build/`. See its header for why the build goes there. The
  `Rope*` modules are voc-only, and poc doesn't build them.
- **`RopeTest` is the in-process check battery**, printing `ok -` or
  `not ok -` per check and then `N/M tests passed.`.
  `tests/rope-selftest.test` runs it and holds the full check list.
- **Fixtures**: `tests/NAME.test` has the lines `program`, `arg`
  (repeatable; a bare `arg` is an empty argument), optional `env`,
  `dir` and `input`, then `status`, and `output` followed by the
  expected text. Standard output and standard error are compared
  mixed together. The harness ignores trailing white space and voc's
  `Terminated by Halt(N).` lines.
- **Regenerate fixtures from real runs; never hand-edit one that
  embeds generated text.** `rope-selftest.test` embeds the check list,
  and `rope-help.test` and `rope-unknown-command.test` embed
  `RopeTool`'s usage text. Adding a check or a command means
  regenerating all three that apply.
- **Build fixture argument lists in Python (`subprocess` with a list),
  not with a shell `eval`**, which collapses spaces inside quoted
  arguments.

## voc facts that have bitten

Each of these was confirmed with a test program, not taken from
documentation.

- **`LONGINT` is 32 bits and signed, and overflow wraps silently**,
  even with `-r`. Guard any sum that could overflow:
  - `AddLen` HALTs rather than wrapping.
  - Write bounds checks as `len > Length(r) - start`, not
    `start + len > Length(r)`, which wraps negative and passes
    (commit `377d6a7`).
  - Use `HUGEINT` (64 bits) for values that need more, as `Hash` does.
  - `MaxDepth = 44` is derived from `LONGINT`'s width.
- **`SET` holds only 0 .. 31 (`MAX(SET)`)**, so a set of characters
  is a record, `CharSet` (`has: ARRAY 256 OF BOOLEAN`), not a `SET`.
- **`Out` never flushes at program exit.** Output after the last line
  feed is lost unless you call `Out.Flush`, which `Rope.Write` does.
- **`Out.String` stops at the first 0X.** Leaves have no terminator
  and may contain 0X, so write them with `Out.Char` or
  `Files.WriteBytes`.
- **A voc runtime trap (an index out of range, or a NIL dereference)
  exits with status 254 (`Halt(-2)`)**, and is distinct from a
  module's own `HALT(1)`. A fixture's `status` line tells them apart.
- **A procedure must be declared before it is used**. There are no
  forward calls without a `^` forward declaration, so a shared helper
  such as `LowerChar` goes above its first caller.
- **Assigning a record containing a `POINTER TO ARRAY` shares the
  array.** It does not copy it. `LeafWalk`'s stack is one, so a search
  that tries a crossing match on a copy of the walk must use
  `CopyWalk`. Plain assignment corrupts the outer scan. (Ada's record
  copy was deep, so the Ada port has no equivalent.)
- A type-bound procedure called through a NIL receiver traps. The
  empty rope is NIL, so `Rope`'s operations are plain procedures
  (`Cat(a, b)`), never `a.Cat(b)`.

## `Rope.Mod` conventions

- **Positions are 0-based.**
- **Out-of-range arguments clamp.** They don't trap, except where a
  single character is addressed: `Fetch` and `ReplaceChar` HALT.
- **"Not found" is -1.**
- **Failure is a BOOLEAN result**: `ReadLine`, `ReadFile` and
  `MakeMapping` return FALSE where Ada would raise.
- **Callbacks are procedure types** such as `Visitor`, `ChunkVisitor`
  and `Mapper`, in place of Ada generics. A visitor returning FALSE
  stops the walk.
- **Nodes are immutable and built bottom-up.** The empty rope is NIL,
  and a Concat node's children are never empty.
- **Never walk a rope with a `Fetch` per character.** That costs
  O(n log n). Walk leaves with `LeafWalk`/`StartWalk`/`StartWalkAt`/
  `NextLeaf`, or with `IterateChunks`. Every search, `Compare`,
  `Blit`, `Escape` and `Hash` now does this.
- **I/O goes leaf by leaf, never through `ToString`.** `ToString`
  copies into a fixed `ARRAY OF CHAR` and silently truncates: an
  `ArgParser.MaxStringLength` buffer cut `RopeTool`'s output at 4095
  characters. `RopeTool` prints every rope with `Rope.Write`.
- **Rider-based I/O, not `Files.File`-based.** The Rider carries the
  position; a caller wanting to append calls `Files.Set` first.
- `Hash`/`HashNoCase` give exactly GNAT's `Ada.Strings.Hash` values,
  so both repos' `hash` fixtures agree. Case folding here is ASCII
  only.

## Porting from the Ada `Ropes` package

- **Translate the scenario, not the assertion.** Where Ada raises
  `Index_Error`, `Rope.Mod` clamps or returns -1. Positions shift from
  1-based to 0-based. A `Slice (Low, High)` becomes
  `(start, len)`.
- **Oberon has no overloading**, so an overload gets its own name,
  such as `ContainsPattern`, `CompareString` or `FindMapped`.
- **Skip what has no Oberon meaning.** That covers operators,
  `Unbounded_String` conversions and exception-only rules (Ada Phase
  20), and a `String` wrapper that would save only a `FromString`
  call. Record what wasn't ported and why, in the commit message and
  the Ada `PLAN.md`.
- Update `Rope.Mod`'s module comment, which lists what came from the
  Ada port.

## Testing lessons

- **Prove a new check can fail.** Plant the bug it targets and watch
  it fail. **Count a trap as caught**: look at the exit status, not
  only for `not ok` lines, because a planted bug often shows up as
  `Halt(-2)`.
- **Test several tree shapes.** Use left-deep, right-deep and
  `Balance`d trees built from leaves longer than `ShortLeafLength`,
  since shorter ones merge. A left-deep forward walk keeps only leaves
  on its stack, so the shared-stack `LeafWalk` bug was invisible on
  left-deep trees alone. Use text where failing partial matches are
  common, such as a run of `a`s.
- **Use a naive oracle.** Compare against a plain `Fetch` loop
  (`NaiveFind`, `NaiveCount` and the rest in `RopeTest.Mod`) across
  every position and length, not just a handful of hand-picked
  answers.
- **Check that every exported operation has a check.** `Iterate` once
  had none, although the `Iterator` type did.
- **Every exported operation should have a `RopeTool` command** where
  its arguments can be given as strings. Operations that take a
  procedure, such as `Map`, can't.
- **Fix a misleading comment when you spot it**, even in a file the
  current change doesn't otherwise touch.
