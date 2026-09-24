MODULE RopeTest;

(* A battery of fixed checks against Rope.Mod, printed as "ok - NAME" /
   "not ok - NAME" lines plus a final summary, and HALT(1) if anything
   failed, so tests/run-tests.sh's exit-status comparison catches a
   regression even if the output itself is not read. *)

IMPORT Files, Out, Rope;

VAR
  passed, failed: LONGINT;
  splitCount: LONGINT;
  splitBuf: ARRAY 8 OF ARRAY 16 OF CHAR;
  iterateBuf: ARRAY 32 OF CHAR;
  iterateLen: LONGINT;
  chunkCalls: LONGINT;
  chunkEmpty: BOOLEAN;
  chunkLens: ARRAY 8 OF LONGINT;
  chunkAcc: Rope.Rope;

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

PROCEDURE CheckEscape;
  VAR r: Rope.Rope; buf: ARRAY 3 OF CHAR;
BEGIN
  Check(StrEq(Rope.Escape(Rope.FromString('say "hi"')), 'say \"hi\"'), "Escape: double quote");

  buf[0] := "a"; buf[1] := 9X; buf[2] := 0X;
  r := Rope.FromString(buf);
  Check(StrEq(Rope.Escape(r), "a\t"), "Escape: tab");

  Check(StrEq(Rope.Escape(Rope.FromString("\")), "\\"), "Escape: backslash");
  Check(Rope.Escape(NIL) = NIL, "Escape of NIL is NIL");
END CheckEscape;

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
  VAR r: Rope.Rope;
BEGIN
  r := Rope.FromString("abcde");

  iterateLen := 0; iterateBuf[0] := 0X;
  Rope.Iterate(r, CollectChar);
  Check(iterateBuf = "abcde", "Iterate: visits every character in order");

  iterateLen := 0; iterateBuf[0] := 0X;
  Rope.Iterate(r, StopAfterTwoChars);
  Check(iterateBuf = "ab", "Iterate: stops early when visit returns FALSE");

  iterateLen := 0; iterateBuf[0] := 0X;
  Rope.Iterate(NIL, CollectChar);
  Check(iterateBuf = "", "Iterate of NIL visits nothing");
END CheckIterate;

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

(* --- IterateChunks, linear Compare, WriteRider/ReadLineRider --- *)

(* Source split into leaves of size characters each (size > 16, the
   short-leaf merge threshold, so Cat keeps them as separate leaves):
   the first len characters of s only. *)
PROCEDURE Chunked(s: ARRAY OF CHAR; len, size: LONGINT): Rope.Rope;
  VAR r: Rope.Rope; i, n: LONGINT;
BEGIN
  r := NIL;
  i := 0;
  WHILE i < len DO
    n := size;
    IF i + n > len THEN n := len - i END;
    r := Rope.Cat(r, Rope.FromSubstring(s, i, n));
    INC(i, n)
  END;
  RETURN r
END Chunked;

(* 200 leaves of 50 characters each. *)
PROCEDURE ManyLeaves(): Rope.Rope;
  VAR r: Rope.Rope; i: LONGINT;
BEGIN
  r := NIL;
  FOR i := 1 TO 200 DO r := Rope.Cat(r, Rope.Make(50, CHR(ORD("a") + i MOD 26))) END;
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
  chunkAcc := Rope.Cat(chunkAcc, Rope.FromSubstring(chunk, 0, LEN(chunk)));
  INC(chunkCalls);
  RETURN TRUE
END CollectChunk;

PROCEDURE StopAfterTwoChunks(VAR chunk: ARRAY OF CHAR): BOOLEAN;
BEGIN
  INC(chunkCalls);
  RETURN chunkCalls < 2
END StopAfterTwoChunks;

PROCEDURE CheckIterateChunks;
  VAR r: Rope.Rope; buf: ARRAY 3 OF CHAR;
BEGIN
  chunkCalls := 0;
  Rope.IterateChunks(NIL, CountChunk);
  Check(chunkCalls = 0, "IterateChunks of NIL visits nothing");

  r := ManyLeaves();
  chunkCalls := 0; chunkEmpty := FALSE;
  Rope.IterateChunks(r, CountChunk);
  Check(chunkCalls > 1, "IterateChunks: a many-leaf rope arrives as more than one chunk");
  Check(~chunkEmpty, "IterateChunks: never passes an empty chunk");

  chunkCalls := 0; chunkAcc := NIL;
  Rope.IterateChunks(r, CollectChunk);
  Check(Rope.Equal(chunkAcc, r) & (Rope.Length(chunkAcc) = Rope.Length(r)),
        "IterateChunks: chunks concatenate to the whole rope");

  chunkCalls := 0;
  Rope.IterateChunks(r, StopAfterTwoChunks);
  Check(chunkCalls = 2, "IterateChunks: stops early when visit returns FALSE");

  (* A leaf holding a 0X: the chunk is all LEN(chunk) characters, not cut
     short at the 0X the way a 0X-terminated string would be. *)
  buf[0] := "a"; buf[1] := 0X; buf[2] := "b";
  chunkCalls := 0;
  Rope.IterateChunks(Rope.FromSubstring(buf, 0, 3), CountChunk);
  Check((chunkCalls = 1) & (chunkLens[0] = 3), "IterateChunks: a chunk containing 0X is passed whole");
END CheckIterateChunks;

(* Compare's oracle: Rope.Compare must agree in sign with Oberon's own
   string comparison, whatever the two ropes' leaf boundaries are. *)
PROCEDURE Agrees(a, b: Rope.Rope): BOOLEAN;
  VAR sa, sb: ARRAY 256 OF CHAR; c: INTEGER;
BEGIN
  Rope.ToString(a, sa);
  Rope.ToString(b, sb);
  c := Rope.Compare(a, b);
  RETURN ((c < 0) = (sa < sb)) & ((c = 0) = (sa = sb)) & ((c > 0) = (sa > sb))
END Agrees;

PROCEDURE CheckCompareLeafBoundaries;
  VAR base, changed: ARRAY 201 OF CHAR; a, b, big1, big2: Rope.Rope; i, p, d, len: LONGINT; ok: BOOLEAN;
BEGIN
  FOR i := 0 TO 199 DO base[i] := CHR(ORD("a") + (i + 1) MOD 26) END;
  base[200] := 0X;
  a := Chunked(base, 200, 17);
  Check(Rope.Equal(a, Chunked(base, 200, 23)) & Rope.Equal(Chunked(base, 200, 23), a),
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
  big1 := Rope.Repeat(Rope.FromString("0123456789"), 2000000);
  big2 := Rope.Repeat(Rope.FromString("01234567890123456789"), 1000000);
  Check(Rope.Equal(big1, big2), "Compare: two large equal ropes with no shared structure");
  Check(Rope.Compare(big1, Rope.AppendChar(big2, "x")) < 0, "Compare: a large rope sorts before itself plus one more character");
  Check(Rope.Compare(big1, big1) = 0, "Compare: a rope equals itself (shared tree)")
END CheckCompareLeafBoundaries;

PROCEDURE WriteLine(VAR w: Files.Rider; r: Rope.Rope);
BEGIN
  Rope.WriteRider(w, r);
  Files.Write(w, 0AX)
END WriteLine;

PROCEDURE CheckWriteReadRider;
  CONST n = 9;
  VAR f: Files.File; w, rd: Files.Rider; line, big: Rope.Rope; lens: ARRAY n OF LONGINT;
      i: LONGINT; ok: BOOLEAN; buf: ARRAY 3 OF CHAR;
BEGIN
  lens[0] := 0; lens[1] := 1; lens[2] := 4095; lens[3] := 4096; lens[4] := 4097;
  lens[5] := 8191; lens[6] := 8192; lens[7] := 8193; lens[8] := 100000;

  (* Files.New without Files.Register: a temporary file, never given a
     name on disk. *)
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  Rope.WriteRider(w, NIL);
  Check(Files.Length(f) = 0, "WriteRider of NIL writes nothing");

  FOR i := 0 TO n - 1 DO WriteLine(w, Rope.Make(lens[i], "q")) END;
  Files.Set(rd, f, 0);
  ok := TRUE;
  FOR i := 0 TO n - 1 DO
    ok := ok & Rope.ReadLineRider(rd, line) & Rope.Equal(line, Rope.Make(lens[i], "q"))
  END;
  Check(ok, "WriteRider/ReadLineRider: lines of length 0, 1, 4095..4097, 8191..8193, 100000 each read back exactly");
  Check(~Rope.ReadLineRider(rd, line) & (line = NIL) & rd.eof, "ReadLineRider: FALSE, with NIL, at end of file");
  Files.Close(f);

  (* The last line exactly fills ReadLineRider's chunk, with no line feed
     after it in the file at all. *)
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  Rope.WriteRider(w, Rope.Make(4096, "q"));
  Files.Set(rd, f, 0);
  Check(Rope.ReadLineRider(rd, line) & Rope.Equal(line, Rope.Make(4096, "q")),
        "ReadLineRider: an unterminated last line of exactly 4096 characters");
  Check(~Rope.ReadLineRider(rd, line), "ReadLineRider: FALSE after an unterminated last line");
  Files.Close(f);

  (* A 0X inside a line is just another character, both ways. *)
  buf[0] := "a"; buf[1] := 0X; buf[2] := "b";
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  WriteLine(w, Rope.FromSubstring(buf, 0, 3));
  Files.Set(rd, f, 0);
  Check(Rope.ReadLineRider(rd, line) & (Rope.Length(line) = 3) & (Rope.Fetch(line, 1) = 0X) & (Rope.Fetch(line, 2) = "b"),
        "WriteRider/ReadLineRider: a 0X inside a line round-trips");
  Files.Close(f);

  (* Far longer than ToString into ArgParser.MaxStringLength-sized buffers
     could ever carry. *)
  big := Rope.Repeat(Rope.FromString("0123456789"), 100000);
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  WriteLine(w, big);
  Files.Set(rd, f, 0);
  Check(Rope.ReadLineRider(rd, line) & (Rope.Length(line) = 1000000) & Rope.Equal(line, big),
        "WriteRider/ReadLineRider: a million-character rope round-trips");
  Files.Close(f)
END CheckWriteReadRider;

(* --- ReadAll, ReadFile, WriteFile --- *)

(* A rope of every byte value, 0X to 0FFX, n times over. *)
PROCEDURE AllBytes(n: LONGINT): Rope.Rope;
  VAR buf: ARRAY 256 OF CHAR; i: LONGINT;
BEGIN
  FOR i := 0 TO 255 DO buf[i] := CHR(i) END;
  RETURN Rope.Repeat(Rope.FromSubstring(buf, 0, 256), n)
END AllBytes;

(* "one" CR LF "two" FF "three" 0X "four" LF "no final newline": what
   reading line by line would lose -- the same bytes as
   tests/data/exact.bin. *)
PROCEDURE Tricky(): Rope.Rope;
  VAR buf: ARRAY 64 OF CHAR; r: Rope.Rope;
BEGIN
  r := Rope.FromString("one");
  r := Rope.AppendChar(Rope.AppendChar(r, 0DX), 0AX);
  r := Rope.AppendChar(Rope.Cat(r, Rope.FromString("two")), 0CX);
  r := Rope.AppendChar(Rope.Cat(r, Rope.FromString("three")), 0X);
  r := Rope.AppendChar(Rope.Cat(r, Rope.FromString("four")), 0AX);
  buf := "no final newline";
  RETURN Rope.Cat(r, Rope.FromString(buf))
END Tricky;

PROCEDURE CheckReadAll;
  CONST n = 7;
  VAR f: Files.File; w, rd: Files.Rider; r: Rope.Rope; sizes: ARRAY n OF LONGINT; i: LONGINT; ok: BOOLEAN;
BEGIN
  f := Files.New("RopeTest.tmp");
  Files.Set(w, f, 0);
  Rope.WriteRider(w, Tricky());
  Files.Set(rd, f, 0);
  r := Rope.ReadAll(rd);
  Check(Rope.Equal(r, Tricky()) & (Rope.Length(r) = Files.Length(f)),
        "ReadAll: CR, form feed, 0X, and no final line feed survive, byte for byte");
  Check(Rope.ReadAll(rd) = NIL, "ReadAll at end of file is NIL");
  Files.Set(rd, f, 9);  (* "one" CR LF "two" FF is 9 bytes. *)
  Check(StrEq(Rope.Substring(Rope.ReadAll(rd), 0, 5), "three"), "ReadAll: reads from the rider's position to the end");
  Files.Close(f);

  sizes[0] := 1; sizes[1] := 4095; sizes[2] := 4096; sizes[3] := 4097;
  sizes[4] := 8192; sizes[5] := 8193; sizes[6] := 100000;
  ok := TRUE;
  FOR i := 0 TO n - 1 DO
    f := Files.New("RopeTest.tmp");
    Files.Set(w, f, 0);
    Rope.WriteRider(w, Rope.Make(sizes[i], "z"));
    Files.Set(rd, f, 0);
    ok := ok & Rope.Equal(Rope.ReadAll(rd), Rope.Make(sizes[i], "z"));
    Files.Close(f)
  END;
  Check(ok, "ReadAll: files of 1, 4095..4097, 8192, 8193, 100000 bytes each read back exactly")
END CheckReadAll;

PROCEDURE CheckReadWriteFile;
  CONST name = "RopeTest-file.tmp";
  VAR r, big: Rope.Rope; res: INTEGER;
BEGIN
  Rope.WriteFile(name, AllBytes(3));
  Check(Rope.ReadFile(name, r) & Rope.Equal(r, AllBytes(3)), "WriteFile/ReadFile: all 256 byte values survive a round trip");

  Rope.WriteFile(name, Rope.FromString("a longer first version"));
  Rope.WriteFile(name, Rope.FromString("short"));
  Check(Rope.ReadFile(name, r) & StrEq(r, "short"), "WriteFile replaces an existing file, not overwrites its start");

  Rope.WriteFile(name, NIL);
  Check(Rope.ReadFile(name, r) & (r = NIL), "WriteFile of NIL makes an empty file; ReadFile of it is TRUE with NIL");

  big := Rope.Repeat(Rope.FromString("0123456789"), 100000);
  Rope.WriteFile(name, big);
  Check(Rope.ReadFile(name, r) & Rope.Equal(r, big), "WriteFile/ReadFile: a million-character rope round-trips");

  Files.Delete(name, res);
  r := Rope.FromString("not reset");
  Check(~Rope.ReadFile(name, r) & (r = NIL), "ReadFile of a missing file is FALSE, with NIL")
END CheckReadWriteFile;

(* --- Blit and Escape across leaves --- *)

PROCEDURE CheckBlitAcrossLeaves;
  VAR base: ARRAY 201 OF CHAR; dst: ARRAY 204 OF CHAR; r: Rope.Rope; start, len, k: LONGINT; ok: BOOLEAN;
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
      Rope.Blit(r, start, dst, 1, len);
      ok := ok & (dst[0] = "#") & (dst[1 + len] = "#");
      FOR k := 0 TO len - 1 DO ok := ok & (dst[1 + k] = base[start + k]) END
    END
  END;
  Check(ok, "Blit: every start and length across leaf boundaries copies exactly that range")
END CheckBlitAcrossLeaves;

PROCEDURE CheckEscapeAcrossLeaves;
  CONST pieceLen = 10;
  VAR piece: ARRAY pieceLen OF CHAR; flat: ARRAY 50 * pieceLen + 1 OF CHAR; p, e: Rope.Rope; k: LONGINT;
BEGIN
  (* One of each kind of escape, plus two plain characters. *)
  piece[0] := "a"; piece[1] := "\"; piece[2] := '"'; piece[3] := 0AX; piece[4] := 09X;
  piece[5] := 0DX; piece[6] := 0X; piece[7] := 0FFX; piece[8] := 01X; piece[9] := "z";
  p := Rope.FromSubstring(piece, 0, pieceLen);
  Check(StrEq(Rope.Escape(p), 'a\\\"\n\t\r\000\255\001z'), "Escape: every kind of escape, including \NNN for 0X and 0FFX");

  (* Escaping is per character, so escaping n copies of piece must give n
     copies of its escape -- whatever the leaf boundaries.  Chunked by 17
     puts them in the middle of pieces, and escapes, too. *)
  FOR k := 0 TO 50 * pieceLen - 1 DO flat[k] := piece[k MOD pieceLen] END;
  flat[50 * pieceLen] := 0X;
  Check(Rope.Equal(Rope.Escape(Chunked(flat, 50 * pieceLen, 17)), Rope.Repeat(Rope.Escape(p), 50)),
        "Escape: leaf boundaries in the middle of the input don't change the result");

  (* Far more output than Escape's 4096-character buffer, so it is
     flushed many times, with escapes landing across those flushes too. *)
  e := Rope.Escape(Rope.Repeat(p, 100000));
  Check((Rope.Length(e) = 100000 * Rope.Length(Rope.Escape(p))) & Rope.Equal(e, Rope.Repeat(Rope.Escape(p), 100000)),
        "Escape: a million-character input escapes the same as its pieces")
END CheckEscapeAcrossLeaves;

(* --- Ported back from the Ada Ropes package: faster search, sets,
   tokens, Count, Replace/ReplaceChar, Translate, mapped search,
   CompareString, case-insensitive comparison, Hash --- *)

(* Searches' oracles: the same search, done naively over a flat array
   s[0 .. n-1] with Rope.Mod's own clamping conventions, so that a rope
   search can be checked against it whatever the rope's leaves.  f, if
   not NIL, maps s's characters before comparing. *)
PROCEDURE Mapped(ch: CHAR; f: Rope.Mapper): CHAR;
BEGIN
  IF f # NIL THEN RETURN f(ch) END;
  RETURN ch
END Mapped;

PROCEDURE MatchesAt(VAR s: ARRAY OF CHAR; i: LONGINT; pat: ARRAY OF CHAR; patLen: LONGINT; f: Rope.Mapper): BOOLEAN;
  VAR k: LONGINT;
BEGIN
  FOR k := 0 TO patLen - 1 DO
    IF Mapped(s[i + k], f) # pat[k] THEN RETURN FALSE END
  END;
  RETURN TRUE
END MatchesAt;

PROCEDURE NaiveFind(VAR s: ARRAY OF CHAR; n: LONGINT; pat: ARRAY OF CHAR; from: LONGINT; f: Rope.Mapper): LONGINT;
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

PROCEDURE NaiveRFind(VAR s: ARRAY OF CHAR; n: LONGINT; pat: ARRAY OF CHAR; before: LONGINT; f: Rope.Mapper): LONGINT;
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

PROCEDURE NaiveCount(VAR s: ARRAY OF CHAR; n: LONGINT; pat: ARRAY OF CHAR; f: Rope.Mapper): LONGINT;
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

PROCEDURE NaiveIndexSet(VAR s: ARRAY OF CHAR; n: LONGINT; VAR set: Rope.CharSet; inside: BOOLEAN; from: LONGINT; forward: BOOLEAN): LONGINT;
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
PROCEDURE RightDeep(s: ARRAY OF CHAR; len, size: LONGINT): Rope.Rope;
  VAR r: Rope.Rope; i: LONGINT;
BEGIN
  r := NIL;
  i := len - len MOD size;
  IF i = len THEN DEC(i, size) END;
  WHILE i >= 0 DO
    r := Rope.Cat(Rope.FromSubstring(s, i, len - i - Rope.Length(r)), r);
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
  VAR i, from: LONGINT; r: Rope.Rope; set: Rope.CharSet; mappers: ARRAY 3 OF Rope.Mapper; m, shape: INTEGER;
BEGIN
  mappers[0] := NIL; mappers[1] := Rope.LowerChar; mappers[2] := SwapMapper;
  Rope.MakeCharSet("aeiou ", set);
  FOR shape := 0 TO 3 DO
    IF shape = 0 THEN r := Chunked(text, n, 17)
    ELSIF shape = 1 THEN r := Chunked(text, n, 23)
    ELSIF shape = 2 THEN r := RightDeep(text, n, 17)
    ELSE r := Rope.Balance(Chunked(text, n, 17))
    END;
    FOR from := -2 TO n + 2 DO
      FOR i := 0 TO LEN(pats) - 1 DO
        ok := ok & (Rope.Find(r, pats[i], from) = NaiveFind(text, n, pats[i], from, NIL))
                 & (Rope.RFind(r, pats[i], from) = NaiveRFind(text, n, pats[i], from, NIL));
        FOR m := 1 TO 2 DO
          okMapped := okMapped
            & (Rope.FindMapped(r, pats[i], from, mappers[m]) = NaiveFind(text, n, pats[i], from, mappers[m]))
            & (Rope.RFindMapped(r, pats[i], from, mappers[m]) = NaiveRFind(text, n, pats[i], from, mappers[m]))
        END
      END;
      okSet := okSet
        & (Rope.IndexSet(r, set, TRUE, from) = NaiveIndexSet(text, n, set, TRUE, from, TRUE))
        & (Rope.IndexSet(r, set, FALSE, from) = NaiveIndexSet(text, n, set, FALSE, from, TRUE))
        & (Rope.RIndexSet(r, set, TRUE, from) = NaiveIndexSet(text, n, set, TRUE, from, FALSE))
        & (Rope.RIndexSet(r, set, FALSE, from) = NaiveIndexSet(text, n, set, FALSE, from, FALSE))
        & (Rope.IndexChar(r, "e", from) = NaiveFind(text, n, "e", from, NIL))
        & (Rope.RIndexChar(r, "e", from) = NaiveRFind(text, n, "e", from, NIL))
    END;
    FOR i := 0 TO LEN(pats) - 1 DO
      FOR m := 0 TO 2 DO
        okMapped := okMapped & (Rope.CountMapped(r, pats[i], mappers[m]) = NaiveCount(text, n, pats[i], mappers[m]))
      END;
      ok := ok & (Rope.Count(r, pats[i]) = NaiveCount(text, n, pats[i], NIL))
    END
  END
END CompareSearches;

PROCEDURE CheckSearchWalk;
  VAR text, run: ARRAY 128 OF CHAR; n, i: LONGINT; r: Rope.Rope; pats: ARRAY 11, 24 OF CHAR; runPats: ARRAY 4, 24 OF CHAR;
      ok, okSet, okMapped: BOOLEAN; set: Rope.CharSet;
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
  Rope.MakeCharSet("aeiou ", set);

  r := Chunked(text, n, 17);
  Check(Rope.FindMapped(r, "quick brown", 0, Rope.LowerChar) = 4, "FindMapped: case-insensitive with LowerChar");
  Check(Rope.FindMapped(r, "THE", 0, Rope.LowerChar) = -1, "FindMapped: the pattern is not mapped");
  Check(Rope.FindMapped(r, "xyz", 0, SwapMapper) = n - 9, "FindMapped: a swap mapper finds abc for xyz");
  Check(Rope.FindMapped(r, "the", 1, NIL) = Rope.Find(r, "the", 1), "FindMapped: a NIL mapper is Find");
  Check((Rope.Count(r, "the") = 4) & (Rope.CountMapped(r, "the", Rope.LowerChar) = 7), "Count and CountMapped");
  Check(Rope.Count(r, "") = 0, "Count: the empty pattern never occurs");
  Check((Rope.Count(NIL, "x") = 0) & (Rope.Find(NIL, "x", 0) = -1) & (Rope.IndexSet(NIL, set, TRUE, 0) = -1), "searches of NIL");

  (* Twenty million characters: until the searches walked leaves, each
     did a Fetch from the root per character, ~20 times slower. *)
  r := Rope.Repeat(Rope.FromString("0123456789"), 2000000);
  Check((Rope.Find(r, "0123x", 0) = -1) & (Rope.RFind(r, "9012", Rope.Length(r)) = Rope.Length(r) - 11),
        "Find and RFind on a twenty-million-character rope");
  Check(Rope.Count(r, "90") = 1999999, "Count on a twenty-million-character rope")
END CheckSearchWalk;

PROCEDURE CheckCharSetAndToken;
  VAR r: Rope.Rope; set: Rope.CharSet; start, len: LONGINT;
BEGIN
  r := Rope.Cat(Rope.FromString("   alpha 12 bravo "), Rope.FromString("       charlie3456789   "));
  Rope.MakeCharSet("0123456789", set);
  Check((Rope.IndexSet(r, set, TRUE, 0) = 9) & (Rope.RIndexSet(r, set, TRUE, Rope.Length(r)) = 38), "IndexSet, RIndexSet");
  Check(Rope.CountSet(r, set) = 9, "CountSet");
  Check((Rope.IndexNonBlank(r, 0) = 3) & (Rope.RIndexNonBlank(r, 100) = 38) & (Rope.IndexNonBlank(r, 8) = 9),
        "IndexNonBlank, RIndexNonBlank");
  Check(Rope.IndexNonBlank(Rope.FromString("    "), 0) = -1, "IndexNonBlank: all blank");
  Rope.FindToken(r, set, TRUE, 12, start, len);
  Check((start = 32) & (len = 7) & StrEq(Rope.Substring(r, start, len), "3456789"), "FindToken: a digit run across a leaf boundary");
  Rope.MakeCharSet(" ", set);
  Rope.FindToken(r, set, FALSE, 0, start, len);
  Check(StrEq(Rope.Substring(r, start, len), "alpha"), "FindToken: not in set (outside)");
  Rope.MakeCharSet("xyz", set);
  Rope.FindToken(r, set, TRUE, 5, start, len);
  Check((start = 5) & (len = 0), "FindToken: none gives start = from, len = 0");
  Rope.FindToken(r, set, TRUE, -3, start, len);
  Check((start = 0) & (len = 0), "FindToken: a negative from is treated as 0")
END CheckCharSetAndToken;

PROCEDURE CheckReplace;
  VAR r: Rope.Rope;
BEGIN
  r := Rope.Cat(Rope.FromString("Hello, "), Rope.FromString("World!"));
  Check(StrEq(Rope.Replace(r, 7, 5, Rope.FromString("Oberon")), "Hello, Oberon!"), "Replace: a slice across the leaf boundary");
  Check(StrEq(Rope.Replace(r, 5, 0, Rope.FromString(" there")), "Hello there, World!"), "Replace: len 0 inserts");
  Check(StrEq(Rope.Replace(r, 7, 100, Rope.FromString("you")), "Hello, you"), "Replace: len past the end is clamped");
  Check(StrEq(Rope.Replace(r, -5, 7, NIL), "World!"), "Replace: a negative pos is clamped, NIL by removes");
  Check(StrEq(Rope.Replace(r, 99, 3, Rope.FromString("?")), "Hello, World!?"), "Replace: pos past the end appends");
  Check(StrEq(Rope.ReplaceChar(r, 7, "w"), "Hello, world!") & StrEq(r, "Hello, World!"), "ReplaceChar; r itself unchanged");
  Check(StrEq(Rope.ReplaceChar(r, 12, "?"), "Hello, World?"), "ReplaceChar: the last character")
END CheckReplace;

PROCEDURE CheckTranslate;
  VAR r, t: Rope.Rope; m: Rope.Mapping;
BEGIN
  r := Rope.Cat(Rope.FromString("abc to xyz, "), Rope.FromString("0123456789"));
  Check(Rope.MakeMapping("abcxyz", "xyzabc", m), "MakeMapping: valid");
  t := Rope.Translate(r, m);
  Check(StrEq(t, "xyz to abc, 0123456789") & (Rope.Depth(t) = Rope.Depth(r)), "Translate: characters mapped, tree shape kept");
  Check(~Rope.MakeMapping("abc", "xy", m) & StrEq(Rope.Translate(r, m), "abc to xyz, 0123456789"),
        "MakeMapping: different lengths fail, leaving the identity");
  Check(~Rope.MakeMapping("aba", "xyz", m), "MakeMapping: a repeated from character fails");
  Check(Rope.MakeMapping("0123456789", "##########", m) & StrEq(Rope.Translate(r, m), "abc to xyz, ##########"),
        "Translate: many to one");
  Check(Rope.Translate(NIL, m) = NIL, "Translate of NIL is NIL")
END CheckTranslate;

PROCEDURE CheckCompareStringAndNoCase;
  VAR text: ARRAY 64 OF CHAR; prefix: ARRAY 64 OF CHAR; r, a, b: Rope.Rope; i, j, n: LONGINT; ok, okNoCase: BOOLEAN;
BEGIN
  text := "The Quick BROWN fox Jumps over THE lazy dog";
  n := 0;
  WHILE text[n] # 0X DO INC(n) END;
  r := Chunked(text, n, 17);
  ok := TRUE; okNoCase := TRUE;
  FOR i := 0 TO n DO
    FOR j := 0 TO i - 1 DO prefix[j] := text[j] END;
    prefix[i] := 0X;
    ok := ok & (Rope.CompareString(r, prefix) = Rope.Compare(r, Rope.FromString(prefix)))
             & (Rope.CompareString(Chunked(text, i, 17), text) = Rope.Compare(Chunked(text, i, 17), r));
    a := Chunked(text, i, 17);
    FOR j := 0 TO n DO
      b := Rope.LowercaseAscii(Chunked(text, j, 23));
      okNoCase := okNoCase
        & (Rope.CompareNoCase(a, b) = Rope.Compare(Rope.LowercaseAscii(a), b))
        & (Rope.CompareNoCase(b, a) = Rope.Compare(b, Rope.LowercaseAscii(a)))
        & (Rope.EqualNoCase(a, b) = (i = j))
    END
  END;
  Check(ok, "CompareString: every prefix, both ways, agrees with Compare");
  Check(okNoCase, "CompareNoCase, EqualNoCase: every pair of prefixes agrees with Compare on LowercaseAscii");
  Check(Rope.EqualString(r, text) & ~Rope.EqualString(r, "The") & Rope.EqualString(NIL, ""), "EqualString");
  Check(~Rope.Equal(r, Rope.LowercaseAscii(r)) & Rope.EqualNoCase(r, Rope.UppercaseAscii(r)), "EqualNoCase: across case")
END CheckCompareStringAndNoCase;

PROCEDURE CheckHash;
  VAR text: ARRAY 64 OF CHAR; n: LONGINT;
BEGIN
  (* The same values as GNAT's Ada.Strings.Hash and
     Ada.Strings.Hash_Case_Insensitive, as printed by the Ada Ropes
     package's rope_tool hash and hashci. *)
  Check(Rope.Hash(Rope.FromString("Hello, World")) = 3446766348, "Hash: GNAT's Ada.Strings.Hash value");
  Check(Rope.HashNoCase(Rope.FromString("hELLO, wORLD")) = 4000297740, "HashNoCase: GNAT's Hash_Case_Insensitive value");
  text := "The Quick BROWN fox Jumps over THE lazy dog";
  n := 0;
  WHILE text[n] # 0X DO INC(n) END;
  Check(Rope.Hash(Chunked(text, n, 17)) = Rope.Hash(Chunked(text, n, 23)), "Hash: the same whatever the leaves");
  Check(Rope.Hash(Chunked(text, n, 17)) # Rope.Hash(Rope.LowercaseAscii(Chunked(text, n, 17))), "Hash: distinguishes case");
  Check(Rope.HashNoCase(Chunked(text, n, 17)) = Rope.HashNoCase(Rope.UppercaseAscii(Chunked(text, n, 23))),
        "HashNoCase: the same for any case");
  Check((Rope.Hash(NIL) = 0) & (Rope.HashNoCase(NIL) = 0), "Hash of NIL is 0")
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
