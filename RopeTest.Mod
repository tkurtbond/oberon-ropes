MODULE RopeTest;

(* A battery of fixed checks against Ropes.Mod, printed as "ok - NAME" /
   "not ok - NAME" lines plus a final summary, and HALT(1) if anything
   failed, so tests/run-tests.sh's exit-status comparison catches a
   regression even if the output itself is not read. *)

IMPORT Files, Out, Ropes;

VAR
  passed, failed: LONGINT;
  splitCount: LONGINT;
  splitBuf: ARRAY 8 OF ARRAY 16 OF CHAR;
  iterateBuf: ARRAY 32 OF CHAR;
  iterateLen: LONGINT;
  chunkCalls: LONGINT;
  chunkEmpty: BOOLEAN;
  chunkLens: ARRAY 8 OF LONGINT;
  chunkAcc: Ropes.Rope;

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

PROCEDURE ToStr(r: Ropes.Rope; VAR s: ARRAY OF CHAR);
BEGIN
  Ropes.ToString(r, s)
END ToStr;

PROCEDURE StrEq(r: Ropes.Rope; expect: ARRAY OF CHAR): BOOLEAN;
  VAR buf: ARRAY 4096 OF CHAR;
BEGIN
  ToStr(r, buf);
  RETURN buf = expect
END StrEq;

PROCEDURE CheckConstruction;
  VAR r: Ropes.Rope; buf: ARRAY 16 OF CHAR;
BEGIN
  Check(Ropes.FromString("") = NIL, "FromString of an empty string is NIL");
  Check(Ropes.IsEmpty(NIL), "IsEmpty(NIL)");
  Check(~Ropes.IsEmpty(Ropes.FromString("x")), "~IsEmpty(FromString(x))");

  r := Ropes.FromString("hello");
  Check(StrEq(r, "hello"), "FromString/ToString round trip");
  Check(Ropes.Length(r) = 5, "Length of FromString(hello)");

  Ropes.ToString(NIL, buf);
  Check(buf = "", "ToString(NIL) gives an empty string");

  r := Ropes.FromString("this does not fit in a tiny buffer");
  Ropes.ToString(r, buf);
  Check(buf = "this does not f", "ToString truncates to fit, like ArgParser.String");
END CheckConstruction;

PROCEDURE CheckLengthAndFetch;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("abcde");
  Check(Ropes.Length(r) = 5, "Length");
  Check(Ropes.Fetch(r, 0) = "a", "Fetch first character");
  Check(Ropes.Fetch(r, 4) = "e", "Fetch last character");
  Check(Ropes.Length(NIL) = 0, "Length(NIL) = 0");
END CheckLengthAndFetch;

PROCEDURE CheckCat;
  VAR a, b, r: Ropes.Rope;
BEGIN
  a := Ropes.FromString("foo");
  Check(Ropes.Cat(NIL, a) = a, "Cat(NIL, x) = x");
  Check(Ropes.Cat(a, NIL) = a, "Cat(x, NIL) = x");

  (* Both short leaves: merges into one leaf (depth 0). *)
  a := Ropes.FromString("ab");
  b := Ropes.FromString("cd");
  r := Ropes.Cat(a, b);
  Check(StrEq(r, "abcd"), "Cat of two short leaves: content");
  Check(Ropes.Depth(r) = 0, "Cat of two short leaves merges into one leaf");

  (* Absorbing into a Concat's short-leaf right child: still depth 1, not 2.
     The right leaf ("01234", 5 chars) has room left under ShortLeafLength
     (16), so appending "x" merges into it instead of adding a level. *)
  r := Ropes.Cat(r, Ropes.FromString("0123456789012345"));  (* forces a real Concat: combined > ShortLeafLength *)
  Check(Ropes.Depth(r) = 1, "First concat past the short-leaf limit has depth 1");
  r := Ropes.Cat(r, Ropes.FromString("01234"));
  Check(Ropes.Depth(r) = 2, "Second concat past the short-leaf limit has depth 2");
  r := Ropes.Cat(r, Ropes.FromString("x"));
  Check(StrEq(r, "abcd012345678901234501234x"), "Absorbing a short leaf: content");
  Check(Ropes.Depth(r) = 2, "Absorbing a short leaf keeps depth from growing");

  (* Two large leaves: an ordinary Concat node, depth 1. *)
  a := Ropes.FromString("0123456789012345");
  b := Ropes.FromString("9876543210987654");
  r := Ropes.Cat(a, b);
  Check(StrEq(r, "01234567890123459876543210987654"), "Cat of two large leaves: content");
  Check(Ropes.Depth(r) = 1, "Cat of two large leaves has depth 1");
END CheckCat;

PROCEDURE CheckSubstring;
  VAR r, s: Ropes.Rope;
BEGIN
  r := Ropes.Cat(Ropes.FromString("0123456789012345"), Ropes.FromString("abcdefghij"));

  s := Ropes.Substring(r, 0, Ropes.Length(r));
  Check(StrEq(s, "0123456789012345abcdefghij"), "Substring of the whole rope");

  s := Ropes.Substring(r, 3, 0);
  Check(s = NIL, "Substring of length 0 is NIL");

  s := Ropes.Substring(r, -5, 8);
  Check(StrEq(s, "01234567"), "Substring clamps a negative start");

  s := Ropes.Substring(r, 20, 1000);
  Check(StrEq(s, "efghij"), "Substring clamps an over-length end");

  (* Spans both children of the Concat built above (left is 16 chars). *)
  s := Ropes.Substring(r, 10, 10);
  Check(StrEq(s, "012345abcd"), "Substring spanning two tree nodes");

  s := Ropes.Substring(r, 100, 5);
  Check(s = NIL, "Substring starting past the end is NIL");
END CheckSubstring;

PROCEDURE CheckInsert;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("hello world");

  Check(StrEq(Ropes.Insert(r, 5, Ropes.FromString(",")), "hello, world"), "Insert in the middle");
  Check(StrEq(Ropes.Insert(r, 0, Ropes.FromString(">> ")), ">> hello world"), "Insert at the start");
  Check(StrEq(Ropes.Insert(r, 11, Ropes.FromString("!")), "hello world!"), "Insert at the end");
  Check(StrEq(Ropes.Insert(r, 100, Ropes.FromString("!")), "hello world!"), "Insert clamps a too-large pos to the end");
  Check(StrEq(Ropes.Insert(r, -5, Ropes.FromString(">> ")), ">> hello world"), "Insert clamps a negative pos to the start");

  Check(StrEq(Ropes.Insert(NIL, 0, Ropes.FromString("x")), "x"), "Insert into NIL is just the inserted rope");
  Check(StrEq(Ropes.Insert(r, 5, NIL), "hello world"), "Insert of NIL leaves the rope unchanged");
  Check(Ropes.Insert(NIL, 0, NIL) = NIL, "Insert of NIL into NIL is NIL");

  Check(Ropes.Length(Ropes.Insert(r, 5, Ropes.FromString(","))) = 12, "Insert: resulting length");
END CheckInsert;

PROCEDURE CheckRemove;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("hello, world");

  Check(StrEq(Ropes.Remove(r, 5, 2), "helloworld"), "Remove from the middle");
  Check(StrEq(Ropes.Remove(r, 0, 7), "world"), "Remove from the start");
  Check(StrEq(Ropes.Remove(r, 5, 100), "hello"), "Remove clamps a too-large len to the end");
  Check(StrEq(Ropes.Remove(r, 100, 5), "hello, world"), "Remove at a too-large pos removes nothing");
  Check(StrEq(Ropes.Remove(r, -5, 5), ", world"), "Remove clamps a negative pos to the start");
  Check(StrEq(Ropes.Remove(r, 5, -2), "hello, world"), "Remove clamps a negative len to 0");
  Check(Ropes.Remove(r, 0, Ropes.Length(r)) = NIL, "Remove of the whole rope is NIL");

  Check(Ropes.Remove(NIL, 0, 5) = NIL, "Remove from NIL is NIL");
  Check(StrEq(Ropes.Remove(r, 5, 0), "hello, world"), "Remove of length 0 leaves the rope unchanged");

  Check(Ropes.Length(Ropes.Remove(r, 5, 2)) = 10, "Remove: resulting length");
END CheckRemove;

PROCEDURE CheckOverwrite;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("hello world");

  Check(StrEq(Ropes.Overwrite(r, 6, Ropes.FromString("there")), "hello there"), "Overwrite replaces characters in the middle");
  Check(StrEq(Ropes.Overwrite(r, 0, Ropes.FromString("HELLO")), "HELLO world"), "Overwrite at the start");
  Check(StrEq(Ropes.Overwrite(r, 11, Ropes.FromString("!")), "hello world!"), "Overwrite past the end appends");
  Check(StrEq(Ropes.Overwrite(r, 6, Ropes.FromString("there, universe")), "hello there, universe"),
        "Overwrite extends past the original end");
  Check(StrEq(Ropes.Overwrite(r, 100, Ropes.FromString("!")), "hello world!"), "Overwrite clamps a too-large pos to the end");
  Check(StrEq(Ropes.Overwrite(r, -5, Ropes.FromString(">> ")), ">> lo world"), "Overwrite clamps a negative pos to the start");

  Check(StrEq(Ropes.Overwrite(NIL, 0, Ropes.FromString("x")), "x"), "Overwrite into NIL is just the new rope");
  Check(StrEq(Ropes.Overwrite(r, 5, NIL), "hello world"), "Overwrite of NIL leaves the rope unchanged");
  Check(Ropes.Overwrite(NIL, 0, NIL) = NIL, "Overwrite of NIL into NIL is NIL");

  Check(Ropes.Length(Ropes.Overwrite(r, 6, Ropes.FromString("there"))) = 11, "Overwrite: resulting length");
END CheckOverwrite;

PROCEDURE CheckCompareFindRepeat;
  VAR r: Ropes.Rope;
BEGIN
  Check(Ropes.Compare(Ropes.FromString("abc"), Ropes.FromString("abc")) = 0, "Compare equal ropes");
  Check(Ropes.Compare(Ropes.FromString("abc"), Ropes.FromString("abd")) < 0, "Compare less-than");
  Check(Ropes.Compare(Ropes.FromString("abd"), Ropes.FromString("abc")) > 0, "Compare greater-than");
  Check(Ropes.Compare(Ropes.FromString("ab"), Ropes.FromString("abc")) < 0, "Compare: shorter prefix sorts first");
  Check(Ropes.Equal(Ropes.FromString("xyz"), Ropes.FromString("xyz")), "Equal");
  Check(~Ropes.Equal(Ropes.FromString("xyz"), Ropes.FromString("xy")), "~Equal");

  r := Ropes.Cat(Ropes.FromString("Hello, "), Ropes.FromString("World!"));
  Check(Ropes.Find(r, "World", 0) = 7, "Find a substring present in the rope");
  Check(Ropes.Find(r, "xyz", 0) = -1, "Find a substring not present");
  Check(Ropes.Find(r, "o", 5) = 8, "Find starting from an offset");
  Check(Ropes.Find(r, "", 3) = 3, "Find of the empty pattern");

  r := Ropes.Repeat(Ropes.FromString("ab"), 4);
  Check(StrEq(r, "abababab"), "Repeat content");
  Check(Ropes.Length(r) = 8, "Repeat length");
  Check(Ropes.Repeat(Ropes.FromString("x"), 0) = NIL, "Repeat 0 times is NIL");
  Check(Ropes.Repeat(NIL, 5) = NIL, "Repeat of NIL is NIL");
END CheckCompareFindRepeat;

PROCEDURE CheckStressAndBalance;
  VAR r, balanced, wide: Ropes.Rope; i: LONGINT; ok: BOOLEAN;
BEGIN
  (* Build a rope by appending one character at a time, the way a naive
     caller building up output would.  Without the short-leaf merge and
     depth-triggered auto-rebalance, this would grow one Concat level per
     character (depth ~2000); Cat.MaxDepth bounds it well below that. *)
  r := NIL;
  FOR i := 0 TO 1999 DO
    r := Ropes.AppendChar(r, CHR(ORD("a") + (i MOD 26)))
  END;
  Check(Ropes.Length(r) = 2000, "AppendChar x2000: length");
  Check(Ropes.Fetch(r, 0) = "a", "AppendChar x2000: first character");
  Check(Ropes.Fetch(r, 1999) = CHR(ORD("a") + (1999 MOD 26)), "AppendChar x2000: last character");

  ok := TRUE;
  i := 0;
  WHILE ok & (i < 2000) DO
    IF Ropes.Fetch(r, i) # CHR(ORD("a") + (i MOD 26)) THEN ok := FALSE END;
    INC(i)
  END;
  Check(ok, "AppendChar x2000: every character matches");

  Check(Ropes.Depth(r) < Ropes.MaxDepth, "AppendChar x2000: depth stays bounded well below MaxDepth");

  balanced := Ropes.Balance(r);
  Check(Ropes.Equal(r, balanced), "Balance preserves content");
  Check(Ropes.Depth(balanced) <= Ropes.Depth(r), "Balance does not increase depth");
  Check(Ropes.Depth(balanced) < 20, "Balance brings depth down close to optimal for 2000 characters");

  (* A rope built by balanced binary doubling (Repeat) should meet the
     paper's strict balance definition exactly. *)
  wide := Ropes.Repeat(Ropes.FromString("0123456789012345"), 200);
  Check(Ropes.IsBalanced(wide), "A rope built by balanced doubling is strictly balanced");
END CheckStressAndBalance;

PROCEDURE CheckFromCharAndMake;
  VAR r: Ropes.Rope;
BEGIN
  Check(StrEq(Ropes.FromChar("x"), "x"), "FromChar builds a one-character rope");
  Check(Ropes.Length(Ropes.FromChar("x")) = 1, "FromChar: length");

  r := Ropes.FromSubstring("hello world", 6, 5);
  Check(StrEq(r, "world"), "FromSubstring: content");
  Check(Ropes.FromSubstring("hello", 0, 0) = NIL, "FromSubstring of length 0 is NIL");

  r := Ropes.Make(5, "z");
  Check(StrEq(r, "zzzzz"), "Make: content");
  Check(Ropes.Make(0, "z") = NIL, "Make of length 0 is NIL");
  Check(Ropes.Make(-1, "z") = NIL, "Make of negative length is NIL");
END CheckFromCharAndMake;

PROCEDURE CheckHeadTail;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("hello");

  Check(StrEq(Ropes.Head(r, 3, " "), "hel"), "Head takes the first COUNT characters");
  Check(StrEq(Ropes.Head(r, 5, " "), "hello"), "Head of exactly Length(r) characters is r itself");
  Check(StrEq(Ropes.Head(r, 8, "."), "hello..."), "Head pads on the right when COUNT exceeds Length(r)");
  Check(Ropes.Head(r, 0, " ") = NIL, "Head of 0 characters is NIL");
  Check(Ropes.Head(r, -1, " ") = NIL, "Head of a negative COUNT is NIL");
  Check(StrEq(Ropes.Head(NIL, 3, "x"), "xxx"), "Head of NIL is COUNT copies of pad");

  Check(StrEq(Ropes.Tail(r, 3, " "), "llo"), "Tail takes the last COUNT characters");
  Check(StrEq(Ropes.Tail(r, 5, " "), "hello"), "Tail of exactly Length(r) characters is r itself");
  Check(StrEq(Ropes.Tail(r, 8, "."), "...hello"), "Tail pads on the left when COUNT exceeds Length(r)");
  Check(Ropes.Tail(r, 0, " ") = NIL, "Tail of 0 characters is NIL");
  Check(Ropes.Tail(r, -1, " ") = NIL, "Tail of a negative COUNT is NIL");
  Check(StrEq(Ropes.Tail(NIL, 3, "x"), "xxx"), "Tail of NIL is COUNT copies of pad");
END CheckHeadTail;

PROCEDURE CheckOverflowGuard;
  VAR r: Ropes.Rope;
BEGIN
  (* Exactly at the boundary: (MAX(LONGINT) - 1) + 1 = MAX(LONGINT), which
     must succeed -- only a combined length that would exceed
     MAX(LONGINT) should HALT.  This is cheap even at this size: Repeat's
     binary doubling shares subtrees instead of allocating MAX(LONGINT)
     real characters.  The over-the-boundary case can't be a Check here
     -- it HALTs the whole process by design, so it's covered instead by
     tests/rope-bigcat-overflow.test, which expects exactly that. *)
  r := Ropes.Cat(Ropes.Repeat(Ropes.FromChar("x"), MAX(LONGINT) - 1), Ropes.FromChar("y"));
  Check(Ropes.Length(r) = MAX(LONGINT), "Cat right at the LONGINT boundary succeeds");
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
  VAR r, mapped: Ropes.Rope;
BEGIN
  r := Ropes.FromString("abc");
  Check(StrEq(Ropes.Map(r, ShiftMapper), "bcd"), "Map shifts every character");
  Check(Ropes.Map(NIL, ShiftMapper) = NIL, "Map of NIL is NIL");

  (* Two tree nodes (left leaf is 16 chars), so Mapi's threaded index has
     to survive the recursion into the right child. *)
  r := Ropes.Cat(Ropes.FromString("0123456789012345"), Ropes.FromString("abcdefghij"));
  mapped := Ropes.Map(r, ShiftMapper);
  Check(Ropes.Depth(mapped) = Ropes.Depth(r), "Map preserves tree shape (same Depth)");

  mapped := Ropes.Mapi(r, IndexDigitMapper);
  Check(StrEq(mapped, "01234567890123456789012345"), "Mapi: index threads correctly across a Concat node");
END CheckMap;

PROCEDURE CheckAsciiCase;
BEGIN
  Check(StrEq(Ropes.UppercaseAscii(Ropes.FromString("Hello, World! 123")), "HELLO, WORLD! 123"), "UppercaseAscii");
  Check(StrEq(Ropes.LowercaseAscii(Ropes.FromString("Hello, World! 123")), "hello, world! 123"), "LowercaseAscii");
  Check(StrEq(Ropes.CapitalizeAscii(Ropes.FromString("hello")), "Hello"), "CapitalizeAscii");
  Check(StrEq(Ropes.UncapitalizeAscii(Ropes.FromString("Hello")), "hello"), "UncapitalizeAscii");
  Check(Ropes.CapitalizeAscii(NIL) = NIL, "CapitalizeAscii of NIL is NIL");
  Check(Ropes.UncapitalizeAscii(NIL) = NIL, "UncapitalizeAscii of NIL is NIL");
END CheckAsciiCase;

PROCEDURE CheckTrim;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("  hello world  ");
  Check(StrEq(Ropes.TrimLeft(r), "hello world  "), "TrimLeft");
  Check(StrEq(Ropes.TrimRight(r), "  hello world"), "TrimRight");
  Check(StrEq(Ropes.Trim(r), "hello world"), "Trim");
  Check(Ropes.Trim(Ropes.FromString("   ")) = NIL, "Trim of all-whitespace is NIL");
  Check(Ropes.Trim(NIL) = NIL, "Trim of NIL is NIL");
  Check(StrEq(Ropes.Trim(Ropes.FromString("no-trim-needed")), "no-trim-needed"),
        "Trim leaves a rope with no padding unchanged");
END CheckTrim;

PROCEDURE CheckEscape;
  VAR r: Ropes.Rope; buf: ARRAY 3 OF CHAR;
BEGIN
  Check(StrEq(Ropes.Escape(Ropes.FromString('say "hi"')), 'say \"hi\"'), "Escape: double quote");

  buf[0] := "a"; buf[1] := 9X; buf[2] := 0X;
  r := Ropes.FromString(buf);
  Check(StrEq(Ropes.Escape(r), "a\t"), "Escape: tab");

  Check(StrEq(Ropes.Escape(Ropes.FromString("\")), "\\"), "Escape: backslash");
  Check(Ropes.Escape(NIL) = NIL, "Escape of NIL is NIL");
END CheckEscape;

PROCEDURE CheckIndexCharAndRFind;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("abcabc");
  Check(Ropes.IndexChar(r, "b", 0) = 1, "IndexChar: first occurrence");
  Check(Ropes.IndexChar(r, "b", 2) = 4, "IndexChar: from an offset");
  Check(Ropes.IndexChar(r, "z", 0) = -1, "IndexChar: not present");
  Check(Ropes.RIndexChar(r, "b", 5) = 4, "RIndexChar: last occurrence");
  Check(Ropes.RIndexChar(r, "b", 3) = 1, "RIndexChar: before an offset");
  Check(Ropes.RIndexChar(r, "z", 5) = -1, "RIndexChar: not present");
  Check(Ropes.Contains(r, "c", 0), "Contains: present");
  Check(~Ropes.Contains(r, "z", 0), "Contains: not present");

  (* "World" occurs at 7 and again at 14. *)
  r := Ropes.Cat(Ropes.FromString("Hello, "), Ropes.FromString("World! World!"));
  Check(Ropes.RFind(r, "World", Ropes.Length(r)) = 14, "RFind: last occurrence searching the whole rope");
  Check(Ropes.RFind(r, "World", 13) = 7, "RFind: a bound excludes a later occurrence");
  Check(Ropes.RFind(r, "xyz", Ropes.Length(r)) = -1, "RFind: not present");
  Check(Ropes.RFind(r, "", Ropes.Length(r)) = Ropes.Length(r), "RFind: empty pattern matches at the bound");
END CheckIndexCharAndRFind;

PROCEDURE CheckContainsPattern;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("hello world");

  Check(Ropes.ContainsPattern(r, "world", 0), "ContainsPattern: present");
  Check(~Ropes.ContainsPattern(r, "xyz", 0), "ContainsPattern: not present");
  Check(Ropes.ContainsPattern(r, "hello", 0), "ContainsPattern: present at the very start");
  Check(Ropes.ContainsPattern(r, "o", 5), "ContainsPattern: from an offset, still present");
  Check(~Ropes.ContainsPattern(r, "hello", 5), "ContainsPattern: from an offset excludes an earlier occurrence");
  Check(Ropes.ContainsPattern(r, "", 0), "ContainsPattern: the empty pattern always matches");
  Check(~Ropes.ContainsPattern(NIL, "x", 0), "ContainsPattern: not present in NIL (non-empty pattern)");
  Check(Ropes.ContainsPattern(NIL, "", 0), "ContainsPattern: the empty pattern matches even in NIL");
END CheckContainsPattern;

PROCEDURE CheckBlit;
  VAR r: Ropes.Rope; buf: ARRAY 11 OF CHAR;
BEGIN
  r := Ropes.FromString("hello world");
  buf := "XXXXXXXXXX";
  Ropes.Blit(r, 6, buf, 2, 5);
  Check((buf[0] = "X") & (buf[1] = "X") & (buf[2] = "w") & (buf[6] = "d") & (buf[7] = "X"),
        "Blit copies into the middle of dst without touching the rest");
END CheckBlit;

PROCEDURE CollectChar(ch: CHAR): BOOLEAN;
BEGIN
  IF iterateLen < LEN(iterateBuf) - 1 THEN
    iterateBuf[iterateLen] := ch;
    INC(iterateLen);
    iterateBuf[iterateLen] := 0X
  END;
  RETURN TRUE
END CollectChar;

PROCEDURE StopAfterTwoChars(ch: CHAR): BOOLEAN;
BEGIN
  IF iterateLen < LEN(iterateBuf) - 1 THEN
    iterateBuf[iterateLen] := ch;
    INC(iterateLen);
    iterateBuf[iterateLen] := 0X
  END;
  RETURN iterateLen < 2
END StopAfterTwoChars;

PROCEDURE CheckIterate;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("abcde");

  iterateLen := 0; iterateBuf[0] := 0X;
  Ropes.Iterate(r, CollectChar);
  Check(iterateBuf = "abcde", "Iterate: visits every character in order");

  iterateLen := 0; iterateBuf[0] := 0X;
  Ropes.Iterate(r, StopAfterTwoChars);
  Check(iterateBuf = "ab", "Iterate: stops early when visit returns FALSE");

  iterateLen := 0; iterateBuf[0] := 0X;
  Ropes.Iterate(NIL, CollectChar);
  Check(iterateBuf = "", "Iterate of NIL visits nothing");
END CheckIterate;

PROCEDURE CollectPiece(piece: Ropes.Rope): BOOLEAN;
BEGIN
  IF splitCount < LEN(splitBuf) THEN
    Ropes.ToString(piece, splitBuf[splitCount]);
    INC(splitCount)
  END;
  RETURN TRUE
END CollectPiece;

PROCEDURE StopAfterTwo(piece: Ropes.Rope): BOOLEAN;
BEGIN
  IF splitCount < LEN(splitBuf) THEN
    Ropes.ToString(piece, splitBuf[splitCount]);
    INC(splitCount)
  END;
  RETURN splitCount < 2
END StopAfterTwo;

PROCEDURE CheckSplit;
  VAR r: Ropes.Rope; arr: Ropes.Pieces; node: Ropes.Piece;
BEGIN
  r := Ropes.FromString("a,b,,c");

  splitCount := 0;
  Ropes.Split(r, ",", CollectPiece);
  Check(splitCount = 4, "Split: visits every piece, including an empty one");
  Check((splitBuf[0] = "a") & (splitBuf[1] = "b") & (splitBuf[2] = "") & (splitBuf[3] = "c"),
        "Split: piece contents in order");

  splitCount := 0;
  Ropes.Split(r, ",", StopAfterTwo);
  Check(splitCount = 2, "Split: stops early when visit returns FALSE");

  splitCount := 0;
  Ropes.Split(NIL, ",", CollectPiece);
  Check((splitCount = 1) & (splitBuf[0] = ""), "Split of NIL gives one empty piece");

  splitCount := 0;
  Ropes.Split(Ropes.FromString("abc"), ",", CollectPiece);
  Check((splitCount = 1) & (splitBuf[0] = "abc"), "Split with an absent separator gives one piece: the whole rope");

  splitCount := 0;
  Ropes.Split(Ropes.FromString("abc"), "", CollectPiece);
  Check((splitCount = 1) & (splitBuf[0] = "abc"), "Split with an empty separator never splits");

  arr := Ropes.SplitArray(r, ",");
  Check(LEN(arr^) = 4, "SplitArray: piece count");
  Check(StrEq(arr[0], "a") & StrEq(arr[1], "b") & StrEq(arr[2], "") & StrEq(arr[3], "c"),
        "SplitArray: piece contents in order");

  node := Ropes.SplitList(r, ",");
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
  VAR r: Ropes.Rope; it: Ropes.Iterator; i: LONGINT; ok: BOOLEAN;
BEGIN
  (* Two tree nodes: the first leaf is 16 characters, so position 15 is
     its last and position 16 crosses into the second leaf. *)
  r := Ropes.Cat(Ropes.FromString("0123456789012345"), Ropes.FromString("abcdefghij"));

  it := Ropes.NewIterator(r, 0);
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

  it := Ropes.NewIterator(r, 0);
  ok := TRUE;
  i := 0;
  WHILE ok & (i < Ropes.Length(r)) DO
    IF it.Get() # Ropes.Fetch(r, i) THEN ok := FALSE END;
    it.Incr;
    INC(i)
  END;
  Check(ok, "Iterator: walking forward matches Fetch at every position");
END CheckIterator;

(* --- IterateChunks, linear Compare, WriteRider/ReadLineRider --- *)

(* Source split into leaves of size characters each (size > 16, the
   short-leaf merge threshold, so Cat keeps them as separate leaves):
   the first len characters of s only. *)
PROCEDURE Chunked(s: ARRAY OF CHAR; len, size: LONGINT): Ropes.Rope;
  VAR r: Ropes.Rope; i, n: LONGINT;
BEGIN
  r := NIL;
  i := 0;
  WHILE i < len DO
    n := size;
    IF i + n > len THEN n := len - i END;
    r := Ropes.Cat(r, Ropes.FromSubstring(s, i, n));
    INC(i, n)
  END;
  RETURN r
END Chunked;

(* 200 leaves of 50 characters each. *)
PROCEDURE ManyLeaves(): Ropes.Rope;
  VAR r: Ropes.Rope; i: LONGINT;
BEGIN
  r := NIL;
  FOR i := 1 TO 200 DO r := Ropes.Cat(r, Ropes.Make(50, CHR(ORD("a") + i MOD 26))) END;
  RETURN r
END ManyLeaves;

PROCEDURE CountChunk(VAR chunk: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF chunkCalls < LEN(chunkLens) THEN chunkLens[chunkCalls] := LEN(chunk) END;
  INC(chunkCalls);
  IF LEN(chunk) = 0 THEN chunkEmpty := TRUE END;
  RETURN TRUE
END CountChunk;

PROCEDURE CollectChunk(VAR chunk: ARRAY OF CHAR): BOOLEAN;
BEGIN
  chunkAcc := Ropes.Cat(chunkAcc, Ropes.FromSubstring(chunk, 0, LEN(chunk)));
  INC(chunkCalls);
  RETURN TRUE
END CollectChunk;

PROCEDURE StopAfterTwoChunks(VAR chunk: ARRAY OF CHAR): BOOLEAN;
BEGIN
  INC(chunkCalls);
  RETURN chunkCalls < 2
END StopAfterTwoChunks;

PROCEDURE CheckIterateChunks;
  VAR r: Ropes.Rope; buf: ARRAY 3 OF CHAR;
BEGIN
  chunkCalls := 0;
  Ropes.IterateChunks(NIL, CountChunk);
  Check(chunkCalls = 0, "IterateChunks of NIL visits nothing");

  r := ManyLeaves();
  chunkCalls := 0; chunkEmpty := FALSE;
  Ropes.IterateChunks(r, CountChunk);
  Check(chunkCalls > 1, "IterateChunks: a many-leaf rope arrives as more than one chunk");
  Check(~chunkEmpty, "IterateChunks: never passes an empty chunk");

  chunkCalls := 0; chunkAcc := NIL;
  Ropes.IterateChunks(r, CollectChunk);
  Check(Ropes.Equal(chunkAcc, r) & (Ropes.Length(chunkAcc) = Ropes.Length(r)),
        "IterateChunks: chunks concatenate to the whole rope");

  chunkCalls := 0;
  Ropes.IterateChunks(r, StopAfterTwoChunks);
  Check(chunkCalls = 2, "IterateChunks: stops early when visit returns FALSE");

  (* A leaf holding a 0X: the chunk is all LEN(chunk) characters, not cut
     short at the 0X the way a 0X-terminated string would be. *)
  buf[0] := "a"; buf[1] := 0X; buf[2] := "b";
  chunkCalls := 0;
  Ropes.IterateChunks(Ropes.FromSubstring(buf, 0, 3), CountChunk);
  Check((chunkCalls = 1) & (chunkLens[0] = 3), "IterateChunks: a chunk containing 0X is passed whole");
END CheckIterateChunks;

(* Compare's oracle: Ropes.Compare must agree in sign with Oberon's own
   string comparison, whatever the two ropes' leaf boundaries are. *)
PROCEDURE Agrees(a, b: Ropes.Rope): BOOLEAN;
  VAR sa, sb: ARRAY 256 OF CHAR; c: INTEGER;
BEGIN
  Ropes.ToString(a, sa);
  Ropes.ToString(b, sb);
  c := Ropes.Compare(a, b);
  RETURN ((c < 0) = (sa < sb)) & ((c = 0) = (sa = sb)) & ((c > 0) = (sa > sb))
END Agrees;

PROCEDURE CheckCompareLeafBoundaries;
  VAR base, changed: ARRAY 201 OF CHAR; a, b, big1, big2: Ropes.Rope; i, p, d, len: LONGINT; ok: BOOLEAN;
BEGIN
  FOR i := 0 TO 199 DO base[i] := CHR(ORD("a") + (i + 1) MOD 26) END;
  base[200] := 0X;
  a := Chunked(base, 200, 17);
  Check(Ropes.Equal(a, Chunked(base, 200, 23)) & Ropes.Equal(Chunked(base, 200, 23), a),
        "Compare: same text, different leaf boundaries, is equal");

  (* One character changed, down, not at all, or up, at every position:
     covers a difference at the first/last character and at, just before,
     and just after every leaf boundary of either rope. *)
  ok := TRUE;
  FOR p := 0 TO 199 DO
    FOR d := -1 TO 1 DO
      changed := base;
      changed[p] := CHR(ORD(changed[p]) + d);
      b := Chunked(changed, 200, 23);
      ok := ok & Agrees(a, b) & Agrees(b, a)
    END
  END;
  Check(ok, "Compare: a one-character difference at every position agrees with string comparison");

  ok := TRUE;
  FOR len := 0 TO 200 DO
    b := Chunked(base, len, 23);
    ok := ok & Agrees(a, b) & Agrees(b, a)
  END;
  Check(ok, "Compare: every prefix length agrees with string comparison");

  (* Twenty million characters each, built with different leaf sizes so
     no subtree is shared: Compare used to Fetch every character from the
     root, O(n log n); now linear. *)
  big1 := Ropes.Repeat(Ropes.FromString("0123456789"), 2000000);
  big2 := Ropes.Repeat(Ropes.FromString("01234567890123456789"), 1000000);
  Check(Ropes.Equal(big1, big2), "Compare: two large equal ropes with no shared structure");
  Check(Ropes.Compare(big1, Ropes.AppendChar(big2, "x")) < 0, "Compare: a large rope sorts before itself plus one more character");
  Check(Ropes.Compare(big1, big1) = 0, "Compare: a rope equals itself (shared tree)")
END CheckCompareLeafBoundaries;

PROCEDURE WriteLine(VAR w: Files.Rider; r: Ropes.Rope);
BEGIN
  Ropes.WriteRider(w, r);
  Files.Write(w, 0AX)
END WriteLine;

PROCEDURE CheckWriteReadRider;
  CONST n = 9;
  VAR f: Files.File; w, rd: Files.Rider; line, big: Ropes.Rope; lens: ARRAY n OF LONGINT;
      i: LONGINT; ok: BOOLEAN; buf: ARRAY 3 OF CHAR;
BEGIN
  lens[0] := 0; lens[1] := 1; lens[2] := 4095; lens[3] := 4096; lens[4] := 4097;
  lens[5] := 8191; lens[6] := 8192; lens[7] := 8193; lens[8] := 100000;

  (* Files.New without Files.Register: a temporary file, never given a
     name on disk. *)
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  Ropes.WriteRider(w, NIL);
  Check(Files.Length(f) = 0, "WriteRider of NIL writes nothing");

  FOR i := 0 TO n - 1 DO WriteLine(w, Ropes.Make(lens[i], "q")) END;
  Files.Set(rd, f, 0);
  ok := TRUE;
  FOR i := 0 TO n - 1 DO
    ok := ok & Ropes.ReadLineRider(rd, line) & Ropes.Equal(line, Ropes.Make(lens[i], "q"))
  END;
  Check(ok, "WriteRider/ReadLineRider: lines of length 0, 1, 4095..4097, 8191..8193, 100000 each read back exactly");
  Check(~Ropes.ReadLineRider(rd, line) & (line = NIL) & rd.eof, "ReadLineRider: FALSE, with NIL, at end of file");
  Files.Close(f);

  (* The last line exactly fills ReadLineRider's chunk, with no line feed
     after it in the file at all. *)
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  Ropes.WriteRider(w, Ropes.Make(4096, "q"));
  Files.Set(rd, f, 0);
  Check(Ropes.ReadLineRider(rd, line) & Ropes.Equal(line, Ropes.Make(4096, "q")),
        "ReadLineRider: an unterminated last line of exactly 4096 characters");
  Check(~Ropes.ReadLineRider(rd, line), "ReadLineRider: FALSE after an unterminated last line");
  Files.Close(f);

  (* A 0X inside a line is just another character, both ways. *)
  buf[0] := "a"; buf[1] := 0X; buf[2] := "b";
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  WriteLine(w, Ropes.FromSubstring(buf, 0, 3));
  Files.Set(rd, f, 0);
  Check(Ropes.ReadLineRider(rd, line) & (Ropes.Length(line) = 3) & (Ropes.Fetch(line, 1) = 0X) & (Ropes.Fetch(line, 2) = "b"),
        "WriteRider/ReadLineRider: a 0X inside a line round-trips");
  Files.Close(f);

  (* Far longer than ToString into ArgParser.MaxStringLength-sized buffers
     could ever carry. *)
  big := Ropes.Repeat(Ropes.FromString("0123456789"), 100000);
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  WriteLine(w, big);
  Files.Set(rd, f, 0);
  Check(Ropes.ReadLineRider(rd, line) & (Ropes.Length(line) = 1000000) & Ropes.Equal(line, big),
        "WriteRider/ReadLineRider: a million-character rope round-trips");
  Files.Close(f)
END CheckWriteReadRider;

(* --- ReadAll, ReadFile, WriteFile --- *)

(* A rope of every byte value, 0X to 0FFX, n times over. *)
PROCEDURE AllBytes(n: LONGINT): Ropes.Rope;
  VAR buf: ARRAY 256 OF CHAR; i: LONGINT;
BEGIN
  FOR i := 0 TO 255 DO buf[i] := CHR(i) END;
  RETURN Ropes.Repeat(Ropes.FromSubstring(buf, 0, 256), n)
END AllBytes;

(* "one" CR LF "two" FF "three" 0X "four" LF "no final newline": what
   reading line by line would lose -- the same bytes as
   tests/data/exact.bin. *)
PROCEDURE Tricky(): Ropes.Rope;
  VAR buf: ARRAY 64 OF CHAR; r: Ropes.Rope;
BEGIN
  r := Ropes.FromString("one");
  r := Ropes.AppendChar(Ropes.AppendChar(r, 0DX), 0AX);
  r := Ropes.AppendChar(Ropes.Cat(r, Ropes.FromString("two")), 0CX);
  r := Ropes.AppendChar(Ropes.Cat(r, Ropes.FromString("three")), 0X);
  r := Ropes.AppendChar(Ropes.Cat(r, Ropes.FromString("four")), 0AX);
  buf := "no final newline";
  RETURN Ropes.Cat(r, Ropes.FromString(buf))
END Tricky;

PROCEDURE CheckReadAll;
  CONST n = 7;
  VAR f: Files.File; w, rd: Files.Rider; r: Ropes.Rope; sizes: ARRAY n OF LONGINT; i: LONGINT; ok: BOOLEAN;
BEGIN
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  Ropes.WriteRider(w, Tricky());
  Files.Set(rd, f, 0);
  r := Ropes.ReadAll(rd);
  Check(Ropes.Equal(r, Tricky()) & (Ropes.Length(r) = Files.Length(f)),
        "ReadAll: CR, form feed, 0X, and no final line feed survive, byte for byte");
  Check(Ropes.ReadAll(rd) = NIL, "ReadAll at end of file is NIL");
  Files.Set(rd, f, 9);  (* "one" CR LF "two" FF is 9 bytes. *)
  Check(StrEq(Ropes.Substring(Ropes.ReadAll(rd), 0, 5), "three"), "ReadAll: reads from the rider's position to the end");
  Files.Close(f);

  sizes[0] := 1; sizes[1] := 4095; sizes[2] := 4096; sizes[3] := 4097;
  sizes[4] := 8192; sizes[5] := 8193; sizes[6] := 100000;
  ok := TRUE;
  FOR i := 0 TO n - 1 DO
    f := Files.New("RopeTest.tmp");
    Files.Set(w, f, 0);
    Ropes.WriteRider(w, Ropes.Make(sizes[i], "z"));
    Files.Set(rd, f, 0);
    ok := ok & Ropes.Equal(Ropes.ReadAll(rd), Ropes.Make(sizes[i], "z"));
    Files.Close(f)
  END;
  Check(ok, "ReadAll: files of 1, 4095..4097, 8192, 8193, 100000 bytes each read back exactly")
END CheckReadAll;

PROCEDURE CheckReadWriteFile;
  CONST name = "RopeTest-file.tmp";
  VAR r, big: Ropes.Rope; res: INTEGER;
BEGIN
  Ropes.WriteFile(name, AllBytes(3));
  Check(Ropes.ReadFile(name, r) & Ropes.Equal(r, AllBytes(3)), "WriteFile/ReadFile: all 256 byte values survive a round trip");

  Ropes.WriteFile(name, Ropes.FromString("a longer first version"));
  Ropes.WriteFile(name, Ropes.FromString("short"));
  Check(Ropes.ReadFile(name, r) & StrEq(r, "short"), "WriteFile replaces an existing file, not overwrites its start");

  Ropes.WriteFile(name, NIL);
  Check(Ropes.ReadFile(name, r) & (r = NIL), "WriteFile of NIL makes an empty file; ReadFile of it is TRUE with NIL");

  big := Ropes.Repeat(Ropes.FromString("0123456789"), 100000);
  Ropes.WriteFile(name, big);
  Check(Ropes.ReadFile(name, r) & Ropes.Equal(r, big), "WriteFile/ReadFile: a million-character rope round-trips");

  Files.Delete(name, res);
  r := Ropes.FromString("not reset");
  Check(~Ropes.ReadFile(name, r) & (r = NIL), "ReadFile of a missing file is FALSE, with NIL")
END CheckReadWriteFile;

(* --- Blit and Escape across leaves --- *)

PROCEDURE CheckBlitAcrossLeaves;
  VAR base: ARRAY 201 OF CHAR; dst: ARRAY 204 OF CHAR; r: Ropes.Rope; start, len, k: LONGINT; ok: BOOLEAN;
BEGIN
  FOR k := 0 TO 199 DO base[k] := CHR(ORD("a") + (k + 1) MOD 26) END;
  base[200] := 0X;
  r := Chunked(base, 200, 17);
  (* Every start and every length: a range starting and ending inside, at,
     and just past every leaf boundary.  dst[0] and the character just
     after the copied range are sentinels, so copying one too many or too
     few characters is caught as well as copying the wrong ones. *)
  ok := TRUE;
  FOR start := 0 TO 200 DO
    FOR len := 0 TO 200 - start DO
      FOR k := 0 TO LEN(dst) - 1 DO dst[k] := "#" END;
      Ropes.Blit(r, start, dst, 1, len);
      ok := ok & (dst[0] = "#") & (dst[1 + len] = "#");
      FOR k := 0 TO len - 1 DO ok := ok & (dst[1 + k] = base[start + k]) END
    END
  END;
  Check(ok, "Blit: every start and length across leaf boundaries copies exactly that range")
END CheckBlitAcrossLeaves;

PROCEDURE CheckEscapeAcrossLeaves;
  CONST pieceLen = 10;
  VAR piece: ARRAY pieceLen OF CHAR; flat: ARRAY 50 * pieceLen + 1 OF CHAR; p, e: Ropes.Rope; k: LONGINT;
BEGIN
  (* One of each kind of escape, plus two plain characters. *)
  piece[0] := "a"; piece[1] := "\"; piece[2] := '"'; piece[3] := 0AX; piece[4] := 09X;
  piece[5] := 0DX; piece[6] := 0X; piece[7] := 0FFX; piece[8] := 01X; piece[9] := "z";
  p := Ropes.FromSubstring(piece, 0, pieceLen);
  Check(StrEq(Ropes.Escape(p), 'a\\\"\n\t\r\000\255\001z'), "Escape: every kind of escape, including \NNN for 0X and 0FFX");

  (* Escaping is per character, so escaping n copies of piece must give n
     copies of its escape -- whatever the leaf boundaries.  Chunked by 17
     puts them in the middle of pieces, and escapes, too. *)
  FOR k := 0 TO 50 * pieceLen - 1 DO flat[k] := piece[k MOD pieceLen] END;
  flat[50 * pieceLen] := 0X;
  Check(Ropes.Equal(Ropes.Escape(Chunked(flat, 50 * pieceLen, 17)), Ropes.Repeat(Ropes.Escape(p), 50)),
        "Escape: leaf boundaries in the middle of the input don't change the result");

  (* Far more output than Escape's 4096-character buffer, so it is
     flushed many times, with escapes landing across those flushes too. *)
  e := Ropes.Escape(Ropes.Repeat(p, 100000));
  Check((Ropes.Length(e) = 100000 * Ropes.Length(Ropes.Escape(p))) & Ropes.Equal(e, Ropes.Repeat(Ropes.Escape(p), 100000)),
        "Escape: a million-character input escapes the same as its pieces")
END CheckEscapeAcrossLeaves;

(* --- Ported back from the Ada Ropes package: faster search, sets,
   tokens, Count, Replace/ReplaceChar, Translate, mapped search,
   CompareString, case-insensitive comparison, Hash --- *)

(* Searches' oracles: the same search, done naively over a flat array
   s[0 .. n-1] with Ropes.Mod's own clamping conventions, so that a rope
   search can be checked against it whatever the rope's leaves.  f, if
   not NIL, maps s's characters before comparing. *)
PROCEDURE Mapped(ch: CHAR; f: Ropes.Mapper): CHAR;
BEGIN
  IF f # NIL THEN RETURN f(ch) END;
  RETURN ch
END Mapped;

PROCEDURE MatchesAt(VAR s: ARRAY OF CHAR; i: LONGINT; pat: ARRAY OF CHAR; patLen: LONGINT; f: Ropes.Mapper): BOOLEAN;
  VAR k: LONGINT;
BEGIN
  FOR k := 0 TO patLen - 1 DO
    IF Mapped(s[i + k], f) # pat[k] THEN RETURN FALSE END
  END;
  RETURN TRUE
END MatchesAt;

PROCEDURE NaiveFind(VAR s: ARRAY OF CHAR; n: LONGINT; pat: ARRAY OF CHAR; from: LONGINT; f: Ropes.Mapper): LONGINT;
  VAR patLen, i: LONGINT;
BEGIN
  patLen := 0;
  WHILE (patLen < LEN(pat)) & (pat[patLen] # 0X) DO INC(patLen) END;
  IF from < 0 THEN from := 0 END;
  IF patLen = 0 THEN
    IF from > n THEN RETURN -1 END;
    RETURN from
  END;
  FOR i := from TO n - patLen DO
    IF MatchesAt(s, i, pat, patLen, f) THEN RETURN i END
  END;
  RETURN -1
END NaiveFind;

PROCEDURE NaiveRFind(VAR s: ARRAY OF CHAR; n: LONGINT; pat: ARRAY OF CHAR; before: LONGINT; f: Ropes.Mapper): LONGINT;
  VAR patLen, i: LONGINT;
BEGIN
  patLen := 0;
  WHILE (patLen < LEN(pat)) & (pat[patLen] # 0X) DO INC(patLen) END;
  IF patLen = 0 THEN
    IF before < 0 THEN RETURN -1 END;
    IF before > n THEN RETURN n END;
    RETURN before
  END;
  IF before > n - patLen THEN before := n - patLen END;
  FOR i := before TO 0 BY -1 DO
    IF MatchesAt(s, i, pat, patLen, f) THEN RETURN i END
  END;
  RETURN -1
END NaiveRFind;

PROCEDURE NaiveCount(VAR s: ARRAY OF CHAR; n: LONGINT; pat: ARRAY OF CHAR; f: Ropes.Mapper): LONGINT;
  VAR patLen, from, pos, count: LONGINT;
BEGIN
  patLen := 0;
  WHILE (patLen < LEN(pat)) & (pat[patLen] # 0X) DO INC(patLen) END;
  count := 0;
  IF patLen = 0 THEN RETURN 0 END;
  from := 0;
  LOOP
    pos := NaiveFind(s, n, pat, from, f);
    IF pos < 0 THEN EXIT END;
    INC(count);
    from := pos + patLen
  END;
  RETURN count
END NaiveCount;

PROCEDURE NaiveIndexSet(VAR s: ARRAY OF CHAR; n: LONGINT; VAR set: Ropes.CharSet; inside: BOOLEAN; from: LONGINT; forward: BOOLEAN): LONGINT;
  VAR i: LONGINT;
BEGIN
  IF forward THEN
    IF from < 0 THEN from := 0 END;
    FOR i := from TO n - 1 DO
      IF set.has[ORD(s[i])] = inside THEN RETURN i END
    END
  ELSE
    IF from > n - 1 THEN from := n - 1 END;
    FOR i := from TO 0 BY -1 DO
      IF set.has[ORD(s[i])] = inside THEN RETURN i END
    END
  END;
  RETURN -1
END NaiveIndexSet;

(* Swaps a, b, c with x, y, z: a mapping that changes a pattern's own
   characters, so a search that wrongly mapped the pattern as well as
   the rope would find different matches. *)
PROCEDURE SwapMapper(ch: CHAR): CHAR;
BEGIN
  CASE ch OF
    "a": RETURN "x" | "b": RETURN "y" | "c": RETURN "z"
  | "x": RETURN "a" | "y": RETURN "b" | "z": RETURN "c"
  ELSE RETURN ch
  END
END SwapMapper;

(* The first len characters of s in leaves of size characters, built by
   prepending, so the tree is right-deep: its walks keep Concat nodes on
   their stacks, where Chunked's left-deep trees give forward walks only
   leaves. *)
PROCEDURE RightDeep(s: ARRAY OF CHAR; len, size: LONGINT): Ropes.Rope;
  VAR r: Ropes.Rope; i: LONGINT;
BEGIN
  r := NIL;
  i := len - len MOD size;
  IF i = len THEN DEC(i, size) END;
  WHILE i >= 0 DO
    r := Ropes.Cat(Ropes.FromSubstring(s, i, len - i - Ropes.Length(r)), r);
    DEC(i, size)
  END;
  RETURN r
END RightDeep;

(* Every search of text[0 .. n-1], as four tree shapes, against the
   naive ones, for every pattern in pats and every from: ok for the
   unmapped searches, okMapped for the mapped ones, okSet for the
   character and set scans. *)
PROCEDURE CompareSearches(VAR text: ARRAY OF CHAR; n: LONGINT; VAR pats: ARRAY OF ARRAY OF CHAR;
                          VAR ok, okMapped, okSet: BOOLEAN);
  VAR i, from: LONGINT; r: Ropes.Rope; set: Ropes.CharSet; mappers: ARRAY 3 OF Ropes.Mapper; m, shape: INTEGER;
BEGIN
  mappers[0] := NIL; mappers[1] := Ropes.LowerChar; mappers[2] := SwapMapper;
  Ropes.MakeCharSet("aeiou ", set);
  FOR shape := 0 TO 3 DO
    IF shape = 0 THEN r := Chunked(text, n, 17)
    ELSIF shape = 1 THEN r := Chunked(text, n, 23)
    ELSIF shape = 2 THEN r := RightDeep(text, n, 17)
    ELSE r := Ropes.Balance(Chunked(text, n, 17))
    END;
    FOR from := -2 TO n + 2 DO
      FOR i := 0 TO LEN(pats) - 1 DO
        ok := ok & (Ropes.Find(r, pats[i], from) = NaiveFind(text, n, pats[i], from, NIL))
                 & (Ropes.RFind(r, pats[i], from) = NaiveRFind(text, n, pats[i], from, NIL));
        FOR m := 1 TO 2 DO
          okMapped := okMapped
            & (Ropes.FindMapped(r, pats[i], from, mappers[m]) = NaiveFind(text, n, pats[i], from, mappers[m]))
            & (Ropes.RFindMapped(r, pats[i], from, mappers[m]) = NaiveRFind(text, n, pats[i], from, mappers[m]))
        END
      END;
      okSet := okSet
        & (Ropes.IndexSet(r, set, TRUE, from) = NaiveIndexSet(text, n, set, TRUE, from, TRUE))
        & (Ropes.IndexSet(r, set, FALSE, from) = NaiveIndexSet(text, n, set, FALSE, from, TRUE))
        & (Ropes.RIndexSet(r, set, TRUE, from) = NaiveIndexSet(text, n, set, TRUE, from, FALSE))
        & (Ropes.RIndexSet(r, set, FALSE, from) = NaiveIndexSet(text, n, set, FALSE, from, FALSE))
        & (Ropes.IndexChar(r, "e", from) = NaiveFind(text, n, "e", from, NIL))
        & (Ropes.RIndexChar(r, "e", from) = NaiveRFind(text, n, "e", from, NIL))
    END;
    FOR i := 0 TO LEN(pats) - 1 DO
      FOR m := 0 TO 2 DO
        okMapped := okMapped & (Ropes.CountMapped(r, pats[i], mappers[m]) = NaiveCount(text, n, pats[i], mappers[m]))
      END;
      ok := ok & (Ropes.Count(r, pats[i]) = NaiveCount(text, n, pats[i], NIL))
    END
  END
END CompareSearches;

PROCEDURE CheckSearchWalk;
  VAR text, run: ARRAY 128 OF CHAR; n, i: LONGINT; r: Ropes.Rope; pats: ARRAY 11, 24 OF CHAR; runPats: ARRAY 4, 24 OF CHAR;
      ok, okSet, okMapped: BOOLEAN; set: Ropes.CharSet;
BEGIN
  text := "The Quick BROWN Fox; the quICK brown fOX. THE end, The ENd, the End: thethe xyzabc  0123";
  n := 0;
  WHILE text[n] # 0X DO INC(n) END;
  pats[0] := "the"; pats[1] := "quick brown"; pats[2] := "fox"; pats[3] := "the end";
  pats[4] := "thethe"; pats[5] := "zzz"; pats[6] := "o"; pats[7] := "THE"; pats[8] := "xyz"; pats[9] := "abc";
  pats[10] := "";
  ok := TRUE; okSet := TRUE; okMapped := TRUE;
  CompareSearches(text, n, pats, ok, okMapped, okSet);

  (* A run of "a"s between two "b"s: going forward, "aab" is a candidate
     at every "a" and fails only at the character after, so candidates
     that cross into the next leaf and then fail are everywhere, and so
     going backward for "baa".  Such a failed candidate is what shows up
     a search that loses its place checking one. *)
  run[0] := "b";
  FOR i := 1 TO 80 DO run[i] := "a" END;
  run[81] := "b"; run[82] := 0X;
  runPats[0] := "aab"; runPats[1] := "baa"; runPats[2] := "aaaaaaaaaaaaaaaaaaaab"; runPats[3] := "baaaaaaaaaaaaaaaaaaaa";
  CompareSearches(run, 82, runPats, ok, okMapped, okSet);

  Check(ok, "Find, RFind, Count: every pattern and from, four tree shapes, agree with a naive search");
  Check(okMapped, "FindMapped, RFindMapped, CountMapped: LowerChar and a swap mapper agree with a naive search");
  Check(okSet, "IndexSet, RIndexSet, IndexChar, RIndexChar: every from, both tests, agree with a naive scan");
  Ropes.MakeCharSet("aeiou ", set);

  r := Chunked(text, n, 17);
  Check(Ropes.FindMapped(r, "quick brown", 0, Ropes.LowerChar) = 4, "FindMapped: case-insensitive with LowerChar");
  Check(Ropes.FindMapped(r, "THE", 0, Ropes.LowerChar) = -1, "FindMapped: the pattern is not mapped");
  Check(Ropes.FindMapped(r, "xyz", 0, SwapMapper) = n - 9, "FindMapped: a swap mapper finds abc for xyz");
  Check(Ropes.FindMapped(r, "the", 1, NIL) = Ropes.Find(r, "the", 1), "FindMapped: a NIL mapper is Find");
  Check((Ropes.Count(r, "the") = 4) & (Ropes.CountMapped(r, "the", Ropes.LowerChar) = 7), "Count and CountMapped");
  Check(Ropes.Count(r, "") = 0, "Count: the empty pattern never occurs");
  Check((Ropes.Count(NIL, "x") = 0) & (Ropes.Find(NIL, "x", 0) = -1) & (Ropes.IndexSet(NIL, set, TRUE, 0) = -1), "searches of NIL");

  (* Twenty million characters: until the searches walked leaves, each
     did a Fetch from the root per character, ~20 times slower. *)
  r := Ropes.Repeat(Ropes.FromString("0123456789"), 2000000);
  Check((Ropes.Find(r, "0123x", 0) = -1) & (Ropes.RFind(r, "9012", Ropes.Length(r)) = Ropes.Length(r) - 11),
        "Find and RFind on a twenty-million-character rope");
  Check(Ropes.Count(r, "90") = 1999999, "Count on a twenty-million-character rope")
END CheckSearchWalk;

PROCEDURE CheckCharSetAndToken;
  VAR r: Ropes.Rope; set: Ropes.CharSet; start, len: LONGINT;
BEGIN
  r := Ropes.Cat(Ropes.FromString("   alpha 12 bravo "), Ropes.FromString("       charlie3456789   "));
  Ropes.MakeCharSet("0123456789", set);
  Check((Ropes.IndexSet(r, set, TRUE, 0) = 9) & (Ropes.RIndexSet(r, set, TRUE, Ropes.Length(r)) = 38), "IndexSet, RIndexSet");
  Check(Ropes.CountSet(r, set) = 9, "CountSet");
  Check((Ropes.IndexNonBlank(r, 0) = 3) & (Ropes.RIndexNonBlank(r, 100) = 38) & (Ropes.IndexNonBlank(r, 8) = 9),
        "IndexNonBlank, RIndexNonBlank");
  Check(Ropes.IndexNonBlank(Ropes.FromString("    "), 0) = -1, "IndexNonBlank: all blank");
  Ropes.FindToken(r, set, TRUE, 12, start, len);
  Check((start = 32) & (len = 7) & StrEq(Ropes.Substring(r, start, len), "3456789"), "FindToken: a digit run across a leaf boundary");
  Ropes.MakeCharSet(" ", set);
  Ropes.FindToken(r, set, FALSE, 0, start, len);
  Check(StrEq(Ropes.Substring(r, start, len), "alpha"), "FindToken: not in set (outside)");
  Ropes.MakeCharSet("xyz", set);
  Ropes.FindToken(r, set, TRUE, 5, start, len);
  Check((start = 5) & (len = 0), "FindToken: none gives start = from, len = 0");
  Ropes.FindToken(r, set, TRUE, -3, start, len);
  Check((start = 0) & (len = 0), "FindToken: a negative from is treated as 0")
END CheckCharSetAndToken;

PROCEDURE CheckReplace;
  VAR r: Ropes.Rope;
BEGIN
  r := Ropes.Cat(Ropes.FromString("Hello, "), Ropes.FromString("World!"));
  Check(StrEq(Ropes.Replace(r, 7, 5, Ropes.FromString("Oberon")), "Hello, Oberon!"), "Replace: a slice across the leaf boundary");
  Check(StrEq(Ropes.Replace(r, 5, 0, Ropes.FromString(" there")), "Hello there, World!"), "Replace: len 0 inserts");
  Check(StrEq(Ropes.Replace(r, 7, 100, Ropes.FromString("you")), "Hello, you"), "Replace: len past the end is clamped");
  Check(StrEq(Ropes.Replace(r, -5, 7, NIL), "World!"), "Replace: a negative pos is clamped, NIL by removes");
  Check(StrEq(Ropes.Replace(r, 99, 3, Ropes.FromString("?")), "Hello, World!?"), "Replace: pos past the end appends");
  Check(StrEq(Ropes.ReplaceChar(r, 7, "w"), "Hello, world!") & StrEq(r, "Hello, World!"), "ReplaceChar; r itself unchanged");
  Check(StrEq(Ropes.ReplaceChar(r, 12, "?"), "Hello, World?"), "ReplaceChar: the last character")
END CheckReplace;

PROCEDURE CheckTranslate;
  VAR r, t: Ropes.Rope; m: Ropes.Mapping;
BEGIN
  r := Ropes.Cat(Ropes.FromString("abc to xyz, "), Ropes.FromString("0123456789"));
  Check(Ropes.MakeMapping("abcxyz", "xyzabc", m), "MakeMapping: valid");
  t := Ropes.Translate(r, m);
  Check(StrEq(t, "xyz to abc, 0123456789") & (Ropes.Depth(t) = Ropes.Depth(r)), "Translate: characters mapped, tree shape kept");
  Check(~Ropes.MakeMapping("abc", "xy", m) & StrEq(Ropes.Translate(r, m), "abc to xyz, 0123456789"),
        "MakeMapping: different lengths fail, leaving the identity");
  Check(~Ropes.MakeMapping("aba", "xyz", m), "MakeMapping: a repeated from character fails");
  Check(Ropes.MakeMapping("0123456789", "##########", m) & StrEq(Ropes.Translate(r, m), "abc to xyz, ##########"),
        "Translate: many to one");
  Check(Ropes.Translate(NIL, m) = NIL, "Translate of NIL is NIL")
END CheckTranslate;

PROCEDURE CheckCompareStringAndNoCase;
  VAR text: ARRAY 64 OF CHAR; prefix: ARRAY 64 OF CHAR; r, a, b: Ropes.Rope; i, j, n: LONGINT; ok, okNoCase: BOOLEAN;
BEGIN
  text := "The Quick BROWN fox Jumps over THE lazy dog";
  n := 0;
  WHILE text[n] # 0X DO INC(n) END;
  r := Chunked(text, n, 17);
  ok := TRUE; okNoCase := TRUE;
  FOR i := 0 TO n DO
    FOR j := 0 TO i - 1 DO prefix[j] := text[j] END;
    prefix[i] := 0X;
    ok := ok & (Ropes.CompareString(r, prefix) = Ropes.Compare(r, Ropes.FromString(prefix)))
             & (Ropes.CompareString(Chunked(text, i, 17), text) = Ropes.Compare(Chunked(text, i, 17), r));
    a := Chunked(text, i, 17);
    FOR j := 0 TO n DO
      b := Ropes.LowercaseAscii(Chunked(text, j, 23));
      okNoCase := okNoCase
        & (Ropes.CompareNoCase(a, b) = Ropes.Compare(Ropes.LowercaseAscii(a), b))
        & (Ropes.CompareNoCase(b, a) = Ropes.Compare(b, Ropes.LowercaseAscii(a)))
        & (Ropes.EqualNoCase(a, b) = (i = j))
    END
  END;
  Check(ok, "CompareString: every prefix, both ways, agrees with Compare");
  Check(okNoCase, "CompareNoCase, EqualNoCase: every pair of prefixes agrees with Compare on LowercaseAscii");
  Check(Ropes.EqualString(r, text) & ~Ropes.EqualString(r, "The") & Ropes.EqualString(NIL, ""), "EqualString");
  Check(~Ropes.Equal(r, Ropes.LowercaseAscii(r)) & Ropes.EqualNoCase(r, Ropes.UppercaseAscii(r)), "EqualNoCase: across case")
END CheckCompareStringAndNoCase;

PROCEDURE CheckHash;
  VAR text: ARRAY 64 OF CHAR; n: LONGINT;
BEGIN
  (* The same values as GNAT's Ada.Strings.Hash and
     Ada.Strings.Hash_Case_Insensitive, as printed by the Ada Ropes
     package's rope_tool hash and hashci. *)
  Check(Ropes.Hash(Ropes.FromString("Hello, World")) = 3446766348, "Hash: GNAT's Ada.Strings.Hash value");
  Check(Ropes.HashNoCase(Ropes.FromString("hELLO, wORLD")) = 4000297740, "HashNoCase: GNAT's Hash_Case_Insensitive value");
  text := "The Quick BROWN fox Jumps over THE lazy dog";
  n := 0;
  WHILE text[n] # 0X DO INC(n) END;
  Check(Ropes.Hash(Chunked(text, n, 17)) = Ropes.Hash(Chunked(text, n, 23)), "Hash: the same whatever the leaves");
  Check(Ropes.Hash(Chunked(text, n, 17)) # Ropes.Hash(Ropes.LowercaseAscii(Chunked(text, n, 17))), "Hash: distinguishes case");
  Check(Ropes.HashNoCase(Chunked(text, n, 17)) = Ropes.HashNoCase(Ropes.UppercaseAscii(Chunked(text, n, 23))),
        "HashNoCase: the same for any case");
  Check((Ropes.Hash(NIL) = 0) & (Ropes.HashNoCase(NIL) = 0), "Hash of NIL is 0")
END CheckHash;

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
  CheckEscape;
  CheckIndexCharAndRFind;
  CheckContainsPattern;
  CheckBlit;
  CheckIterate;
  CheckSplit;
  CheckIterator;
  CheckIterateChunks;
  CheckCompareLeafBoundaries;
  CheckWriteReadRider;
  CheckReadAll;
  CheckReadWriteFile;
  CheckBlitAcrossLeaves;
  CheckEscapeAcrossLeaves;
  CheckSearchWalk;
  CheckCharSetAndToken;
  CheckReplace;
  CheckTranslate;
  CheckCompareStringAndNoCase;
  CheckHash;
  Summary
END RopeTest.
