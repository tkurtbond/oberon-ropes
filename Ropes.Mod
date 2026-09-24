MODULE Ropes;

(* An immutable "rope": a tree of concatenations of flat character leaves,
   giving cheap concatenation and substring operations that scale to long
   strings, unlike a flat character array.  Based on Boehm, Atkinson and
   Plass, "Ropes: an Alternative to Strings" (Software--Practice and
   Experience 25(12), 1315-1330, 1995), with two engineering choices taken
   from the same authors' C "cord" library in the Boehm-Demers-Weiser
   garbage collector (bdwgc/cord/cordbscs.c): the short-leaf merge
   optimization in Cat, and the Fibonacci-forest rebalancing algorithm.

   The empty rope is NIL; a Concat node's children are never empty.  Ropes
   are immutable: nothing here ever changes a node after it is built, so
   ropes may be freely shared.

   The exported operations are all plain procedures taking a Rope as an
   ordinary parameter (Cat(a, b), not a.Cat(b)): calling a type-bound
   procedure through a NIL receiver traps in Oberon-2, and NIL -- the empty
   rope -- is a normal, common value here that every operation must accept.

   This is a "core" rope: flat leaves and concatenation nodes only.  There
   are no lazy/function-generator leaves, no lazy substring nodes, and no
   file-backed ropes; Substring always copies.  (ReadAll and ReadFile, at
   the end, are not file-backed ropes: they read the whole file into
   memory at once, like cord's CORD_from_file_eager, not CORD_from_file's
   read-on-demand.)

   Input and output (Write, WriteRider, ReadLine, ReadLineRider, ReadAll,
   ReadFile, WriteFile, at the end) go leaf by leaf, never through one flat copy of the whole rope,
   so they are not limited the way ToString into a fixed ARRAY OF CHAR
   is.  They and IterateChunks were ported back from the Ada Ropes
   package (its Process_Chunks and Ropes.Text_IO), as was the linear
   Compare.

   So were, later, the operations the Ada port added to match
   Ada.Strings.Unbounded -- each translated into this module's own
   conventions (0-based positions, clamping rather than exceptions, -1
   for "not found", procedure types rather than generics): searches that
   walk leaves instead of a Fetch per character, so linear (Find, RFind,
   IndexChar, RIndexChar, and Split with them); CharSet with IndexSet,
   RIndexSet, CountSet and FindToken; IndexNonBlank/RIndexNonBlank;
   Count; Replace and ReplaceChar; Mapping with Translate; FindMapped,
   RFindMapped and CountMapped; CompareString/EqualString;
   CompareNoCase, EqualNoCase and HashNoCase; and Hash.

   This is voc-only for now: it is not built by pocGNUmakefile. *)

IMPORT Files, In, Out;

CONST
  (* Cat merges two flat leaves into one instead of adding a Concat node
     when their combined length is at most this.  Keeps a rope built by
     repeated single-character Cat/AppendChar calls from growing a deep,
     skinny tree.  Tunable; not derived from anything but taste. *)
  ShortLeafLength* = 16;

  (* The largest depth Cat lets a rope reach before rebalancing it.
     Derived so that minLength[MaxDepth] (see below) still fits in a
     LONGINT: voc's LONGINT is 32 bits wide (MAX(LONGINT) = 2147483647),
     and minLength[44] = 1836311903 is the last Fibonacci-like value under
     that; minLength[45] would overflow.  This is cord's CORD_MAX_DEPTH
     (48, derived the same way for a 64-bit size_t) scaled to LONGINT's
     width. *)
  MaxDepth* = 44;

  (* ReadLine/ReadLineRider read a line this many characters at a time,
     each full chunk becoming one leaf of the result, so a line of any
     length is read without one buffer as long as the whole line. *)
  LineChunk = 4096;

  (* ReadAll/ReadFile read a file this many bytes at a time, each full
     chunk becoming one leaf of the result -- not one leaf the size of the
     whole file, since Substring copies the parts of leaves it covers, so
     a one-leaf rope of a large file would make every later edit copy
     all of it. *)
  FileChunk = 4096;

TYPE
  Rope* = POINTER TO RopeDesc;
  RopeDesc* = RECORD
    length: LONGINT;
    depth: INTEGER
  END;

  (* A flat leaf.  chars holds exactly length characters; there is no
     capacity beyond that and no terminating 0X. *)
  Leaf = POINTER TO LeafDesc;
  LeafDesc = RECORD (RopeDesc)
    chars: POINTER TO ARRAY OF CHAR
  END;

  (* left and right are never NIL: an empty operand is always dropped by
     SimpleCat instead of ever appearing as a child. *)
  Concat = POINTER TO ConcatDesc;
  ConcatDesc = RECORD (RopeDesc)
    left, right: Rope
  END;

  (* Called by Iterate for each character, left to right; returning FALSE
     stops the iteration early. *)
  Visitor* = PROCEDURE (ch: CHAR): BOOLEAN;

  (* Called by Map for each character; returns the character to put in
     its place. *)
  Mapper* = PROCEDURE (ch: CHAR): CHAR;

  (* Called by Mapi for each character, together with its index. *)
  IndexedMapper* = PROCEDURE (i: LONGINT; ch: CHAR): CHAR;

  (* Called by Split for each piece, left to right; returning FALSE stops
     the splitting early. *)
  Visitor2* = PROCEDURE (piece: Rope): BOOLEAN;

  (* Called by IterateChunks for each leaf, left to right, with that
     leaf's characters: all LEN(chunk) of them -- there is no 0X
     terminator, and a chunk may itself contain 0X characters.  chunk is
     the leaf's own storage, passed VAR only so that it is not copied: it
     must not be modified, since ropes are immutable and may be shared.
     Returning FALSE stops the iteration early. *)
  ChunkVisitor* = PROCEDURE (VAR chunk: ARRAY OF CHAR): BOOLEAN;

  (* A walk over a rope's leaves, one leaf per NextLeaf call, in
     amortized O(1) per leaf -- used by Compare, Hash and every search.
     Left to right if forward, else right to left.  A pre-order walk with
     an explicit stack of subtrees still to visit (the far child pushed
     first, so the near one comes off first).  The stack never holds more
     than depth + 1 entries, and every Concat's depth is set by
     NewConcat, so r.depth + 1 always suffices.  The stack is a pointer,
     so assigning one LeafWalk to another shares it: CopyWalk makes an
     independent copy. *)
  LeafWalk = RECORD
    stack: POINTER TO ARRAY OF Rope;
    top: LONGINT;
    forward: BOOLEAN
  END;

  (* A set of characters, for IndexSet, RIndexSet, CountSet and
     FindToken: has[ORD(ch)] is whether ch is in it.  Build one with
     MakeCharSet, or set has directly.  Ada's Ada.Strings.Maps.
     Character_Set, ported back from the Ada Ropes package; a record
     rather than an Oberon SET, which holds only 0 .. MAX(SET) (31 in
     voc). *)
  CharSet* = RECORD
    has*: ARRAY 256 OF BOOLEAN
  END;

  (* A character-to-character mapping, for Translate: to[ORD(ch)] is what
     ch maps to.  Build one with MakeMapping or IdentityMapping.  Ada's
     Ada.Strings.Maps.Character_Mapping; its function form is Mapper,
     above. *)
  Mapping* = RECORD
    to*: ARRAY 256 OF CHAR
  END;

  (* The result of SplitArray: one entry per piece, in order. *)
  Pieces* = POINTER TO ARRAY OF Rope;

  (* One node of the result of SplitList: a singly linked list of pieces,
     in order. *)
  Piece* = POINTER TO PieceDesc;
  PieceDesc* = RECORD
    rope*: Rope;
    next*: Piece
  END;

  (* A cursor for stepping through a rope by index.  Caches the leaf
     covering its current position, so repeated Get/Incr/Decr calls that
     stay within one leaf are O(1); only crossing into the next leaf costs
     Fetch's O(log(length r)).  See the Iterator section below. *)
  Iterator* = POINTER TO IteratorDesc;
  IteratorDesc* = RECORD
    r: Rope;
    pos: LONGINT;
    leaf: Leaf;
    leafStart: LONGINT  (* absolute index of leaf.chars[0] in r; only meaningful if leaf # NIL *)
  END;

VAR
  (* minLength[d] is the least total length a rope balanced (per the
     paper's definition: length(r) >= minLength[depth(r)]) at depth d may
     have.  Built once, below, from a Fibonacci-like recurrence. *)
  minLength: ARRAY MaxDepth + 1 OF LONGINT;

PROCEDURE InitMinLength;
  VAR d: INTEGER;
BEGIN
  minLength[0] := 1;
  minLength[1] := 2;
  FOR d := 2 TO MaxDepth DO minLength[d] := minLength[d - 1] + minLength[d - 2] END
END InitMinLength;

PROCEDURE MaxInt(a, b: INTEGER): INTEGER;
BEGIN
  IF a > b THEN RETURN a END;
  RETURN b
END MaxInt;

(* a + b, or a HALT if that would overflow LONGINT.  a and b must both be
   >= 0 (true of every rope length), so overflow is exactly a > MAX(LONGINT)
   - b; testing it this way, instead of computing a + b and checking the
   result, never itself overflows.  voc does not trap plain LONGINT
   overflow -- it silently wraps, like C's int32_t -- so every place a
   Rope's length is computed from its parts goes through this instead of
   "+" directly. *)
PROCEDURE AddLen(a, b: LONGINT): LONGINT;
BEGIN
  IF a > MAX(LONGINT) - b THEN HALT(1) END;
  RETURN a + b
END AddLen;

(* The length of s up to its terminating 0X, or LEN(s) if it has none. *)
PROCEDURE StrLen(s: ARRAY OF CHAR): LONGINT;
  VAR len: LONGINT;
BEGIN
  len := 0;
  WHILE (len < LEN(s)) & (s[len] # 0X) DO INC(len) END;
  RETURN len
END StrLen;

(* ch uppercased if it is an ASCII lowercase letter, lowercased if an
   ASCII uppercase one; any other character unchanged.  Mappers, as
   UppercaseAscii and LowercaseAscii pass them to Map; exported (since
   the Ada Ropes package's Mapping searches were ported back) so that a
   case-insensitive FindMapped needs no mapper of its own. *)
PROCEDURE UpperChar*(ch: CHAR): CHAR;
BEGIN
  IF (ch >= "a") & (ch <= "z") THEN RETURN CAP(ch) END;
  RETURN ch
END UpperChar;

PROCEDURE LowerChar*(ch: CHAR): CHAR;
BEGIN
  IF (ch >= "A") & (ch <= "Z") THEN RETURN CHR(ORD(ch) + 32) END;
  RETURN ch
END LowerChar;

(* A new leaf copying src[start .. start + len - 1].  len must be > 0. *)
PROCEDURE NewLeaf(src: ARRAY OF CHAR; start, len: LONGINT): Leaf;
  VAR leaf: Leaf; i: LONGINT;
BEGIN
  NEW(leaf);
  NEW(leaf.chars, len);
  FOR i := 0 TO len - 1 DO leaf.chars[i] := src[start + i] END;
  leaf.length := len;
  leaf.depth := 0;
  RETURN leaf
END NewLeaf;

PROCEDURE MergeLeaves(a, b: Leaf): Leaf;
  VAR leaf: Leaf; i, n: LONGINT;
BEGIN
  NEW(leaf);
  n := AddLen(a.length, b.length);
  NEW(leaf.chars, n);
  FOR i := 0 TO a.length - 1 DO leaf.chars[i] := a.chars[i] END;
  FOR i := 0 TO b.length - 1 DO leaf.chars[a.length + i] := b.chars[i] END;
  leaf.length := n;
  leaf.depth := 0;
  RETURN leaf
END MergeLeaves;

(* left and right must both be non-NIL. *)
PROCEDURE NewConcat(left, right: Rope): Concat;
  VAR c: Concat;
BEGIN
  NEW(c);
  c.left := left;
  c.right := right;
  c.length := AddLen(left.length, right.length);
  c.depth := MaxInt(left.depth, right.depth) + 1;
  RETURN c
END NewConcat;

(* Plain concatenation: the short-leaf merge special cases from the paper,
   with no depth check and no rebalancing -- that is Cat's job, below.
   Balance also uses this directly, to combine forest slots, since its own
   algorithm already bounds the result's depth without Cat's check. *)
PROCEDURE SimpleCat(left, right: Rope): Rope;
  VAR lc: Concat;
BEGIN
  IF left = NIL THEN RETURN right END;
  IF right = NIL THEN RETURN left END;
  IF (left IS Leaf) & (right IS Leaf) & (AddLen(left.length, right.length) <= ShortLeafLength) THEN
    RETURN MergeLeaves(left(Leaf), right(Leaf))
  END;
  IF (left IS Concat) & (right IS Leaf) THEN
    lc := left(Concat);
    IF (lc.right IS Leaf) & (AddLen(lc.right.length, right.length) <= ShortLeafLength) THEN
      RETURN NewConcat(lc.left, MergeLeaves(lc.right(Leaf), right(Leaf)))
    END
  END;
  RETURN NewConcat(left, right)
END SimpleCat;

PROCEDURE Length*(r: Rope): LONGINT;
BEGIN
  IF r = NIL THEN RETURN 0 END;
  RETURN r.length
END Length;

PROCEDURE IsEmpty*(r: Rope): BOOLEAN;
BEGIN
  RETURN r = NIL
END IsEmpty;

PROCEDURE Depth*(r: Rope): INTEGER;
BEGIN
  IF r = NIL THEN RETURN 0 END;
  RETURN r.depth
END Depth;

(* Precondition: 0 <= i < Length(r).  Traps (HALT) if violated. *)
PROCEDURE Fetch*(r: Rope; i: LONGINT): CHAR;
  VAR c: Concat;
BEGIN
  IF (r = NIL) OR (i < 0) OR (i >= r.length) THEN HALT(1) END;
  IF r IS Leaf THEN RETURN r(Leaf).chars[i] END;
  c := r(Concat);
  IF i < c.left.length THEN RETURN Fetch(c.left, i) END;
  RETURN Fetch(c.right, i - c.left.length)
END Fetch;

PROCEDURE^ Balance*(r: Rope): Rope;

(* SimpleCat, then rebalance if the result got too deep.  This is the only
   place rebalancing is triggered automatically. *)
PROCEDURE Cat*(left, right: Rope): Rope;
  VAR result: Rope;
BEGIN
  result := SimpleCat(left, right);
  IF (result # NIL) & (result.depth >= MaxDepth) THEN result := Balance(result) END;
  RETURN result
END Cat;

(* A rope consisting of the single character ch. *)
PROCEDURE FromChar*(ch: CHAR): Rope;
  VAR one: ARRAY 1 OF CHAR;
BEGIN
  one[0] := ch;
  RETURN NewLeaf(one, 0, 1)
END FromChar;

(* Still benefits from SimpleCat's short-leaf merge, so appending one
   character at a time in a loop does not grow an ever-deeper tree. *)
PROCEDURE AppendChar*(r: Rope; ch: CHAR): Rope;
BEGIN
  RETURN Cat(r, FromChar(ch))
END AppendChar;

(* Whether r is balanced per the paper's definition: length(r) >=
   minLength[depth(r)].  A depth beyond MaxDepth (which Cat guarantees
   never persists past the next Cat it is involved in) is simply reported
   as unbalanced, rather than indexing minLength out of range. *)
PROCEDURE IsBalanced*(r: Rope): BOOLEAN;
BEGIN
  IF r = NIL THEN RETURN TRUE END;
  IF r.depth > MaxDepth THEN RETURN FALSE END;
  RETURN r.length >= minLength[r.depth]
END IsBalanced;

(* --- Balance: the Fibonacci "forest" rebalancing algorithm --- *)

(* Insert the leaf or already-balanced subtree x (of known length xLen)
   into the forest, maintaining the invariant that forest[i], if occupied,
   has depth <= i and length >= minLength[i], and that concatenating the
   occupied slots (see ConcatForest) reproduces what has been inserted so
   far, left to right. *)
PROCEDURE BalanceInsert(x: Rope; xLen: LONGINT; VAR forest: ARRAY OF Rope; VAR forestLen: ARRAY OF LONGINT);
  VAR i: INTEGER; sum: Rope; sumLen: LONGINT;
BEGIN
  i := 0;
  sum := NIL;
  sumLen := 0;
  WHILE (i < MaxDepth) & (xLen > minLength[i + 1]) DO
    IF forest[i] # NIL THEN
      sum := SimpleCat(forest[i], sum);
      sumLen := sumLen + forestLen[i];
      forest[i] := NIL
    END;
    INC(i)
  END;
  sum := SimpleCat(sum, x);
  sumLen := sumLen + xLen;
  WHILE (i <= MaxDepth) & (sumLen >= minLength[i]) DO
    IF forest[i] # NIL THEN
      sum := SimpleCat(forest[i], sum);
      sumLen := sumLen + forestLen[i];
      forest[i] := NIL
    END;
    INC(i)
  END;
  DEC(i);
  forest[i] := sum;
  forestLen[i] := sumLen
END BalanceInsert;

(* Walk x left to right, inserting each leaf into the forest.  A Concat
   node that is already balanced for its own depth is treated as atomic
   (inserted whole) instead of being torn apart; only genuinely unbalanced
   Concat nodes are recursed into. *)
PROCEDURE BalanceWalk(x: Rope; VAR forest: ARRAY OF Rope; VAR forestLen: ARRAY OF LONGINT);
  VAR c: Concat;
BEGIN
  IF x = NIL THEN RETURN END;
  IF (x IS Concat) & ~((x.depth < MaxDepth) & (x.length >= minLength[x.depth])) THEN
    c := x(Concat);
    BalanceWalk(c.left, forest, forestLen);
    BalanceWalk(c.right, forest, forestLen)
  ELSE
    BalanceInsert(x, x.length, forest, forestLen)
  END
END BalanceWalk;

(* Reassemble the forest into one rope: slots low to high, each prepended
   to what has been assembled from the lower slots so far (forest[i] holds
   the piece to the left of everything inserted before it at lower
   depths). *)
PROCEDURE ConcatForest(VAR forest: ARRAY OF Rope): Rope;
  VAR i: INTEGER; result: Rope;
BEGIN
  result := NIL;
  FOR i := 0 TO MaxDepth DO
    IF forest[i] # NIL THEN result := SimpleCat(forest[i], result) END
  END;
  RETURN result
END ConcatForest;

PROCEDURE Balance*(r: Rope): Rope;
  VAR forest: ARRAY MaxDepth + 1 OF Rope; forestLen: ARRAY MaxDepth + 1 OF LONGINT; i: INTEGER;
BEGIN
  IF r = NIL THEN RETURN NIL END;
  FOR i := 0 TO MaxDepth DO forest[i] := NIL; forestLen[i] := 0 END;
  BalanceWalk(r, forest, forestLen);
  RETURN ConcatForest(forest)
END Balance;

(* --- Iterator --- *)

(* Descends from the root to the leaf covering it.pos, caching it in
   it.leaf/it.leafStart.  Skipped if the cached leaf already covers
   it.pos.  Traps (HALT) if it.pos is out of bounds, the same convention
   as Fetch. *)
PROCEDURE (it: Iterator) Locate;
  VAR r: Rope; c: Concat; base: LONGINT;
BEGIN
  IF (it.r = NIL) OR (it.pos < 0) OR (it.pos >= it.r.length) THEN HALT(1) END;
  IF (it.leaf # NIL) & (it.pos >= it.leafStart) & (it.pos < it.leafStart + it.leaf.length) THEN
    RETURN
  END;
  r := it.r;
  base := 0;
  WHILE ~(r IS Leaf) DO
    c := r(Concat);
    IF it.pos - base < c.left.length THEN
      r := c.left
    ELSE
      base := base + c.left.length;
      r := c.right
    END
  END;
  it.leaf := r(Leaf);
  it.leafStart := base
END Locate;

(* A new iterator for r, initially at position pos.  pos need not be a
   valid position of r -- that is only checked by Get and Peek -- so
   Move, Goto, Incr and Decr never trap by themselves. *)
PROCEDURE NewIterator*(r: Rope; pos: LONGINT): Iterator;
  VAR it: Iterator;
BEGIN
  NEW(it);
  it.r := r;
  it.pos := pos;
  it.leaf := NIL;
  it.leafStart := 0;
  RETURN it
END NewIterator;

(* The character at the iterator's current position.  O(1) if the
   position stayed within the leaf last visited, else O(log(length r)). *)
PROCEDURE (it: Iterator) Get*(): CHAR;
BEGIN
  it.Locate;
  RETURN it.leaf.chars[it.pos - it.leafStart]
END Get;

(* The character at position i of the rope the iterator was made from,
   without changing the iterator's current position.  Also updates the
   cached leaf to cover i, so a Peek near the current position -- or a
   sequence of nearby Peeks -- is cheaper than an unrelated Fetch. *)
PROCEDURE (it: Iterator) Peek*(i: LONGINT): CHAR;
  VAR savedPos: LONGINT; ch: CHAR;
BEGIN
  savedPos := it.pos;
  it.pos := i;
  it.Locate;
  ch := it.leaf.chars[i - it.leafStart];
  it.pos := savedPos;
  RETURN ch
END Peek;

(* The iterator's current position.  May not be a valid position of its
   rope. *)
PROCEDURE (it: Iterator) Pos*(): LONGINT;
BEGIN
  RETURN it.pos
END Pos;

(* Moves the iterator to the next character. *)
PROCEDURE (it: Iterator) Incr*;
BEGIN
  INC(it.pos)
END Incr;

(* Moves the iterator to the previous character. *)
PROCEDURE (it: Iterator) Decr*;
BEGIN
  DEC(it.pos)
END Decr;

(* Moves the iterator to position pos. *)
PROCEDURE (it: Iterator) Goto*(pos: LONGINT);
BEGIN
  it.pos := pos
END Goto;

(* Moves the iterator by delta characters (negative or zero allowed). *)
PROCEDURE (it: Iterator) Move*(delta: LONGINT);
BEGIN
  it.pos := it.pos + delta
END Move;

(* The rope the iterator was constructed from. *)
PROCEDURE (it: Iterator) Source*(): Rope;
BEGIN
  RETURN it.r
END Source;

(* --- Substring --- *)

(* Precondition: r # NIL, 0 <= start, start + len <= Length(r), len > 0. *)
PROCEDURE SubstrHelper(r: Rope; start, len: LONGINT): Rope;
  VAR c: Concat; leftPart, rightPart: Rope;
BEGIN
  IF r IS Leaf THEN RETURN NewLeaf(r(Leaf).chars^, start, len) END;
  c := r(Concat);
  IF (start <= 0) & (len >= c.length) THEN RETURN r END;
  IF start >= c.left.length THEN
    RETURN SubstrHelper(c.right, start - c.left.length, len)
  ELSIF start + len <= c.left.length THEN
    RETURN SubstrHelper(c.left, start, len)
  ELSE
    leftPart := SubstrHelper(c.left, start, c.left.length - start);
    rightPart := SubstrHelper(c.right, 0, start + len - c.left.length);
    RETURN SimpleCat(leftPart, rightPart)
  END
END SubstrHelper;

(* start is clamped to 0 and start + len to Length(r); NIL if the clamped
   length is <= 0 or r is NIL. *)
PROCEDURE Substring*(r: Rope; start, len: LONGINT): Rope;
BEGIN
  IF r = NIL THEN RETURN NIL END;
  IF start < 0 THEN start := 0 END;
  IF start >= r.length THEN RETURN NIL END;
  IF start + len > r.length THEN len := r.length - start END;
  IF len <= 0 THEN RETURN NIL END;
  RETURN SubstrHelper(r, start, len)
END Substring;

(* Copies r[start .. start + len - 1] into dst starting at d, advancing d.
   Precondition: r # NIL, len > 0, 0 <= start, start + len <= r.length.
   Descends only into the subtrees that overlap the range, and copies
   straight out of each leaf, so it is O(len + depth), not a Fetch from
   the root per character. *)
PROCEDURE BlitHelper(r: Rope; start, len: LONGINT; VAR dst: ARRAY OF CHAR; VAR d: LONGINT);
  VAR c: Concat; leaf: Leaf; i, n: LONGINT;
BEGIN
  IF r IS Leaf THEN
    leaf := r(Leaf);
    FOR i := start TO start + len - 1 DO dst[d] := leaf.chars[i]; INC(d) END
  ELSE
    c := r(Concat);
    IF start < c.left.length THEN
      n := c.left.length - start;
      IF n > len THEN n := len END;
      BlitHelper(c.left, start, n, dst, d);
      DEC(len, n);
      start := c.left.length
    END;
    IF len > 0 THEN BlitHelper(c.right, start - c.left.length, len, dst, d) END
  END
END BlitHelper;

(* Copies len characters of r starting at srcStart into dst starting at
   dstStart; no 0X terminator is written, unlike ToString.  O(len +
   depth(r)).
   Precondition: 0 <= srcStart, srcStart + len <= Length(r), 0 <= dstStart,
   dstStart + len <= LEN(dst).  Traps (HALT(1)) if violated -- including
   when srcStart + len or dstStart + len would overflow LONGINT: the
   checks are written as len > Length(r) - srcStart and len > LEN(dst) -
   dstStart, which, once srcStart and dstStart are known to be >= 0, are
   differences of two non-negative numbers and so cannot overflow, where
   the sums could silently wrap negative (voc does not trap LONGINT
   overflow) and slip past the check. *)
PROCEDURE Blit*(r: Rope; srcStart: LONGINT; VAR dst: ARRAY OF CHAR; dstStart, len: LONGINT);
  VAR d: LONGINT;
BEGIN
  IF (srcStart < 0) OR (len > Length(r) - srcStart) OR (dstStart < 0) OR (len > LEN(dst) - dstStart) THEN
    HALT(1)
  END;
  IF len > 0 THEN
    d := dstStart;
    BlitHelper(r, srcStart, len, dst, d)
  END
END Blit;

(* r with ins spliced in before index pos: Substring(r, 0, pos) followed by
   ins followed by Substring(r, pos, Length(r) - pos).  pos is clamped to
   [0, Length(r)], so a too-large pos appends and a negative pos prepends,
   the same convention Substring uses for its own start.  NIL r or NIL ins
   are handled by Substring and Cat without any special-casing here. *)
PROCEDURE Insert*(r: Rope; pos: LONGINT; ins: Rope): Rope;
  VAR left, right: Rope;
BEGIN
  IF pos < 0 THEN pos := 0 END;
  IF pos > Length(r) THEN pos := Length(r) END;
  left := Substring(r, 0, pos);
  right := Substring(r, pos, Length(r) - pos);
  RETURN Cat(Cat(left, ins), right)
END Insert;

(* r with the len characters at pos taken out: Substring(r, 0, pos)
   concatenated with Substring(r, pos + len, Length(r) - pos - len).  pos
   and len are clamped the same way Substring clamps its own start and
   len: pos into [0, Length(r)], len into [0, Length(r) - pos], so a
   negative or over-length pos or len is trimmed to what actually exists
   rather than trapping. *)
PROCEDURE Remove*(r: Rope; pos, len: LONGINT): Rope;
  VAR left, right: Rope;
BEGIN
  IF pos < 0 THEN pos := 0 END;
  IF pos > Length(r) THEN pos := Length(r) END;
  IF len < 0 THEN len := 0 END;
  IF pos + len > Length(r) THEN len := Length(r) - pos END;
  left := Substring(r, 0, pos);
  right := Substring(r, pos + len, Length(r) - pos - len);
  RETURN Cat(left, right)
END Remove;

(* r with the characters from pos onward replaced by new, extending r if
   new runs past its current end: Substring(r, 0, pos) followed by new
   followed by Substring(r, pos + Length(new), Length(r) - pos -
   Length(new)).  pos is clamped into [0, Length(r)], the same
   convention Insert/Remove above already use for their own position
   arguments, rather than trapping on an out-of-range pos.  Ported back
   from the Ada Ropes package (Ropes.Overwrite, modeled there on
   Ada.Strings.Unbounded.Overwrite) -- a genuine extension beyond this
   module's own original scope, added because the Ada port found it a
   plausible-enough addition to make anyway; the clamp-not-trap
   convention here keeps it consistent with every other position-taking
   operation already in this file, rather than copying Ada's
   exception-on-out-of-range behavior verbatim. *)
PROCEDURE Overwrite*(r: Rope; pos: LONGINT; new: Rope): Rope;
  VAR left, right: Rope; tailStart: LONGINT;
BEGIN
  IF pos < 0 THEN pos := 0 END;
  IF pos > Length(r) THEN pos := Length(r) END;
  left := Substring(r, 0, pos);
  tailStart := pos + Length(new);
  right := Substring(r, tailStart, Length(r) - tailStart);
  RETURN Cat(Cat(left, new), right)
END Overwrite;

(* r with the len characters at pos replaced by by: Substring(r, 0, pos)
   followed by by followed by what Remove(r, pos, len) leaves after pos.
   pos and len are clamped as Remove clamps them, so a len running past
   the end replaces through the end, and len <= 0 inserts by before pos.
   Ported back from the Ada Ropes package (Ada.Strings.Unbounded's
   Replace_Slice, which takes a Low and High and raises Index_Error for a
   Low past the end rather than clamping). *)
PROCEDURE Replace*(r: Rope; pos, len: LONGINT; by: Rope): Rope;
  VAR left, right: Rope;
BEGIN
  IF pos < 0 THEN pos := 0 END;
  IF pos > Length(r) THEN pos := Length(r) END;
  IF len < 0 THEN len := 0 END;
  IF len > Length(r) - pos THEN len := Length(r) - pos END;
  left := Substring(r, 0, pos);
  right := Substring(r, pos + len, Length(r) - pos - len);
  RETURN Cat(Cat(left, by), right)
END Replace;

(* r with the character at pos replaced by ch.  Precondition: 0 <= pos <
   Length(r) -- traps (HALT) if violated, as Fetch does, rather than
   clamping: there is no character to replace outside r, and a clamped
   pos would silently replace a different one.  Ported back from the Ada
   Ropes package (Ada.Strings.Unbounded's Replace_Element). *)
PROCEDURE ReplaceChar*(r: Rope; pos: LONGINT; ch: CHAR): Rope;
BEGIN
  IF (pos < 0) OR (pos >= Length(r)) THEN HALT(1) END;
  RETURN Cat(Cat(Substring(r, 0, pos), FromChar(ch)), Substring(r, pos + 1, Length(r) - pos - 1))
END ReplaceChar;

(* --- Leaf walks --- *)

(* Precondition: r # NIL. *)
PROCEDURE StartWalk(VAR w: LeafWalk; r: Rope);
BEGIN
  NEW(w.stack, r.depth + 1);
  w.stack[0] := r;
  w.top := 1;
  w.forward := TRUE
END StartWalk;

(* Starts a walk in direction forward from r's character at pos: leaf is
   the leaf holding it, at leaf.chars[off], and NextLeaf then gives the
   leaves after (forward) or before (backward) leaf, in order.  One
   descent from the root, pushing the subtree on the far side of each
   step, so O(depth(r)).  Precondition: r # NIL, 0 <= pos < r.length. *)
PROCEDURE StartWalkAt(VAR w: LeafWalk; r: Rope; pos: LONGINT; forward: BOOLEAN; VAR leaf: Leaf; VAR off: LONGINT);
  VAR n: Rope; c: Concat;
BEGIN
  NEW(w.stack, r.depth + 1);
  w.top := 0;
  w.forward := forward;
  n := r;
  WHILE n IS Concat DO
    c := n(Concat);
    IF pos < c.left.length THEN
      IF forward THEN w.stack[w.top] := c.right; INC(w.top) END;
      n := c.left
    ELSE
      IF ~forward THEN w.stack[w.top] := c.left; INC(w.top) END;
      DEC(pos, c.left.length);
      n := c.right
    END
  END;
  leaf := n(Leaf);
  off := pos
END StartWalkAt;

(* Precondition: the walk has a leaf left to return (w.top > 0). *)
PROCEDURE NextLeaf(VAR w: LeafWalk): Leaf;
  VAR n: Rope; c: Concat;
BEGIN
  LOOP
    DEC(w.top);
    n := w.stack[w.top];
    IF n IS Leaf THEN RETURN n(Leaf) END;
    c := n(Concat);
    IF w.forward THEN
      w.stack[w.top] := c.right;
      w.stack[w.top + 1] := c.left
    ELSE
      w.stack[w.top] := c.left;
      w.stack[w.top + 1] := c.right
    END;
    INC(w.top, 2)
  END
END NextLeaf;

(* v := an independent copy of w, with its own stack: a plain assignment
   would share w's. *)
PROCEDURE CopyWalk(VAR w, v: LeafWalk);
  VAR i: LONGINT;
BEGIN
  NEW(v.stack, LEN(w.stack^));
  FOR i := 0 TO w.top - 1 DO v.stack[i] := w.stack[i] END;
  v.top := w.top;
  v.forward := w.forward
END CopyWalk;

(* --- Comparison and hashing --- *)

(* <0, 0 or >0, like strcmp: lexicographic by character, then by length,
   with each character passed through LowerChar first if fold.  Linear
   in the common prefix: walks both ropes' leaves in step, reading each
   leaf's characters directly, instead of a Fetch from the root per
   character (O(n log n), ~7 s on two 20-million-character ropes in the
   Ada port this was fixed in first).  Two ropes sharing a root compare
   equal in O(1). *)
PROCEDURE CompareFolded(a, b: Rope; fold: BOOLEAN): INTEGER;
  VAR wa, wb: LeafWalk; la, lb: Leaf; pa, pb, remaining: LONGINT; ca, cb: CHAR;
BEGIN
  IF a = b THEN RETURN 0 END;
  remaining := Length(a);
  IF Length(b) < remaining THEN remaining := Length(b) END;
  IF remaining > 0 THEN
    StartWalk(wa, a); StartWalk(wb, b);
    la := NextLeaf(wa); lb := NextLeaf(wb);
    pa := 0; pb := 0;
    WHILE remaining > 0 DO
      IF pa = la.length THEN la := NextLeaf(wa); pa := 0 END;
      IF pb = lb.length THEN lb := NextLeaf(wb); pb := 0 END;
      ca := la.chars[pa];
      cb := lb.chars[pb];
      IF fold THEN ca := LowerChar(ca); cb := LowerChar(cb) END;
      IF ca < cb THEN RETURN -1 END;
      IF ca > cb THEN RETURN 1 END;
      INC(pa); INC(pb); DEC(remaining)
    END
  END;
  IF Length(a) < Length(b) THEN RETURN -1 END;
  IF Length(a) > Length(b) THEN RETURN 1 END;
  RETURN 0
END CompareFolded;

PROCEDURE Compare*(a, b: Rope): INTEGER;
BEGIN
  RETURN CompareFolded(a, b, FALSE)
END Compare;

PROCEDURE Equal*(a, b: Rope): BOOLEAN;
BEGIN
  RETURN Compare(a, b) = 0
END Equal;

(* Compare, ignoring the case of ASCII letters (each character passed
   through LowerChar, as LowercaseAscii does), and Equal likewise.
   Ported back from the Ada Ropes package (its Less_Case_Insensitive and
   Equal_Case_Insensitive, Ada.Strings.Unbounded's), which folds Latin-1
   letters too: this module's case operations are ASCII-only. *)
PROCEDURE CompareNoCase*(a, b: Rope): INTEGER;
BEGIN
  RETURN CompareFolded(a, b, TRUE)
END CompareNoCase;

PROCEDURE EqualNoCase*(a, b: Rope): BOOLEAN;
BEGIN
  RETURN (Length(a) = Length(b)) & (CompareNoCase(a, b) = 0)
END EqualNoCase;

(* Compare, with s -- its characters up to its 0X, or all of it if it has
   none -- in place of a rope, without first copying s into one: r's
   leaves are compared with s where they lie.  Ported back from the Ada
   Ropes package (its Rope/String comparison operators). *)
PROCEDURE CompareString*(r: Rope; s: ARRAY OF CHAR): INTEGER;
  VAR w: LeafWalk; leaf: Leaf; p, k, sLen, remaining: LONGINT; c: CHAR;
BEGIN
  sLen := StrLen(s);
  remaining := Length(r);
  IF sLen < remaining THEN remaining := sLen END;
  IF remaining > 0 THEN
    StartWalk(w, r);
    leaf := NextLeaf(w);
    p := 0; k := 0;
    WHILE remaining > 0 DO
      IF p = leaf.length THEN leaf := NextLeaf(w); p := 0 END;
      c := leaf.chars[p];
      IF c < s[k] THEN RETURN -1 END;
      IF c > s[k] THEN RETURN 1 END;
      INC(p); INC(k); DEC(remaining)
    END
  END;
  IF Length(r) < sLen THEN RETURN -1 END;
  IF Length(r) > sLen THEN RETURN 1 END;
  RETURN 0
END CompareString;

PROCEDURE EqualString*(r: Rope; s: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN CompareString(r, s) = 0
END EqualString;

PROCEDURE HashFolded(r: Rope; fold: BOOLEAN): HUGEINT;
  VAR w: LeafWalk; leaf: Leaf; h: HUGEINT; i: LONGINT; c: CHAR;
BEGIN
  h := 0;
  IF r # NIL THEN
    StartWalk(w, r);
    REPEAT
      leaf := NextLeaf(w);
      FOR i := 0 TO leaf.length - 1 DO
        c := leaf.chars[i];
        IF fold THEN c := LowerChar(c) END;
        h := (ORD(c) + h * 64 + h * 65536 - h) MOD 100000000H
      END
    UNTIL w.top = 0
  END;
  RETURN h
END HashFolded;

(* A hash of r's characters, in 0 .. 2^32 - 1: equal ropes hash alike,
   whatever their leaves.  The sdbm recurrence h := ch + h * 2^6 +
   h * 2^16 - h (mod 2^32) -- GNAT's System.String_Hash, so this is
   exactly GNAT's Ada.Strings.Hash of the same characters, as the Ada
   Ropes package's Hash (ported back from there) is.  A HUGEINT, since
   voc's LONGINT is 32 bits and signed; computed in HUGEINT too, where
   h * 2^16 < 2^48 can't overflow.  O(Length(r)). *)
PROCEDURE Hash*(r: Rope): HUGEINT;
BEGIN
  RETURN HashFolded(r, FALSE)
END Hash;

(* Hash, ignoring the case of ASCII letters: ropes EqualNoCase to each
   other hash alike. *)
PROCEDURE HashNoCase*(r: Rope): HUGEINT;
BEGIN
  RETURN HashFolded(r, TRUE)
END HashNoCase;

(* --- Search ---

   Every search walks r's leaves in its own direction from where it
   starts (StartWalkAt), reading each leaf's characters in place:
   O(depth) to reach the start, then O(1) per character -- not a Fetch
   from the root per character, which made every search O(n log n) and
   a pattern search O(n m log n) until these were ported back from the
   Ada Ropes package, where the same change made searches 25 to 130
   times faster.  A pattern search tests each candidate's first
   character (last, backward) before comparing the rest, continuing into
   the following leaves on a copy of the walk when a candidate crosses
   one: O(n m) at worst, and close to O(n) when the pattern's first
   character is uncommon. *)

(* A set holding exactly the characters of chars, up to its 0X (or all of
   it if it has none) -- so never 0X itself; set has[0] directly for
   that. *)
PROCEDURE MakeCharSet*(chars: ARRAY OF CHAR; VAR set: CharSet);
  VAR i, len: LONGINT;
BEGIN
  FOR i := 0 TO 255 DO set.has[i] := FALSE END;
  len := StrLen(chars);
  FOR i := 0 TO len - 1 DO set.has[ORD(chars[i])] := TRUE END
END MakeCharSet;

(* The index of the first (forward: at or after from) or last (backward:
   at or before from) character of r that is in set if inside, or not in
   it if ~inside; -1 if none.  Precondition: r # NIL, 0 <= from <
   r.length. *)
PROCEDURE ScanSet(r: Rope; VAR set: CharSet; inside: BOOLEAN; from: LONGINT; forward: BOOLEAN): LONGINT;
  VAR w: LeafWalk; leaf: Leaf; off, base, i: LONGINT;
BEGIN
  StartWalkAt(w, r, from, forward, leaf, off);
  base := from - off;  (* leaf.chars[i] is r's character base + i. *)
  IF forward THEN
    LOOP
      FOR i := off TO leaf.length - 1 DO
        IF set.has[ORD(leaf.chars[i])] = inside THEN RETURN base + i END
      END;
      IF w.top = 0 THEN EXIT END;
      INC(base, leaf.length);
      leaf := NextLeaf(w);
      off := 0
    END
  ELSE
    LOOP
      FOR i := off TO 0 BY -1 DO
        IF set.has[ORD(leaf.chars[i])] = inside THEN RETURN base + i END
      END;
      IF w.top = 0 THEN EXIT END;
      leaf := NextLeaf(w);
      DEC(base, leaf.length);
      off := leaf.length - 1
    END
  END;
  RETURN -1
END ScanSet;

(* The index of the first character of r at or after from that is in set
   (inside) or not in set (~inside), or -1.  A negative from is treated
   as 0, as IndexChar treats it.  VAR only so that set is not copied; it
   is not changed.  Ported back from the Ada Ropes package (its
   Character_Set Index, Ada.Strings.Unbounded's). *)
PROCEDURE IndexSet*(r: Rope; VAR set: CharSet; inside: BOOLEAN; from: LONGINT): LONGINT;
BEGIN
  IF from < 0 THEN from := 0 END;
  IF from >= Length(r) THEN RETURN -1 END;
  RETURN ScanSet(r, set, inside, from, TRUE)
END IndexSet;

(* The index of the last character of r at or before "before" that is in
   set (inside) or not (~inside), or -1.  A "before" past the end is
   treated as the last character, as RIndexChar treats it. *)
PROCEDURE RIndexSet*(r: Rope; VAR set: CharSet; inside: BOOLEAN; before: LONGINT): LONGINT;
BEGIN
  IF before > Length(r) - 1 THEN before := Length(r) - 1 END;
  IF before < 0 THEN RETURN -1 END;
  RETURN ScanSet(r, set, inside, before, FALSE)
END RIndexSet;

(* The index of the first occurrence of ch at or after from, or -1. *)
PROCEDURE IndexChar*(r: Rope; ch: CHAR; from: LONGINT): LONGINT;
  VAR set: CharSet;
BEGIN
  MakeCharSet("", set);
  set.has[ORD(ch)] := TRUE;
  RETURN IndexSet(r, set, TRUE, from)
END IndexChar;

(* The index of the last occurrence of ch at or before "before", or -1. *)
PROCEDURE RIndexChar*(r: Rope; ch: CHAR; before: LONGINT): LONGINT;
  VAR set: CharSet;
BEGIN
  MakeCharSet("", set);
  set.has[ORD(ch)] := TRUE;
  RETURN RIndexSet(r, set, TRUE, before)
END RIndexChar;

(* Whether ch occurs in r at or after from. *)
PROCEDURE Contains*(r: Rope; ch: CHAR; from: LONGINT): BOOLEAN;
BEGIN
  RETURN IndexChar(r, ch, from) >= 0
END Contains;

(* The index of the first character of r at or after from that is not a
   space, or -1; RIndexNonBlank, the last at or before "before".  Only
   " " is blank, not tab or line feed -- Ada.Strings.Unbounded's
   Index_Non_Blank, ported back from the Ada Ropes package. *)
PROCEDURE IndexNonBlank*(r: Rope; from: LONGINT): LONGINT;
  VAR blank: CharSet;
BEGIN
  MakeCharSet(" ", blank);
  RETURN IndexSet(r, blank, FALSE, from)
END IndexNonBlank;

PROCEDURE RIndexNonBlank*(r: Rope; before: LONGINT): LONGINT;
  VAR blank: CharSet;
BEGIN
  MakeCharSet(" ", blank);
  RETURN RIndexSet(r, blank, FALSE, before)
END RIndexNonBlank;

(* The first token of r at or after from: start is the index of the first
   character there that is in set (inside) or not in set (~inside), and
   len the length of the run of such characters beginning there, so
   Substring(r, start, len) is the token.  If there is none, start is
   from (0 if from is negative) and len is 0.  Ada.Strings.Unbounded's
   Find_Token, ported back from the Ada Ropes package, as a start and a
   length like Substring's rather than Ada's First and Last. *)
PROCEDURE FindToken*(r: Rope; VAR set: CharSet; inside: BOOLEAN; from: LONGINT; VAR start, len: LONGINT);
  VAR after: LONGINT;
BEGIN
  IF from < 0 THEN from := 0 END;
  start := IndexSet(r, set, inside, from);
  IF start < 0 THEN
    start := from;
    len := 0
  ELSE
    after := IndexSet(r, set, ~inside, start);
    IF after < 0 THEN len := Length(r) - start ELSE len := after - start END
  END
END FindToken;

(* Whether pattern[0 .. patLen-1] occurs starting at leaf.chars[i] (going
   forward) or ending there (backward), running on into the leaves after
   (before) leaf as needed -- which exist: the caller only asks when the
   occurrence would lie within the rope.  Each character of the rope
   passes through f first, unless f is NIL.  Continues on a copy of w,
   made only if the occurrence leaves leaf, so the caller's walk keeps
   its place. *)
PROCEDURE MatchesAt(VAR w: LeafWalk; leaf: Leaf; i: LONGINT; VAR pattern: ARRAY OF CHAR; patLen: LONGINT;
                    forward: BOOLEAN; f: Mapper): BOOLEAN;
  VAR v: LeafWalk; k: LONGINT; c: CHAR; copied: BOOLEAN;
BEGIN
  copied := FALSE;
  IF forward THEN
    k := 0;
    LOOP
      WHILE (k < patLen) & (i < leaf.length) DO
        c := leaf.chars[i];
        IF f # NIL THEN c := f(c) END;
        IF c # pattern[k] THEN RETURN FALSE END;
        INC(k); INC(i)
      END;
      IF k = patLen THEN RETURN TRUE END;
      IF ~copied THEN CopyWalk(w, v); copied := TRUE END;
      leaf := NextLeaf(v);
      i := 0
    END
  ELSE
    k := patLen - 1;
    LOOP
      WHILE (k >= 0) & (i >= 0) DO
        c := leaf.chars[i];
        IF f # NIL THEN c := f(c) END;
        IF c # pattern[k] THEN RETURN FALSE END;
        DEC(k); DEC(i)
      END;
      IF k < 0 THEN RETURN TRUE END;
      IF ~copied THEN CopyWalk(w, v); copied := TRUE END;
      leaf := NextLeaf(v);
      i := leaf.length - 1
    END
  END
END MatchesAt;

(* The start of the first occurrence of pattern[0 .. patLen-1] in r
   starting at or after from (forward), or of the last one starting at or
   before from (backward), or -1; each character of r passes through f
   first, unless f is NIL -- pattern itself never does.  Precondition:
   r # NIL, patLen > 0, 0 <= from <= r.length - patLen. *)
PROCEDURE FindCore(r: Rope; VAR pattern: ARRAY OF CHAR; patLen, from: LONGINT; forward: BOOLEAN; f: Mapper): LONGINT;
  VAR w: LeafWalk; leaf: Leaf; off, base, i, bound, lastStart, lastEnd: LONGINT; c, first, last: CHAR;
BEGIN
  IF forward THEN
    (* Occurrences can start at from .. lastStart. *)
    lastStart := r.length - patLen;
    first := pattern[0];
    StartWalkAt(w, r, from, TRUE, leaf, off);
    base := from - off;
    LOOP
      bound := leaf.length - 1;
      IF base + bound > lastStart THEN bound := lastStart - base END;
      FOR i := off TO bound DO
        c := leaf.chars[i];
        IF f # NIL THEN c := f(c) END;
        IF (c = first) & MatchesAt(w, leaf, i, pattern, patLen, TRUE, f) THEN RETURN base + i END
      END;
      IF base + bound = lastStart THEN EXIT END;
      INC(base, leaf.length);
      leaf := NextLeaf(w);
      off := 0
    END
  ELSE
    (* Occurrences can end at patLen - 1 .. lastEnd. *)
    lastEnd := from + patLen - 1;
    last := pattern[patLen - 1];
    StartWalkAt(w, r, lastEnd, FALSE, leaf, off);
    base := lastEnd - off;
    LOOP
      bound := 0;
      IF base < patLen - 1 THEN bound := patLen - 1 - base END;
      FOR i := off TO bound BY -1 DO
        c := leaf.chars[i];
        IF f # NIL THEN c := f(c) END;
        IF (c = last) & MatchesAt(w, leaf, i, pattern, patLen, FALSE, f) THEN RETURN base + i - patLen + 1 END
      END;
      IF base + bound = patLen - 1 THEN EXIT END;
      leaf := NextLeaf(w);
      DEC(base, leaf.length);
      off := leaf.length - 1
    END
  END;
  RETURN -1
END FindCore;

(* Find, with each character of r passed through f before it is compared
   with pattern's -- pattern itself is not mapped, so a case-insensitive
   search passes LowerChar and a lower-case pattern.  A NIL f compares
   unmapped, as Find does.  Ported back from the Ada Ropes package (the
   Mapping parameter of its Index, Ada.Strings.Unbounded's). *)
PROCEDURE FindMapped*(r: Rope; pattern: ARRAY OF CHAR; from: LONGINT; f: Mapper): LONGINT;
  VAR patLen, rLen: LONGINT;
BEGIN
  patLen := StrLen(pattern);
  rLen := Length(r);
  IF from < 0 THEN from := 0 END;
  IF patLen = 0 THEN
    IF from > rLen THEN RETURN -1 END;
    RETURN from
  END;
  IF from > rLen - patLen THEN RETURN -1 END;
  RETURN FindCore(r, pattern, patLen, from, TRUE, f)
END FindMapped;

(* The index of the first occurrence of pattern at or after from, or -1.
   The empty pattern matches at from (clamped into [0, Length(r)]). *)
PROCEDURE Find*(r: Rope; pattern: ARRAY OF CHAR; from: LONGINT): LONGINT;
BEGIN
  RETURN FindMapped(r, pattern, from, NIL)
END Find;

(* RFind, with each character of r passed through f first, as FindMapped
   does for Find. *)
PROCEDURE RFindMapped*(r: Rope; pattern: ARRAY OF CHAR; before: LONGINT; f: Mapper): LONGINT;
  VAR patLen, rLen: LONGINT;
BEGIN
  patLen := StrLen(pattern);
  rLen := Length(r);
  IF patLen = 0 THEN
    IF before < 0 THEN RETURN -1 END;
    IF before > rLen THEN before := rLen END;
    RETURN before
  END;
  IF before > rLen - patLen THEN before := rLen - patLen END;
  IF before < 0 THEN RETURN -1 END;
  RETURN FindCore(r, pattern, patLen, before, FALSE, f)
END RFindMapped;

(* The index of the last occurrence of pattern starting at or before
   "before", or -1.  RFind(r, pattern, Length(r)) searches the whole
   rope, mirroring how Find(r, pattern, 0) does.  The empty pattern
   matches at "before" itself (clamped into [0, Length(r)]), mirroring
   Find's empty-pattern convention. *)
PROCEDURE RFind*(r: Rope; pattern: ARRAY OF CHAR; before: LONGINT): LONGINT;
BEGIN
  RETURN RFindMapped(r, pattern, before, NIL)
END RFind;

(* Count, with each character of r passed through f first, as FindMapped
   does for Find. *)
PROCEDURE CountMapped*(r: Rope; pattern: ARRAY OF CHAR; f: Mapper): LONGINT;
  VAR patLen, from, pos, n: LONGINT;
BEGIN
  patLen := StrLen(pattern);
  n := 0;
  IF patLen = 0 THEN RETURN 0 END;
  from := 0;
  WHILE from <= Length(r) - patLen DO
    pos := FindCore(r, pattern, patLen, from, TRUE, f);
    IF pos < 0 THEN RETURN n END;
    INC(n);
    from := pos + patLen
  END;
  RETURN n
END CountMapped;

(* The number of non-overlapping occurrences of pattern in r, counted left
   to right, each search starting just after the previous match.  0 for
   the empty pattern, which never occurs -- the same convention as
   Split's, where an empty separator never splits.  Ported back from the
   Ada Ropes package (Ada.Strings.Unbounded's Count, which raises
   Pattern_Error for an empty pattern instead). *)
PROCEDURE Count*(r: Rope; pattern: ARRAY OF CHAR): LONGINT;
BEGIN
  RETURN CountMapped(r, pattern, NIL)
END Count;

(* The number of characters of r that are in set.  Linear in Length(r). *)
PROCEDURE CountSet*(r: Rope; VAR set: CharSet): LONGINT;
  VAR w: LeafWalk; leaf: Leaf; i, n: LONGINT;
BEGIN
  n := 0;
  IF r # NIL THEN
    StartWalk(w, r);
    REPEAT
      leaf := NextLeaf(w);
      FOR i := 0 TO leaf.length - 1 DO
        IF set.has[ORD(leaf.chars[i])] THEN INC(n) END
      END
    UNTIL w.top = 0
  END;
  RETURN n
END CountSet;

(* Whether pattern occurs in r at or after from -- a thin wrapper over
   Find, the same relationship Contains above already has to IndexChar,
   just for a string/rope pattern instead of one character.  Ported back
   from the Ada Ropes package (Ropes.Contains's Rope-pattern overloads),
   which paired a pattern-based Contains with the char-based one this
   module already had; named ContainsPattern rather than reusing
   Contains, since Oberon-2 has no overloading to distinguish the two by
   parameter type alone. *)
PROCEDURE ContainsPattern*(r: Rope; pattern: ARRAY OF CHAR; from: LONGINT): BOOLEAN;
BEGIN
  RETURN Find(r, pattern, from) >= 0
END ContainsPattern;

(* --- Iteration --- *)

(* Returns FALSE if visit asked to stop partway through. *)
PROCEDURE IterateHelper(r: Rope; visit: Visitor): BOOLEAN;
  VAR c: Concat; leaf: Leaf; i: LONGINT; cont: BOOLEAN;
BEGIN
  IF r = NIL THEN RETURN TRUE END;
  IF r IS Leaf THEN
    leaf := r(Leaf);
    i := 0;
    cont := TRUE;
    WHILE cont & (i < leaf.length) DO
      cont := visit(leaf.chars[i]);
      INC(i)
    END;
    RETURN cont
  END;
  c := r(Concat);
  IF IterateHelper(c.left, visit) THEN RETURN IterateHelper(c.right, visit) END;
  RETURN FALSE
END IterateHelper;

(* Calls visit for each character of r, left to right; stops early if
   visit returns FALSE. *)
PROCEDURE Iterate*(r: Rope; visit: Visitor);
  VAR ignore: BOOLEAN;
BEGIN
  ignore := IterateHelper(r, visit)
END Iterate;

PROCEDURE IterateChunksHelper(r: Rope; visit: ChunkVisitor): BOOLEAN;
  VAR c: Concat;
BEGIN
  IF r = NIL THEN RETURN TRUE END;
  IF r IS Leaf THEN RETURN visit(r(Leaf).chars^) END;
  c := r(Concat);
  IF IterateChunksHelper(c.left, visit) THEN RETURN IterateChunksHelper(c.right, visit) END;
  RETURN FALSE
END IterateChunksHelper;

(* Calls visit once per leaf of r, left to right, with that leaf's
   characters (see ChunkVisitor), so the concatenation of every chunk
   visited is r's whole contents; stops early if visit returns FALSE.
   Never calls visit for NIL, and never with an empty chunk.  How r is
   divided into chunks depends on how it was built; only their order and
   concatenation are fixed.  The general way to hand a rope to something
   that takes flat characters -- a file, a buffer, a checksum -- without
   first copying all of it into one ARRAY OF CHAR. *)
PROCEDURE IterateChunks*(r: Rope; visit: ChunkVisitor);
  VAR ignore: BOOLEAN;
BEGIN
  ignore := IterateChunksHelper(r, visit)
END IterateChunks;

(* --- Split --- *)

(* The splitting rule shared by Split, SplitArray and SplitList: r's
   pieces are the maximal runs between non-overlapping occurrences of
   sep, found by repeated Find starting just after each match.  A NIL r,
   or a sep that does not occur in r, each give a single piece, r itself.
   A leading, trailing or doubled sep gives an empty piece, so there are
   always exactly (number of occurrences of sep) + 1 pieces, the same
   convention as Python's str.split (e.g. "a,b,".split(",") is
   ["a", "b", ""]).  An empty sep never splits -- there is no occurrence
   to split on -- so it too always gives a single piece, r itself. *)

(* Advances start past the next piece of r (and the sep, if any, that
   follows it), returning that piece.  sepLen must be StrLen(sep) > 0.
   Sets last to TRUE if the returned piece is the final one. *)
PROCEDURE NextPiece(r: Rope; sep: ARRAY OF CHAR; sepLen: LONGINT; VAR start: LONGINT; VAR last: BOOLEAN): Rope;
  VAR pos, rLen: LONGINT; piece: Rope;
BEGIN
  rLen := Length(r);
  pos := Find(r, sep, start);
  IF pos < 0 THEN
    piece := Substring(r, start, rLen - start);
    last := TRUE
  ELSE
    piece := Substring(r, start, pos - start);
    start := pos + sepLen;
    last := FALSE
  END;
  RETURN piece
END NextPiece;

(* How many pieces r splits into on sep (sepLen = StrLen(sep) > 0),
   without building any of them -- just counts occurrences of sep. *)
PROCEDURE CountPieces(r: Rope; sep: ARRAY OF CHAR; sepLen: LONGINT): LONGINT;
  VAR pos, start, count: LONGINT;
BEGIN
  count := 1;
  start := 0;
  pos := Find(r, sep, start);
  WHILE pos >= 0 DO
    INC(count);
    start := pos + sepLen;
    pos := Find(r, sep, start)
  END;
  RETURN count
END CountPieces;

(* Calls visit for each piece of r as split on sep (see above), left to
   right.  Stops early if visit returns FALSE. *)
PROCEDURE Split*(r: Rope; sep: ARRAY OF CHAR; visit: Visitor2);
  VAR sepLen, start: LONGINT; last, more: BOOLEAN;
BEGIN
  sepLen := StrLen(sep);
  IF sepLen = 0 THEN
    more := visit(r);
    RETURN
  END;
  start := 0;
  last := FALSE;
  more := TRUE;
  WHILE more & ~last DO
    more := visit(NextPiece(r, sep, sepLen, start, last))
  END
END Split;

(* r split on sep (see above), as an array with one entry per piece, in
   order. *)
PROCEDURE SplitArray*(r: Rope; sep: ARRAY OF CHAR): Pieces;
  VAR sepLen, start, n, i: LONGINT; last: BOOLEAN; result: Pieces;
BEGIN
  sepLen := StrLen(sep);
  IF sepLen = 0 THEN
    NEW(result, 1);
    result[0] := r;
    RETURN result
  END;
  n := CountPieces(r, sep, sepLen);
  NEW(result, n);
  start := 0;
  last := FALSE;
  i := 0;
  WHILE ~last DO
    result[i] := NextPiece(r, sep, sepLen, start, last);
    INC(i)
  END;
  RETURN result
END SplitArray;

(* r split on sep (see above), as a singly linked list of pieces, in
   order. *)
PROCEDURE SplitList*(r: Rope; sep: ARRAY OF CHAR): Piece;
  VAR sepLen, start: LONGINT; last: BOOLEAN; head, tail, node: Piece;
BEGIN
  sepLen := StrLen(sep);
  IF sepLen = 0 THEN
    NEW(head);
    head.rope := r;
    head.next := NIL;
    RETURN head
  END;
  head := NIL;
  tail := NIL;
  start := 0;
  last := FALSE;
  WHILE ~last DO
    NEW(node);
    node.rope := NextPiece(r, sep, sepLen, start, last);
    node.next := NIL;
    IF tail = NIL THEN head := node ELSE tail.next := node END;
    tail := node
  END;
  RETURN head
END SplitList;

PROCEDURE ToStringHelper(r: Rope; VAR s: ARRAY OF CHAR; VAR i, cap: LONGINT);
  VAR c: Concat; leaf: Leaf; j: LONGINT;
BEGIN
  IF (r = NIL) OR (i >= cap) THEN RETURN END;
  IF r IS Leaf THEN
    leaf := r(Leaf);
    j := 0;
    WHILE (j < leaf.length) & (i < cap) DO
      s[i] := leaf.chars[j];
      INC(i);
      INC(j)
    END
  ELSE
    c := r(Concat);
    ToStringHelper(c.left, s, i, cap);
    ToStringHelper(c.right, s, i, cap)
  END
END ToStringHelper;

(* Copies the characters of r into s, 0X-terminated, truncating if it
   does not fit (the same silent-cut convention as ArgParser.String /
   ArgParser.MaxStringLength). *)
PROCEDURE ToString*(r: Rope; VAR s: ARRAY OF CHAR);
  VAR i, cap: LONGINT;
BEGIN
  cap := LEN(s) - 1;
  i := 0;
  ToStringHelper(r, s, i, cap);
  s[i] := 0X
END ToString;

(* The characters of s up to its terminating 0X, or all of s if it has
   none.  NIL for an empty string. *)
PROCEDURE FromString*(s: ARRAY OF CHAR): Rope;
  VAR len: LONGINT;
BEGIN
  len := StrLen(s);
  IF len = 0 THEN RETURN NIL END;
  RETURN NewLeaf(s, 0, len)
END FromString;

(* The characters of s[start .. start+len-1].  NIL if len <= 0.
   Precondition: 0 <= start, start + len <= LEN(s).  Traps (HALT) if
   violated. *)
PROCEDURE FromSubstring*(s: ARRAY OF CHAR; start, len: LONGINT): Rope;
BEGIN
  IF len <= 0 THEN RETURN NIL END;
  IF (start < 0) OR (start + len > LEN(s)) THEN HALT(1) END;
  RETURN NewLeaf(s, start, len)
END FromSubstring;

(* n concatenated copies of r, built with O(log n) concatenations by
   binary doubling.  NIL if r is NIL or n <= 0. *)
PROCEDURE Repeat*(r: Rope; n: LONGINT): Rope;
  VAR result, piece: Rope; count: LONGINT;
BEGIN
  IF (r = NIL) OR (n <= 0) THEN RETURN NIL END;
  result := NIL;
  piece := r;
  count := n;
  WHILE count > 0 DO
    IF count MOD 2 = 1 THEN result := Cat(result, piece) END;
    count := count DIV 2;
    IF count > 0 THEN piece := Cat(piece, piece) END
  END;
  RETURN result
END Repeat;

(* A rope of len characters, all ch.  NIL if len <= 0. *)
PROCEDURE Make*(len: LONGINT; ch: CHAR): Rope;
BEGIN
  RETURN Repeat(FromChar(ch), len)
END Make;

(* --- Head / Tail --- *)

(* The first count characters of r, padded on the right with pad if
   count exceeds Length(r).  NIL if count <= 0 -- the same "NIL means
   empty" convention Make above uses for its own len <= 0 case.  Ported
   back from the Ada Ropes package (Ropes.Head, itself modeled there on
   Ada.Strings.Unbounded.Head) -- a genuine extension beyond this
   module's own original scope. *)
PROCEDURE Head*(r: Rope; count: LONGINT; pad: CHAR): Rope;
BEGIN
  IF count <= 0 THEN RETURN NIL END;
  IF count <= Length(r) THEN RETURN Substring(r, 0, count) END;
  RETURN Cat(r, Make(count - Length(r), pad))
END Head;

(* The last count characters of r, padded on the left with pad if count
   exceeds Length(r).  NIL if count <= 0.  Ropes.Tail's counterpart. *)
PROCEDURE Tail*(r: Rope; count: LONGINT; pad: CHAR): Rope;
BEGIN
  IF count <= 0 THEN RETURN NIL END;
  IF count <= Length(r) THEN RETURN Substring(r, Length(r) - count, count) END;
  RETURN Cat(Make(count - Length(r), pad), r)
END Tail;

(* --- Map --- *)

PROCEDURE MapHelper(r: Rope; f: Mapper): Rope;
  VAR leaf, newLeaf: Leaf; c: Concat; i: LONGINT; left, right: Rope;
BEGIN
  IF r = NIL THEN RETURN NIL END;
  IF r IS Leaf THEN
    leaf := r(Leaf);
    NEW(newLeaf);
    NEW(newLeaf.chars, leaf.length);
    FOR i := 0 TO leaf.length - 1 DO newLeaf.chars[i] := f(leaf.chars[i]) END;
    newLeaf.length := leaf.length;
    newLeaf.depth := 0;
    RETURN newLeaf
  END;
  c := r(Concat);
  left := MapHelper(c.left, f);
  right := MapHelper(c.right, f);
  RETURN NewConcat(left, right)
END MapHelper;

(* r with f applied to every character, in increasing index order.  The
   result has the same tree shape as r (same Depth, no Balance needed).
   NIL if r is NIL. *)
PROCEDURE Map*(r: Rope; f: Mapper): Rope;
BEGIN
  RETURN MapHelper(r, f)
END Map;

PROCEDURE MapiHelper(r: Rope; f: IndexedMapper; VAR idx: LONGINT): Rope;
  VAR leaf, newLeaf: Leaf; c: Concat; i: LONGINT; left, right: Rope;
BEGIN
  IF r = NIL THEN RETURN NIL END;
  IF r IS Leaf THEN
    leaf := r(Leaf);
    NEW(newLeaf);
    NEW(newLeaf.chars, leaf.length);
    FOR i := 0 TO leaf.length - 1 DO
      newLeaf.chars[i] := f(idx, leaf.chars[i]);
      INC(idx)
    END;
    newLeaf.length := leaf.length;
    newLeaf.depth := 0;
    RETURN newLeaf
  END;
  c := r(Concat);
  left := MapiHelper(c.left, f, idx);
  right := MapiHelper(c.right, f, idx);
  RETURN NewConcat(left, right)
END MapiHelper;

(* Same as Map, but f is also passed the index of the character. *)
PROCEDURE Mapi*(r: Rope; f: IndexedMapper): Rope;
  VAR idx: LONGINT;
BEGIN
  idx := 0;
  RETURN MapiHelper(r, f, idx)
END Mapi;

(* m maps every character to itself. *)
PROCEDURE IdentityMapping*(VAR m: Mapping);
  VAR i: INTEGER;
BEGIN
  FOR i := 0 TO 255 DO m.to[i] := CHR(i) END
END IdentityMapping;

(* m maps from[i] to to[i] for each i, and every other character to
   itself; from and to are taken up to their 0X.  Returns FALSE, with m
   the identity, if from and to differ in length or a character occurs in
   from twice -- where Ada.Strings.Maps.To_Mapping raises
   Translation_Error. *)
PROCEDURE MakeMapping*(from, to: ARRAY OF CHAR; VAR m: Mapping): BOOLEAN;
  VAR i, len: LONGINT; seen: CharSet;
BEGIN
  IdentityMapping(m);
  len := StrLen(from);
  IF StrLen(to) # len THEN RETURN FALSE END;
  MakeCharSet("", seen);
  FOR i := 0 TO len - 1 DO
    IF seen.has[ORD(from[i])] THEN IdentityMapping(m); RETURN FALSE END;
    seen.has[ORD(from[i])] := TRUE;
    m.to[ORD(from[i])] := to[i]
  END;
  RETURN TRUE
END MakeMapping;

PROCEDURE TranslateHelper(r: Rope; VAR m: Mapping): Rope;
  VAR leaf, newLeaf: Leaf; c: Concat; i: LONGINT;
BEGIN
  IF r = NIL THEN RETURN NIL END;
  IF r IS Leaf THEN
    leaf := r(Leaf);
    NEW(newLeaf);
    NEW(newLeaf.chars, leaf.length);
    FOR i := 0 TO leaf.length - 1 DO newLeaf.chars[i] := m.to[ORD(leaf.chars[i])] END;
    newLeaf.length := leaf.length;
    newLeaf.depth := 0;
    RETURN newLeaf
  END;
  c := r(Concat);
  RETURN NewConcat(TranslateHelper(c.left, m), TranslateHelper(c.right, m))
END TranslateHelper;

(* r with every character ch replaced by m.to[ORD(ch)] -- Map, with a
   table in place of a Mapper, and the same tree shape as r.  VAR only so
   that m is not copied; it is not changed.  Ported back from the Ada
   Ropes package (Ada.Strings.Unbounded's Translate with a
   Character_Mapping; its Character_Mapping_Function form is Map
   itself). *)
PROCEDURE Translate*(r: Rope; VAR m: Mapping): Rope;
BEGIN
  RETURN TranslateHelper(r, m)
END Translate;

(* --- ASCII case --- *)

(* r with every ASCII lowercase letter translated to uppercase; other
   characters, including accented letters, are left unchanged. *)
PROCEDURE UppercaseAscii*(r: Rope): Rope;
BEGIN
  RETURN Map(r, UpperChar)
END UppercaseAscii;

(* r with every ASCII uppercase letter translated to lowercase; other
   characters are left unchanged. *)
PROCEDURE LowercaseAscii*(r: Rope): Rope;
BEGIN
  RETURN Map(r, LowerChar)
END LowercaseAscii;

(* r with its first character uppercased (ASCII only); the rest is
   unchanged.  NIL is NIL. *)
PROCEDURE CapitalizeAscii*(r: Rope): Rope;
BEGIN
  IF r = NIL THEN RETURN NIL END;
  RETURN Cat(FromChar(UpperChar(Fetch(r, 0))), Substring(r, 1, Length(r) - 1))
END CapitalizeAscii;

(* r with its first character lowercased (ASCII only); the rest is
   unchanged.  NIL is NIL. *)
PROCEDURE UncapitalizeAscii*(r: Rope): Rope;
BEGIN
  IF r = NIL THEN RETURN NIL END;
  RETURN Cat(FromChar(LowerChar(Fetch(r, 0))), Substring(r, 1, Length(r) - 1))
END UncapitalizeAscii;

(* --- Trim --- *)

PROCEDURE IsSpace(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 9X) OR (ch = 0AX) OR (ch = 0CX) OR (ch = 0DX)
END IsSpace;

(* r with leading whitespace (space, tab, newline, carriage return, form
   feed) removed. *)
PROCEDURE TrimLeft*(r: Rope): Rope;
  VAR i, len: LONGINT;
BEGIN
  len := Length(r);
  i := 0;
  WHILE (i < len) & IsSpace(Fetch(r, i)) DO INC(i) END;
  RETURN Substring(r, i, len - i)
END TrimLeft;

(* r with trailing whitespace removed. *)
PROCEDURE TrimRight*(r: Rope): Rope;
  VAR len: LONGINT;
BEGIN
  len := Length(r);
  WHILE (len > 0) & IsSpace(Fetch(r, len - 1)) DO DEC(len) END;
  RETURN Substring(r, 0, len)
END TrimRight;

(* r with both leading and trailing whitespace removed. *)
PROCEDURE Trim*(r: Rope): Rope;
BEGIN
  RETURN TrimLeft(TrimRight(r))
END Trim;

(* --- Escaping --- *)

(* Appends buf[0 .. n-1] to acc as one leaf and resets n to 0; nothing if
   n = 0.  Shared by Escape and ReadLine/ReadLineRider, which all build a
   rope a buffer's worth at a time. *)
PROCEDURE FlushChunk(VAR acc: Rope; VAR buf: ARRAY OF CHAR; VAR n: LONGINT);
BEGIN
  IF n > 0 THEN acc := Cat(acc, NewLeaf(buf, 0, n)); n := 0 END
END FlushChunk;

(* Appends ch's escaped form (see Escape) to buf at n, advancing n.  At
   most 4 characters, so there must be room for that many. *)
PROCEDURE PutEscaped(ch: CHAR; VAR buf: ARRAY OF CHAR; VAR n: LONGINT);
  VAR v: INTEGER;
BEGIN
  IF (ch = "\") OR (ch = '"') OR (ch = 0AX) OR (ch = 09X) OR (ch = 0DX) THEN
    buf[n] := "\"; INC(n);
    IF ch = 0AX THEN buf[n] := "n"
    ELSIF ch = 09X THEN buf[n] := "t"
    ELSIF ch = 0DX THEN buf[n] := "r"
    ELSE buf[n] := ch
    END;
    INC(n)
  ELSIF (ORD(ch) < 32) OR (ORD(ch) >= 127) THEN
    v := ORD(ch);
    buf[n] := "\";
    buf[n + 1] := CHR(ORD("0") + v DIV 100);
    buf[n + 2] := CHR(ORD("0") + (v DIV 10) MOD 10);
    buf[n + 3] := CHR(ORD("0") + v MOD 10);
    INC(n, 4)
  ELSE
    buf[n] := ch; INC(n)
  END
END PutEscaped;

PROCEDURE EscapeHelper(r: Rope; VAR acc: Rope; VAR buf: ARRAY OF CHAR; VAR n: LONGINT);
  VAR c: Concat; leaf: Leaf; i: LONGINT;
BEGIN
  IF r = NIL THEN RETURN END;
  IF r IS Leaf THEN
    leaf := r(Leaf);
    FOR i := 0 TO leaf.length - 1 DO
      IF n > LEN(buf) - 4 THEN FlushChunk(acc, buf, n) END;
      PutEscaped(leaf.chars[i], buf, n)
    END
  ELSE
    c := r(Concat);
    EscapeHelper(c.left, acc, buf, n);
    EscapeHelper(c.right, acc, buf, n)
  END
END EscapeHelper;

(* r with backslash, double quote, newline, tab and carriage return
   replaced by their two-character backslash escapes, and any other
   non-printable character (ORD(ch) < 32 or >= 127) replaced by a
   backslash followed by its three-digit decimal code.  Linear: walks
   r's leaves directly and builds the result a buffer's worth
   (FileChunk characters) at a time, instead of a Fetch from the root and
   a Cat per character.  Named Escaped until the Ada Ropes port's
   Escape was ported back: a verb, like every other operation here. *)
PROCEDURE Escape*(r: Rope): Rope;
  VAR acc: Rope; buf: ARRAY FileChunk OF CHAR; n: LONGINT;
BEGIN
  acc := NIL;
  n := 0;
  EscapeHelper(r, acc, buf, n);
  FlushChunk(acc, buf, n);
  RETURN acc
END Escape;

(* --- Input and output --- *)

PROCEDURE WriteHelper(r: Rope);
  VAR c: Concat; leaf: Leaf; i: LONGINT;
BEGIN
  IF r = NIL THEN RETURN END;
  IF r IS Leaf THEN
    leaf := r(Leaf);
    (* Out.Char, not Out.String: a leaf has no 0X terminator and may
       contain 0X characters itself, and Out.String stops at the first. *)
    FOR i := 0 TO leaf.length - 1 DO Out.Char(leaf.chars[i]) END
  ELSE
    c := r(Concat);
    WriteHelper(c.left);
    WriteHelper(c.right)
  END
END WriteHelper;

(* Writes r's characters to standard output, through Out, leaf by leaf --
   never truncated, unlike ToString into a fixed buffer followed by
   Out.String.  Ends with Out.Flush: voc's Out only flushes at a line
   feed, and not at all when the program ends, so without it a rope
   written with no line feed after it would never appear. *)
PROCEDURE Write*(r: Rope);
BEGIN
  WriteHelper(r);
  Out.Flush
END Write;

PROCEDURE WriteRiderHelper(VAR w: Files.Rider; r: Rope);
  VAR c: Concat; leaf: Leaf;
BEGIN
  IF r = NIL THEN RETURN END;
  IF r IS Leaf THEN
    leaf := r(Leaf);
    Files.WriteBytes(w, leaf.chars^, leaf.length)
  ELSE
    c := r(Concat);
    WriteRiderHelper(w, c.left);
    WriteRiderHelper(w, c.right)
  END
END WriteRiderHelper;

(* Writes r's characters at w's position, advancing it, one
   Files.WriteBytes per leaf.  Takes a Rider rather than a Files.File
   because the Rider is what carries the position: to append to f, first
   Files.Set(w, f, Files.Length(f)). *)
PROCEDURE WriteRider*(VAR w: Files.Rider; r: Rope);
BEGIN
  WriteRiderHelper(w, r)
END WriteRider;

(* Reads the next line of standard input, through In, into line, without
   its line feed (a carriage return before it is kept, as on any
   character-level Unix read).  TRUE if a line was read -- including an
   empty one, which gives NIL, and a last line with no line feed after
   it; FALSE, with line = NIL, only at end of input with nothing left to
   read.  So: WHILE Ropes.ReadLine(line) DO ... END. *)
PROCEDURE ReadLine*(VAR line: Rope): BOOLEAN;
  VAR buf: ARRAY LineChunk OF CHAR; n: LONGINT; ch: CHAR; any: BOOLEAN;
BEGIN
  line := NIL; n := 0; any := FALSE;
  In.Char(ch);
  WHILE In.Done & (ch # 0AX) DO
    any := TRUE;
    buf[n] := ch; INC(n);
    IF n = LineChunk THEN FlushChunk(line, buf, n) END;
    In.Char(ch)
  END;
  FlushChunk(line, buf, n);
  RETURN In.Done OR any
END ReadLine;

(* Like ReadLine, but from rd, advancing it; FALSE (with rd.eof) only at
   end of file with nothing left to read. *)
PROCEDURE ReadLineRider*(VAR rd: Files.Rider; VAR line: Rope): BOOLEAN;
  VAR buf: ARRAY LineChunk OF CHAR; n: LONGINT; ch: CHAR; any: BOOLEAN;
BEGIN
  line := NIL; n := 0; any := FALSE;
  Files.Read(rd, ch);
  WHILE ~rd.eof & (ch # 0AX) DO
    any := TRUE;
    buf[n] := ch; INC(n);
    IF n = LineChunk THEN FlushChunk(line, buf, n) END;
    Files.Read(rd, ch)
  END;
  FlushChunk(line, buf, n);
  RETURN ~rd.eof OR any
END ReadLineRider;

(* Everything from rd's position to the end of its file, byte for byte --
   no line feeds added, dropped or translated, unlike reading it line by
   line with ReadLineRider, which cannot tell whether the last line had a
   line feed after it.  NIL if there is nothing left.  Reads eagerly: this
   is not a lazy, file-backed rope (see the module comment). *)
PROCEDURE ReadAll*(VAR rd: Files.Rider): Rope;
  VAR buf: ARRAY FileChunk OF CHAR; r: Rope; n: LONGINT;
BEGIN
  r := NIL;
  REPEAT
    Files.ReadBytes(rd, buf, FileChunk);
    n := FileChunk - rd.res;  (* rd.res is how many of the FileChunk bytes were NOT read. *)
    IF n > 0 THEN r := Cat(r, NewLeaf(buf, 0, n)) END
  UNTIL rd.eof;
  RETURN r
END ReadAll;

(* Sets r to the whole of the file named name, byte for byte (see
   ReadAll), and returns TRUE; or, if there is no such file (Files.Old
   gives NIL), sets r to NIL and returns FALSE.  A BOOLEAN rather than
   just a NIL result because NIL is also the whole of an empty file. *)
PROCEDURE ReadFile*(name: ARRAY OF CHAR; VAR r: Rope): BOOLEAN;
  VAR f: Files.File; rd: Files.Rider;
BEGIN
  r := NIL;
  f := Files.Old(name);
  IF f = NIL THEN RETURN FALSE END;
  Files.Set(rd, f, 0);
  r := ReadAll(rd);
  Files.Close(f);
  RETURN TRUE
END ReadFile;

(* Creates the file named name, or replaces an existing one, containing
   exactly r's characters (see WriteRider): Files.New, then
   Files.Register.  Like Files.Register itself, HALTs (99) if the file
   cannot be put in place -- there is no failure result to return. *)
PROCEDURE WriteFile*(name: ARRAY OF CHAR; r: Rope);
  VAR f: Files.File; w: Files.Rider;
BEGIN
  f := Files.New(name);
  Files.Set(w, f, 0);
  WriteRider(w, r);
  Files.Register(f)
END WriteFile;

BEGIN
  InitMinLength
END Ropes.
