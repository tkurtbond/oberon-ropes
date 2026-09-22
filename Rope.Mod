MODULE Rope;

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
   file-backed ropes; Substring always copies.

   This is voc-only for now: it is not built by pocGNUmakefile. *)

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
  n := a.length + b.length;
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
  c.length := left.length + right.length;
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
  IF (left IS Leaf) & (right IS Leaf) & (left.length + right.length <= ShortLeafLength) THEN
    RETURN MergeLeaves(left(Leaf), right(Leaf))
  END;
  IF (left IS Concat) & (right IS Leaf) THEN
    lc := left(Concat);
    IF (lc.right IS Leaf) & (lc.right.length + right.length <= ShortLeafLength) THEN
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

(* Still benefits from SimpleCat's short-leaf merge, so appending one
   character at a time in a loop does not grow an ever-deeper tree. *)
PROCEDURE AppendChar*(r: Rope; ch: CHAR): Rope;
  VAR one: ARRAY 1 OF CHAR;
BEGIN
  one[0] := ch;
  RETURN Cat(r, NewLeaf(one, 0, 1))
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

(* --- Comparison, search, iteration --- *)

(* <0, 0 or >0, like strcmp: lexicographic by character, then by length. *)
PROCEDURE Compare*(a, b: Rope): INTEGER;
  VAR i, n: LONGINT; ca, cb: CHAR;
BEGIN
  n := Length(a);
  IF Length(b) < n THEN n := Length(b) END;
  i := 0;
  WHILE i < n DO
    ca := Fetch(a, i);
    cb := Fetch(b, i);
    IF ca < cb THEN RETURN -1 END;
    IF ca > cb THEN RETURN 1 END;
    INC(i)
  END;
  IF Length(a) < Length(b) THEN RETURN -1 END;
  IF Length(a) > Length(b) THEN RETURN 1 END;
  RETURN 0
END Compare;

PROCEDURE Equal*(a, b: Rope): BOOLEAN;
BEGIN
  RETURN Compare(a, b) = 0
END Equal;

(* The index of the first occurrence of pattern at or after from, or -1.
   The empty pattern matches at from (clamped into [0, Length(r)]). *)
PROCEDURE Find*(r: Rope; pattern: ARRAY OF CHAR; from: LONGINT): LONGINT;
  VAR patLen, rLen, i, j: LONGINT; match: BOOLEAN;
BEGIN
  patLen := 0;
  WHILE (patLen < LEN(pattern)) & (pattern[patLen] # 0X) DO INC(patLen) END;
  rLen := Length(r);
  IF from < 0 THEN from := 0 END;
  IF patLen = 0 THEN
    IF from > rLen THEN RETURN -1 END;
    RETURN from
  END;
  i := from;
  WHILE i + patLen <= rLen DO
    match := TRUE;
    j := 0;
    WHILE match & (j < patLen) DO
      IF Fetch(r, i + j) # pattern[j] THEN match := FALSE END;
      INC(j)
    END;
    IF match THEN RETURN i END;
    INC(i)
  END;
  RETURN -1
END Find;

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
  len := 0;
  WHILE (len < LEN(s)) & (s[len] # 0X) DO INC(len) END;
  IF len = 0 THEN RETURN NIL END;
  RETURN NewLeaf(s, 0, len)
END FromString;

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

BEGIN
  InitMinLength
END Rope.
