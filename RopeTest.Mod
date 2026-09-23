MODULE RopeTest;

(* A battery of fixed checks against Rope.Mod, printed as "ok - NAME" /
   "not ok - NAME" lines plus a final summary, and HALT(1) if anything
   failed, so tests/run-tests.sh's exit-status comparison catches a
   regression even if the output itself is not read. *)

IMPORT Out, Rope;

VAR
  passed, failed: LONGINT;
  splitCount: LONGINT;
  splitBuf: ARRAY 8 OF ARRAY 16 OF CHAR;

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

PROCEDURE CheckOverwrite;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("hello world");

  Check(StrEq(Rope.Overwrite(r, 6, Rope.FromString("there")), "hello there"), "Overwrite replaces characters in the middle");
  Check(StrEq(Rope.Overwrite(r, 0, Rope.FromString("HELLO")), "HELLO world"), "Overwrite at the start");
  Check(StrEq(Rope.Overwrite(r, 11, Rope.FromString("!")), "hello world!"), "Overwrite past the end appends");
  Check(StrEq(Rope.Overwrite(r, 6, Rope.FromString("there, universe")), "hello there, universe"),
        "Overwrite extends past the original end");
  Check(StrEq(Rope.Overwrite(r, 100, Rope.FromString("!")), "hello world!"), "Overwrite clamps a too-large pos to the end");
  Check(StrEq(Rope.Overwrite(r, -5, Rope.FromString(">> ")), ">> lo world"), "Overwrite clamps a negative pos to the start");

  Check(StrEq(Rope.Overwrite(NIL, 0, Rope.FromString("x")), "x"), "Overwrite into NIL is just the new rope");
  Check(StrEq(Rope.Overwrite(r, 5, NIL), "hello world"), "Overwrite of NIL leaves the rope unchanged");
  Check(Rope.Overwrite(NIL, 0, NIL) = NIL, "Overwrite of NIL into NIL is NIL");

  Check(Rope.Length(Rope.Overwrite(r, 6, Rope.FromString("there"))) = 11, "Overwrite: resulting length");
END CheckOverwrite;

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

PROCEDURE CheckFromCharAndMake;
  VAR r: Rope.Rope;
BEGIN
  Check(StrEq(Rope.FromChar("x"), "x"), "FromChar builds a one-character rope");
  Check(Rope.Length(Rope.FromChar("x")) = 1, "FromChar: length");

  r := Rope.FromSubstring("hello world", 6, 5);
  Check(StrEq(r, "world"), "FromSubstring: content");
  Check(Rope.FromSubstring("hello", 0, 0) = NIL, "FromSubstring of length 0 is NIL");

  r := Rope.Make(5, "z");
  Check(StrEq(r, "zzzzz"), "Make: content");
  Check(Rope.Make(0, "z") = NIL, "Make of length 0 is NIL");
  Check(Rope.Make(-1, "z") = NIL, "Make of negative length is NIL");
END CheckFromCharAndMake;

PROCEDURE CheckHeadTail;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("hello");

  Check(StrEq(Rope.Head(r, 3, " "), "hel"), "Head takes the first COUNT characters");
  Check(StrEq(Rope.Head(r, 5, " "), "hello"), "Head of exactly Length(r) characters is r itself");
  Check(StrEq(Rope.Head(r, 8, "."), "hello..."), "Head pads on the right when COUNT exceeds Length(r)");
  Check(Rope.Head(r, 0, " ") = NIL, "Head of 0 characters is NIL");
  Check(Rope.Head(r, -1, " ") = NIL, "Head of a negative COUNT is NIL");
  Check(StrEq(Rope.Head(NIL, 3, "x"), "xxx"), "Head of NIL is COUNT copies of pad");

  Check(StrEq(Rope.Tail(r, 3, " "), "llo"), "Tail takes the last COUNT characters");
  Check(StrEq(Rope.Tail(r, 5, " "), "hello"), "Tail of exactly Length(r) characters is r itself");
  Check(StrEq(Rope.Tail(r, 8, "."), "...hello"), "Tail pads on the left when COUNT exceeds Length(r)");
  Check(Rope.Tail(r, 0, " ") = NIL, "Tail of 0 characters is NIL");
  Check(Rope.Tail(r, -1, " ") = NIL, "Tail of a negative COUNT is NIL");
  Check(StrEq(Rope.Tail(NIL, 3, "x"), "xxx"), "Tail of NIL is COUNT copies of pad");
END CheckHeadTail;

PROCEDURE CheckOverflowGuard;
  VAR r: Rope.Rope;
BEGIN
  (* Exactly at the boundary: (MAX(LONGINT) - 1) + 1 = MAX(LONGINT), which
     must succeed -- only a combined length that would exceed
     MAX(LONGINT) should HALT.  This is cheap even at this size: Repeat's
     binary doubling shares subtrees instead of allocating MAX(LONGINT)
     real characters.  The over-the-boundary case can't be a Check here
     -- it HALTs the whole process by design, so it's covered instead by
     tests/rope-bigcat-overflow.test, which expects exactly that. *)
  r := Rope.Cat(Rope.Repeat(Rope.FromChar("x"), MAX(LONGINT) - 1), Rope.FromChar("y"));
  Check(Rope.Length(r) = MAX(LONGINT), "Cat right at the LONGINT boundary succeeds");
END CheckOverflowGuard;

PROCEDURE ShiftMapper(ch: CHAR): CHAR;
BEGIN
  RETURN CHR(ORD(ch) + 1)
END ShiftMapper;

PROCEDURE IndexDigitMapper(i: LONGINT; ch: CHAR): CHAR;
BEGIN
  RETURN CHR(ORD("0") + SHORT(i MOD 10))
END IndexDigitMapper;

PROCEDURE CheckMap;
  VAR r, mapped: Rope.Rope;
BEGIN
  r := Rope.FromString("abc");
  Check(StrEq(Rope.Map(r, ShiftMapper), "bcd"), "Map shifts every character");
  Check(Rope.Map(NIL, ShiftMapper) = NIL, "Map of NIL is NIL");

  (* Two tree nodes (left leaf is 16 chars), so Mapi's threaded index has
     to survive the recursion into the right child. *)
  r := Rope.Cat(Rope.FromString("0123456789012345"), Rope.FromString("abcdefghij"));
  mapped := Rope.Map(r, ShiftMapper);
  Check(Rope.Depth(mapped) = Rope.Depth(r), "Map preserves tree shape (same Depth)");

  mapped := Rope.Mapi(r, IndexDigitMapper);
  Check(StrEq(mapped, "01234567890123456789012345"), "Mapi: index threads correctly across a Concat node");
END CheckMap;

PROCEDURE CheckAsciiCase;
BEGIN
  Check(StrEq(Rope.UppercaseAscii(Rope.FromString("Hello, World! 123")), "HELLO, WORLD! 123"), "UppercaseAscii");
  Check(StrEq(Rope.LowercaseAscii(Rope.FromString("Hello, World! 123")), "hello, world! 123"), "LowercaseAscii");
  Check(StrEq(Rope.CapitalizeAscii(Rope.FromString("hello")), "Hello"), "CapitalizeAscii");
  Check(StrEq(Rope.UncapitalizeAscii(Rope.FromString("Hello")), "hello"), "UncapitalizeAscii");
  Check(Rope.CapitalizeAscii(NIL) = NIL, "CapitalizeAscii of NIL is NIL");
  Check(Rope.UncapitalizeAscii(NIL) = NIL, "UncapitalizeAscii of NIL is NIL");
END CheckAsciiCase;

PROCEDURE CheckTrim;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("  hello world  ");
  Check(StrEq(Rope.TrimLeft(r), "hello world  "), "TrimLeft");
  Check(StrEq(Rope.TrimRight(r), "  hello world"), "TrimRight");
  Check(StrEq(Rope.Trim(r), "hello world"), "Trim");
  Check(Rope.Trim(Rope.FromString("   ")) = NIL, "Trim of all-whitespace is NIL");
  Check(Rope.Trim(NIL) = NIL, "Trim of NIL is NIL");
  Check(StrEq(Rope.Trim(Rope.FromString("no-trim-needed")), "no-trim-needed"),
        "Trim leaves a rope with no padding unchanged");
END CheckTrim;

PROCEDURE CheckEscaped;
  VAR r: Rope.Rope; buf: ARRAY 3 OF CHAR;
BEGIN
  Check(StrEq(Rope.Escaped(Rope.FromString('say "hi"')), 'say \"hi\"'), "Escaped: double quote");

  buf[0] := "a"; buf[1] := 9X; buf[2] := 0X;
  r := Rope.FromString(buf);
  Check(StrEq(Rope.Escaped(r), "a\t"), "Escaped: tab");

  Check(StrEq(Rope.Escaped(Rope.FromString("\")), "\\"), "Escaped: backslash");
  Check(Rope.Escaped(NIL) = NIL, "Escaped of NIL is NIL");
END CheckEscaped;

PROCEDURE CheckIndexCharAndRFind;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("abcabc");
  Check(Rope.IndexChar(r, "b", 0) = 1, "IndexChar: first occurrence");
  Check(Rope.IndexChar(r, "b", 2) = 4, "IndexChar: from an offset");
  Check(Rope.IndexChar(r, "z", 0) = -1, "IndexChar: not present");
  Check(Rope.RIndexChar(r, "b", 5) = 4, "RIndexChar: last occurrence");
  Check(Rope.RIndexChar(r, "b", 3) = 1, "RIndexChar: before an offset");
  Check(Rope.RIndexChar(r, "z", 5) = -1, "RIndexChar: not present");
  Check(Rope.Contains(r, "c", 0), "Contains: present");
  Check(~Rope.Contains(r, "z", 0), "Contains: not present");

  (* "World" occurs at 7 and again at 14. *)
  r := Rope.Cat(Rope.FromString("Hello, "), Rope.FromString("World! World!"));
  Check(Rope.RFind(r, "World", Rope.Length(r)) = 14, "RFind: last occurrence searching the whole rope");
  Check(Rope.RFind(r, "World", 13) = 7, "RFind: a bound excludes a later occurrence");
  Check(Rope.RFind(r, "xyz", Rope.Length(r)) = -1, "RFind: not present");
  Check(Rope.RFind(r, "", Rope.Length(r)) = Rope.Length(r), "RFind: empty pattern matches at the bound");
END CheckIndexCharAndRFind;

PROCEDURE CheckContainsPattern;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("hello world");

  Check(Rope.ContainsPattern(r, "world", 0), "ContainsPattern: present");
  Check(~Rope.ContainsPattern(r, "xyz", 0), "ContainsPattern: not present");
  Check(Rope.ContainsPattern(r, "hello", 0), "ContainsPattern: present at the very start");
  Check(Rope.ContainsPattern(r, "o", 5), "ContainsPattern: from an offset, still present");
  Check(~Rope.ContainsPattern(r, "hello", 5), "ContainsPattern: from an offset excludes an earlier occurrence");
  Check(Rope.ContainsPattern(r, "", 0), "ContainsPattern: the empty pattern always matches");
  Check(~Rope.ContainsPattern(NIL, "x", 0), "ContainsPattern: not present in NIL (non-empty pattern)");
  Check(Rope.ContainsPattern(NIL, "", 0), "ContainsPattern: the empty pattern matches even in NIL");
END CheckContainsPattern;

PROCEDURE CheckBlit;
  VAR r: Rope.Rope; buf: ARRAY 11 OF CHAR;
BEGIN
  r := Rope.FromString("hello world");
  buf := "XXXXXXXXXX";
  Rope.Blit(r, 6, buf, 2, 5);
  Check((buf[0] = "X") & (buf[1] = "X") & (buf[2] = "w") & (buf[6] = "d") & (buf[7] = "X"),
        "Blit copies into the middle of dst without touching the rest");
END CheckBlit;

PROCEDURE CollectPiece(piece: Rope.Rope): BOOLEAN;
BEGIN
  IF splitCount < LEN(splitBuf) THEN
    Rope.ToString(piece, splitBuf[splitCount]);
    INC(splitCount)
  END;
  RETURN TRUE
END CollectPiece;

PROCEDURE StopAfterTwo(piece: Rope.Rope): BOOLEAN;
BEGIN
  IF splitCount < LEN(splitBuf) THEN
    Rope.ToString(piece, splitBuf[splitCount]);
    INC(splitCount)
  END;
  RETURN splitCount < 2
END StopAfterTwo;

PROCEDURE CheckSplit;
  VAR r: Rope.Rope; arr: Rope.Pieces; node: Rope.Piece;
BEGIN
  r := Rope.FromString("a,b,,c");

  splitCount := 0;
  Rope.Split(r, ",", CollectPiece);
  Check(splitCount = 4, "Split: visits every piece, including an empty one");
  Check((splitBuf[0] = "a") & (splitBuf[1] = "b") & (splitBuf[2] = "") & (splitBuf[3] = "c"),
        "Split: piece contents in order");

  splitCount := 0;
  Rope.Split(r, ",", StopAfterTwo);
  Check(splitCount = 2, "Split: stops early when visit returns FALSE");

  splitCount := 0;
  Rope.Split(NIL, ",", CollectPiece);
  Check((splitCount = 1) & (splitBuf[0] = ""), "Split of NIL gives one empty piece");

  splitCount := 0;
  Rope.Split(Rope.FromString("abc"), ",", CollectPiece);
  Check((splitCount = 1) & (splitBuf[0] = "abc"), "Split with an absent separator gives one piece: the whole rope");

  splitCount := 0;
  Rope.Split(Rope.FromString("abc"), "", CollectPiece);
  Check((splitCount = 1) & (splitBuf[0] = "abc"), "Split with an empty separator never splits");

  arr := Rope.SplitArray(r, ",");
  Check(LEN(arr^) = 4, "SplitArray: piece count");
  Check(StrEq(arr[0], "a") & StrEq(arr[1], "b") & StrEq(arr[2], "") & StrEq(arr[3], "c"),
        "SplitArray: piece contents in order");

  node := Rope.SplitList(r, ",");
  Check(StrEq(node.rope, "a"), "SplitList: first piece");
  node := node.next;
  Check(StrEq(node.rope, "b"), "SplitList: second piece");
  node := node.next;
  Check(node.rope = NIL, "SplitList: third (empty) piece is NIL");
  node := node.next;
  Check(StrEq(node.rope, "c"), "SplitList: fourth piece");
  node := node.next;
  Check(node = NIL, "SplitList: list ends after the last piece");
END CheckSplit;

PROCEDURE CheckIterator;
  VAR r: Rope.Rope; it: Rope.Iterator; i: LONGINT; ok: BOOLEAN;
BEGIN
  (* Two tree nodes: the first leaf is 16 characters, so position 15 is
     its last and position 16 crosses into the second leaf. *)
  r := Rope.Cat(Rope.FromString("0123456789012345"), Rope.FromString("abcdefghij"));

  it := Rope.NewIterator(r, 0);
  Check(it.Pos() = 0, "NewIterator: initial position");
  Check(it.Get() = "0", "Iterator.Get at the start");
  it.Incr;
  Check(it.Get() = "1", "Iterator.Incr moves forward");
  it.Goto(15);
  Check(it.Get() = "5", "Iterator.Goto: last character of the first leaf");
  it.Incr;
  Check(it.Get() = "a", "Iterator.Get after crossing into the second leaf");
  it.Decr;
  Check(it.Get() = "5", "Iterator.Decr moves back across the leaf boundary");
  it.Move(10);
  Check(it.Get() = "j", "Iterator.Move: last character of the rope");
  Check(it.Source() = r, "Iterator.Source returns the rope it was made from");
  Check(it.Peek(0) = "0", "Iterator.Peek an arbitrary earlier position");
  Check(it.Pos() = 25, "Iterator.Peek does not change the current position");

  it := Rope.NewIterator(r, 0);
  ok := TRUE;
  i := 0;
  WHILE ok & (i < Rope.Length(r)) DO
    IF it.Get() # Rope.Fetch(r, i) THEN ok := FALSE END;
    it.Incr;
    INC(i)
  END;
  Check(ok, "Iterator: walking forward matches Fetch at every position");
END CheckIterator;

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
  CheckOverwrite;
  CheckCompareFindRepeat;
  CheckStressAndBalance;
  CheckFromCharAndMake;
  CheckHeadTail;
  CheckOverflowGuard;
  CheckMap;
  CheckAsciiCase;
  CheckTrim;
  CheckEscaped;
  CheckIndexCharAndRFind;
  CheckContainsPattern;
  CheckBlit;
  CheckSplit;
  CheckIterator;
  Summary
END RopeTest.
