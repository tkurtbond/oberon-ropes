MODULE RopeTest;

(* A battery of fixed checks against Rope.Mod, printed as "ok - NAME" /
   "not ok - NAME" lines plus a final summary, and HALT(1) if anything
   failed, so tests/run-tests.sh's exit-status comparison catches a
   regression even if the output itself is not read. *)

IMPORT Out, Rope;

VAR
  passed, failed: LONGINT;

PROCEDURE Check(cond: BOOLEAN; name: ARRAY OF CHAR);
BEGIN
  IF cond THEN
    Out.String("ok - "); Out.String(name); Out.Ln;
    INC(passed)
  ELSE
    Out.String("not ok - "); Out.String(name); Out.Ln;
    INC(failed)
  END
END Check;

PROCEDURE ToStr(r: Rope.Rope; VAR s: ARRAY OF CHAR);
BEGIN
  Rope.ToString(r, s)
END ToStr;

PROCEDURE StrEq(r: Rope.Rope; expect: ARRAY OF CHAR): BOOLEAN;
  VAR buf: ARRAY 4096 OF CHAR;
BEGIN
  ToStr(r, buf);
  RETURN buf = expect
END StrEq;

PROCEDURE CheckConstruction;
  VAR r: Rope.Rope; buf: ARRAY 16 OF CHAR;
BEGIN
  Check(Rope.FromString("") = NIL, "FromString of an empty string is NIL");
  Check(Rope.IsEmpty(NIL), "IsEmpty(NIL)");
  Check(~Rope.IsEmpty(Rope.FromString("x")), "~IsEmpty(FromString(x))");

  r := Rope.FromString("hello");
  Check(StrEq(r, "hello"), "FromString/ToString round trip");
  Check(Rope.Length(r) = 5, "Length of FromString(hello)");

  Rope.ToString(NIL, buf);
  Check(buf = "", "ToString(NIL) gives an empty string");

  r := Rope.FromString("this does not fit in a tiny buffer");
  Rope.ToString(r, buf);
  Check(buf = "this does not f", "ToString truncates to fit, like ArgParser.String");
END CheckConstruction;

PROCEDURE CheckLengthAndFetch;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("abcde");
  Check(Rope.Length(r) = 5, "Length");
  Check(Rope.Fetch(r, 0) = "a", "Fetch first character");
  Check(Rope.Fetch(r, 4) = "e", "Fetch last character");
  Check(Rope.Length(NIL) = 0, "Length(NIL) = 0");
END CheckLengthAndFetch;

PROCEDURE CheckCat;
  VAR a, b, r: Rope.Rope;
BEGIN
  a := Rope.FromString("foo");
  Check(Rope.Cat(NIL, a) = a, "Cat(NIL, x) = x");
  Check(Rope.Cat(a, NIL) = a, "Cat(x, NIL) = x");

  (* Both short leaves: merges into one leaf (depth 0). *)
  a := Rope.FromString("ab");
  b := Rope.FromString("cd");
  r := Rope.Cat(a, b);
  Check(StrEq(r, "abcd"), "Cat of two short leaves: content");
  Check(Rope.Depth(r) = 0, "Cat of two short leaves merges into one leaf");

  (* Absorbing into a Concat's short-leaf right child: still depth 1, not 2.
     The right leaf ("01234", 5 chars) has room left under ShortLeafLength
     (16), so appending "x" merges into it instead of adding a level. *)
  r := Rope.Cat(r, Rope.FromString("0123456789012345"));  (* forces a real Concat: combined > ShortLeafLength *)
  Check(Rope.Depth(r) = 1, "First concat past the short-leaf limit has depth 1");
  r := Rope.Cat(r, Rope.FromString("01234"));
  Check(Rope.Depth(r) = 2, "Second concat past the short-leaf limit has depth 2");
  r := Rope.Cat(r, Rope.FromString("x"));
  Check(StrEq(r, "abcd012345678901234501234x"), "Absorbing a short leaf: content");
  Check(Rope.Depth(r) = 2, "Absorbing a short leaf keeps depth from growing");

  (* Two large leaves: an ordinary Concat node, depth 1. *)
  a := Rope.FromString("0123456789012345");
  b := Rope.FromString("9876543210987654");
  r := Rope.Cat(a, b);
  Check(StrEq(r, "01234567890123459876543210987654"), "Cat of two large leaves: content");
  Check(Rope.Depth(r) = 1, "Cat of two large leaves has depth 1");
END CheckCat;

PROCEDURE CheckSubstring;
  VAR r, s: Rope.Rope;
BEGIN
  r := Rope.Cat(Rope.FromString("0123456789012345"), Rope.FromString("abcdefghij"));

  s := Rope.Substring(r, 0, Rope.Length(r));
  Check(StrEq(s, "0123456789012345abcdefghij"), "Substring of the whole rope");

  s := Rope.Substring(r, 3, 0);
  Check(s = NIL, "Substring of length 0 is NIL");

  s := Rope.Substring(r, -5, 8);
  Check(StrEq(s, "01234567"), "Substring clamps a negative start");

  s := Rope.Substring(r, 20, 1000);
  Check(StrEq(s, "efghij"), "Substring clamps an over-length end");

  (* Spans both children of the Concat built above (left is 16 chars). *)
  s := Rope.Substring(r, 10, 10);
  Check(StrEq(s, "012345abcd"), "Substring spanning two tree nodes");

  s := Rope.Substring(r, 100, 5);
  Check(s = NIL, "Substring starting past the end is NIL");
END CheckSubstring;

PROCEDURE CheckInsert;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("hello world");

  Check(StrEq(Rope.Insert(r, 5, Rope.FromString(",")), "hello, world"), "Insert in the middle");
  Check(StrEq(Rope.Insert(r, 0, Rope.FromString(">> ")), ">> hello world"), "Insert at the start");
  Check(StrEq(Rope.Insert(r, 11, Rope.FromString("!")), "hello world!"), "Insert at the end");
  Check(StrEq(Rope.Insert(r, 100, Rope.FromString("!")), "hello world!"), "Insert clamps a too-large pos to the end");
  Check(StrEq(Rope.Insert(r, -5, Rope.FromString(">> ")), ">> hello world"), "Insert clamps a negative pos to the start");

  Check(StrEq(Rope.Insert(NIL, 0, Rope.FromString("x")), "x"), "Insert into NIL is just the inserted rope");
  Check(StrEq(Rope.Insert(r, 5, NIL), "hello world"), "Insert of NIL leaves the rope unchanged");
  Check(Rope.Insert(NIL, 0, NIL) = NIL, "Insert of NIL into NIL is NIL");

  Check(Rope.Length(Rope.Insert(r, 5, Rope.FromString(","))) = 12, "Insert: resulting length");
END CheckInsert;

PROCEDURE CheckRemove;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("hello, world");

  Check(StrEq(Rope.Remove(r, 5, 2), "helloworld"), "Remove from the middle");
  Check(StrEq(Rope.Remove(r, 0, 7), "world"), "Remove from the start");
  Check(StrEq(Rope.Remove(r, 5, 100), "hello"), "Remove clamps a too-large len to the end");
  Check(StrEq(Rope.Remove(r, 100, 5), "hello, world"), "Remove at a too-large pos removes nothing");
  Check(StrEq(Rope.Remove(r, -5, 5), ", world"), "Remove clamps a negative pos to the start");
  Check(StrEq(Rope.Remove(r, 5, -2), "hello, world"), "Remove clamps a negative len to 0");
  Check(Rope.Remove(r, 0, Rope.Length(r)) = NIL, "Remove of the whole rope is NIL");

  Check(Rope.Remove(NIL, 0, 5) = NIL, "Remove from NIL is NIL");
  Check(StrEq(Rope.Remove(r, 5, 0), "hello, world"), "Remove of length 0 leaves the rope unchanged");

  Check(Rope.Length(Rope.Remove(r, 5, 2)) = 10, "Remove: resulting length");
END CheckRemove;

PROCEDURE CheckCompareFindRepeat;
  VAR r: Rope.Rope;
BEGIN
  Check(Rope.Compare(Rope.FromString("abc"), Rope.FromString("abc")) = 0, "Compare equal ropes");
  Check(Rope.Compare(Rope.FromString("abc"), Rope.FromString("abd")) < 0, "Compare less-than");
  Check(Rope.Compare(Rope.FromString("abd"), Rope.FromString("abc")) > 0, "Compare greater-than");
  Check(Rope.Compare(Rope.FromString("ab"), Rope.FromString("abc")) < 0, "Compare: shorter prefix sorts first");
  Check(Rope.Equal(Rope.FromString("xyz"), Rope.FromString("xyz")), "Equal");
  Check(~Rope.Equal(Rope.FromString("xyz"), Rope.FromString("xy")), "~Equal");

  r := Rope.Cat(Rope.FromString("Hello, "), Rope.FromString("World!"));
  Check(Rope.Find(r, "World", 0) = 7, "Find a substring present in the rope");
  Check(Rope.Find(r, "xyz", 0) = -1, "Find a substring not present");
  Check(Rope.Find(r, "o", 5) = 8, "Find starting from an offset");
  Check(Rope.Find(r, "", 3) = 3, "Find of the empty pattern");

  r := Rope.Repeat(Rope.FromString("ab"), 4);
  Check(StrEq(r, "abababab"), "Repeat content");
  Check(Rope.Length(r) = 8, "Repeat length");
  Check(Rope.Repeat(Rope.FromString("x"), 0) = NIL, "Repeat 0 times is NIL");
  Check(Rope.Repeat(NIL, 5) = NIL, "Repeat of NIL is NIL");
END CheckCompareFindRepeat;

PROCEDURE CheckStressAndBalance;
  VAR r, balanced, wide: Rope.Rope; i: LONGINT; ok: BOOLEAN;
BEGIN
  (* Build a rope by appending one character at a time, the way a naive
     caller building up output would.  Without the short-leaf merge and
     depth-triggered auto-rebalance, this would grow one Concat level per
     character (depth ~2000); Cat.MaxDepth bounds it well below that. *)
  r := NIL;
  FOR i := 0 TO 1999 DO
    r := Rope.AppendChar(r, CHR(ORD("a") + (i MOD 26)))
  END;
  Check(Rope.Length(r) = 2000, "AppendChar x2000: length");
  Check(Rope.Fetch(r, 0) = "a", "AppendChar x2000: first character");
  Check(Rope.Fetch(r, 1999) = CHR(ORD("a") + (1999 MOD 26)), "AppendChar x2000: last character");

  ok := TRUE;
  i := 0;
  WHILE ok & (i < 2000) DO
    IF Rope.Fetch(r, i) # CHR(ORD("a") + (i MOD 26)) THEN ok := FALSE END;
    INC(i)
  END;
  Check(ok, "AppendChar x2000: every character matches");

  Check(Rope.Depth(r) < Rope.MaxDepth, "AppendChar x2000: depth stays bounded well below MaxDepth");

  balanced := Rope.Balance(r);
  Check(Rope.Equal(r, balanced), "Balance preserves content");
  Check(Rope.Depth(balanced) <= Rope.Depth(r), "Balance does not increase depth");
  Check(Rope.Depth(balanced) < 20, "Balance brings depth down close to optimal for 2000 characters");

  (* A rope built by balanced binary doubling (Repeat) should meet the
     paper's strict balance definition exactly. *)
  wide := Rope.Repeat(Rope.FromString("0123456789012345"), 200);
  Check(Rope.IsBalanced(wide), "A rope built by balanced doubling is strictly balanced");
END CheckStressAndBalance;

PROCEDURE Summary;
BEGIN
  Out.Ln;
  Out.Int(passed, 0); Out.String("/"); Out.Int(passed + failed, 0);
  Out.String(" tests passed."); Out.Ln;
  IF failed > 0 THEN HALT(1) END
END Summary;

BEGIN
  passed := 0;
  failed := 0;
  CheckConstruction;
  CheckLengthAndFetch;
  CheckCat;
  CheckSubstring;
  CheckInsert;
  CheckRemove;
  CheckCompareFindRepeat;
  CheckStressAndBalance;
  Summary
END RopeTest.
