MODULE RopeTool;

(* Command-line demo of Rope.Mod: each subcommand builds one or two ropes
   from its string arguments with Rope.FromString and prints the result of
   one Rope operation.  Built on ArgParser, following the multiple
   sub-parsers pattern in Commands.Mod: each subcommand is its own
   sub-parser with its own ArgHandler, called once per positional
   argument, so a handler accumulates arguments until it has seen enough
   to act.

   Every rope result is printed with Rope.Write, leaf by leaf, so it is
   never cut short: until Rope.Write existed this printed through
   Rope.ToString into an ArgParser.MaxStringLength buffer, which silently
   truncated any result longer than that (make 5000 x printed 4095 x's). *)

IMPORT ArgParser, Files, Out, Rope;

VAR
  parser, catParser, subParser, lenParser, fetchParser,
  cmpParser, findParser, repeatParser, insertParser, removeParser,
  rfindParser, splitParser, trimParser, trimLeftParser, trimRightParser,
  upperParser, lowerParser, capitalizeParser, uncapitalizeParser, escapedParser,
  makeParser, bigCatParser, indexCharParser, rIndexCharParser, containsParser,
  overwriteParser, headParser, tailParser, containsPatternParser,
  iterateParser, iteratorParser, linesParser, readFileParser, blitParser,
  replaceParser, replaceCharParser, countParser, countSetParser, indexSetParser, rIndexSetParser,
  nonBlankParser, rNonBlankParser, findTokenParser, translateParser, cmpNoCaseParser,
  hashParser, hashNoCaseParser, findNoCaseParser, countNoCaseParser: ArgParser.Parser;

  catCount: INTEGER; catA: Rope.Rope;
  subCount: INTEGER; subS: Rope.Rope; subStart: LONGINT;
  fetchCount: INTEGER; fetchS: Rope.Rope;
  cmpCount: INTEGER; cmpA: Rope.Rope;
  findCount: INTEGER; findS: Rope.Rope; findPattern: ArgParser.String;
  repeatCount: INTEGER; repeatS: Rope.Rope;
  insertCount: INTEGER; insertS: Rope.Rope; insertPos: LONGINT;
  removeCount: INTEGER; removeS: Rope.Rope; removePos: LONGINT;
  rfindCount: INTEGER; rfindS: Rope.Rope; rfindPattern: ArgParser.String;
  splitCount: INTEGER; splitS: Rope.Rope;
  makeCount: INTEGER; makeLen: LONGINT;
  bigCatCount: INTEGER; bigCatN1, bigCatN2: LONGINT; bigCatCh1: CHAR;
  indexCharCount: INTEGER; indexCharS: Rope.Rope; indexCharCh: CHAR;
  rIndexCharCount: INTEGER; rIndexCharS: Rope.Rope; rIndexCharCh: CHAR;
  containsCount: INTEGER; containsS: Rope.Rope; containsCh: CHAR;
  overwriteCount: INTEGER; overwriteS: Rope.Rope; overwritePos: LONGINT;
  headCount: INTEGER; headS: Rope.Rope; headLen: LONGINT;
  tailCount: INTEGER; tailS: Rope.Rope; tailLen: LONGINT;
  containsPatternCount: INTEGER; containsPatternS: Rope.Rope; containsPatternPattern: ArgParser.String;
  blitCount: INTEGER; blitS: Rope.Rope; blitSrc, blitDstStart: LONGINT; blitDst: POINTER TO ARRAY OF CHAR;
  replaceCount: INTEGER; replaceS: Rope.Rope; replacePos, replaceLen: LONGINT;
  replaceCharCount: INTEGER; replaceCharS: Rope.Rope; replaceCharPos: LONGINT;
  countCount: INTEGER; countS: Rope.Rope;
  countSetCount: INTEGER; countSetS: Rope.Rope;
  indexSetCount: INTEGER; indexSetS: Rope.Rope; indexSetSet: Rope.CharSet;
  rIndexSetCount: INTEGER; rIndexSetS: Rope.Rope; rIndexSetSet: Rope.CharSet;
  nonBlankCount: INTEGER; nonBlankS: Rope.Rope;
  rNonBlankCount: INTEGER; rNonBlankS: Rope.Rope;
  findTokenCount: INTEGER; findTokenS: Rope.Rope; findTokenSet: Rope.CharSet;
  translateCount: INTEGER; translateS: Rope.Rope; translateFrom: ArgParser.String;
  cmpNoCaseCount: INTEGER; cmpNoCaseA: Rope.Rope;
  findNoCaseCount: INTEGER; findNoCaseS: Rope.Rope; findNoCasePattern: ArgParser.String;
  countNoCaseCount: INTEGER; countNoCaseS: Rope.Rope;

PROCEDURE ParseInt(s: ARRAY OF CHAR): LONGINT;
  VAR val: LONGINT;
BEGIN
  IF ~ArgParser.StrToInt(s, val) THEN
    Out.String("Error: not an integer: "); Out.String(s); Out.Ln;
    HALT(1)
  END;
  RETURN val
END ParseInt;

PROCEDURE DoHelp*(): BOOLEAN;
BEGIN
  parser.Usage;
  RETURN FALSE
END DoHelp;

PROCEDURE TopArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Out.String("Error: unknown command: "); Out.String(arg); Out.Ln;
  parser.Usage;
  HALT(1);
  RETURN FALSE
END TopArgHandler;

(* --- cat A B --- *)

PROCEDURE CatArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF catCount = 0 THEN
    catA := Rope.FromString(arg)
  ELSIF catCount = 1 THEN
    Rope.Write(Rope.Cat(catA, Rope.FromString(arg))); Out.Ln
  END;
  INC(catCount);
  RETURN TRUE
END CatArgHandler;

(* --- sub S START LEN --- *)

PROCEDURE SubArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF subCount = 0 THEN
    subS := Rope.FromString(arg)
  ELSIF subCount = 1 THEN
    subStart := ParseInt(arg)
  ELSIF subCount = 2 THEN
    Rope.Write(Rope.Substring(subS, subStart, ParseInt(arg))); Out.Ln
  END;
  INC(subCount);
  RETURN TRUE
END SubArgHandler;

(* --- len S --- *)

PROCEDURE LenArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Out.Int(Rope.Length(Rope.FromString(arg)), 0); Out.Ln;
  RETURN TRUE
END LenArgHandler;

(* --- fetch S I --- *)

PROCEDURE FetchArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF fetchCount = 0 THEN
    fetchS := Rope.FromString(arg)
  ELSIF fetchCount = 1 THEN
    Out.Char(Rope.Fetch(fetchS, ParseInt(arg))); Out.Ln
  END;
  INC(fetchCount);
  RETURN TRUE
END FetchArgHandler;

(* --- cmp A B --- *)

PROCEDURE CmpArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF cmpCount = 0 THEN
    cmpA := Rope.FromString(arg)
  ELSIF cmpCount = 1 THEN
    Out.Int(Rope.CompareString(cmpA, arg), 0); Out.Ln
  END;
  INC(cmpCount);
  RETURN TRUE
END CmpArgHandler;

(* --- find S PATTERN FROM --- *)

PROCEDURE FindArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF findCount = 0 THEN
    findS := Rope.FromString(arg)
  ELSIF findCount = 1 THEN
    COPY(arg, findPattern)
  ELSIF findCount = 2 THEN
    Out.Int(Rope.Find(findS, findPattern, ParseInt(arg)), 0); Out.Ln
  END;
  INC(findCount);
  RETURN TRUE
END FindArgHandler;

(* --- repeat S N --- *)

PROCEDURE RepeatArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF repeatCount = 0 THEN
    repeatS := Rope.FromString(arg)
  ELSIF repeatCount = 1 THEN
    Rope.Write(Rope.Repeat(repeatS, ParseInt(arg))); Out.Ln
  END;
  INC(repeatCount);
  RETURN TRUE
END RepeatArgHandler;

(* --- insert S POS INS --- *)

PROCEDURE InsertArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF insertCount = 0 THEN
    insertS := Rope.FromString(arg)
  ELSIF insertCount = 1 THEN
    insertPos := ParseInt(arg)
  ELSIF insertCount = 2 THEN
    Rope.Write(Rope.Insert(insertS, insertPos, Rope.FromString(arg))); Out.Ln
  END;
  INC(insertCount);
  RETURN TRUE
END InsertArgHandler;

(* --- remove S POS LEN --- *)

PROCEDURE RemoveArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF removeCount = 0 THEN
    removeS := Rope.FromString(arg)
  ELSIF removeCount = 1 THEN
    removePos := ParseInt(arg)
  ELSIF removeCount = 2 THEN
    Rope.Write(Rope.Remove(removeS, removePos, ParseInt(arg))); Out.Ln
  END;
  INC(removeCount);
  RETURN TRUE
END RemoveArgHandler;

(* --- rfind S PATTERN BEFORE --- *)

PROCEDURE RFindArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF rfindCount = 0 THEN
    rfindS := Rope.FromString(arg)
  ELSIF rfindCount = 1 THEN
    COPY(arg, rfindPattern)
  ELSIF rfindCount = 2 THEN
    Out.Int(Rope.RFind(rfindS, rfindPattern, ParseInt(arg)), 0); Out.Ln
  END;
  INC(rfindCount);
  RETURN TRUE
END RFindArgHandler;

(* --- split S SEP --- *)

PROCEDURE SplitArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR arr: Rope.Pieces; i: LONGINT;
BEGIN
  IF splitCount = 0 THEN
    splitS := Rope.FromString(arg)
  ELSIF splitCount = 1 THEN
    arr := Rope.SplitArray(splitS, arg);
    FOR i := 0 TO LEN(arr^) - 1 DO Rope.Write(arr[i]); Out.Ln END
  END;
  INC(splitCount);
  RETURN TRUE
END SplitArgHandler;

(* --- trim / triml / trimr S --- *)

PROCEDURE TrimArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Write(Rope.Trim(Rope.FromString(arg))); Out.Ln;
  RETURN TRUE
END TrimArgHandler;

PROCEDURE TrimLeftArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Write(Rope.TrimLeft(Rope.FromString(arg))); Out.Ln;
  RETURN TRUE
END TrimLeftArgHandler;

PROCEDURE TrimRightArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Write(Rope.TrimRight(Rope.FromString(arg))); Out.Ln;
  RETURN TRUE
END TrimRightArgHandler;

(* --- upper / lower / capitalize / uncapitalize S --- *)

PROCEDURE UpperArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Write(Rope.UppercaseAscii(Rope.FromString(arg))); Out.Ln;
  RETURN TRUE
END UpperArgHandler;

PROCEDURE LowerArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Write(Rope.LowercaseAscii(Rope.FromString(arg))); Out.Ln;
  RETURN TRUE
END LowerArgHandler;

PROCEDURE CapitalizeArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Write(Rope.CapitalizeAscii(Rope.FromString(arg))); Out.Ln;
  RETURN TRUE
END CapitalizeArgHandler;

PROCEDURE UncapitalizeArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Write(Rope.UncapitalizeAscii(Rope.FromString(arg))); Out.Ln;
  RETURN TRUE
END UncapitalizeArgHandler;

(* --- escaped S --- *)

PROCEDURE EscapedArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Write(Rope.Escape(Rope.FromString(arg))); Out.Ln;
  RETURN TRUE
END EscapedArgHandler;

(* --- make LEN CH --- *)

PROCEDURE MakeArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF makeCount = 0 THEN
    makeLen := ParseInt(arg)
  ELSIF makeCount = 1 THEN
    Rope.Write(Rope.Make(makeLen, arg[0])); Out.Ln
  END;
  INC(makeCount);
  RETURN TRUE
END MakeArgHandler;

(* --- bigcat N1 CH1 N2 CH2 --- *)

(* Prints the length of N1 copies of CH1 concatenated with N2 copies of
   CH2, built with Repeat so that even huge N1/N2 stay cheap (Repeat's
   binary doubling shares subtrees instead of copying characters).  Lets
   the overflow guard in Rope.Mod's Cat be exercised -- and HALT(1), as
   designed, instead of silently wrapping -- without actually allocating
   anywhere near MAX(LONGINT) real characters. *)
PROCEDURE BigCatArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF bigCatCount = 0 THEN
    bigCatN1 := ParseInt(arg)
  ELSIF bigCatCount = 1 THEN
    bigCatCh1 := arg[0]
  ELSIF bigCatCount = 2 THEN
    bigCatN2 := ParseInt(arg)
  ELSIF bigCatCount = 3 THEN
    Out.Int(Rope.Length(Rope.Cat(Rope.Repeat(Rope.FromChar(bigCatCh1), bigCatN1),
                                  Rope.Repeat(Rope.FromChar(arg[0]), bigCatN2))), 0);
    Out.Ln
  END;
  INC(bigCatCount);
  RETURN TRUE
END BigCatArgHandler;

(* --- indexchar S CH FROM --- *)

PROCEDURE IndexCharArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF indexCharCount = 0 THEN
    indexCharS := Rope.FromString(arg)
  ELSIF indexCharCount = 1 THEN
    indexCharCh := arg[0]
  ELSIF indexCharCount = 2 THEN
    Out.Int(Rope.IndexChar(indexCharS, indexCharCh, ParseInt(arg)), 0); Out.Ln
  END;
  INC(indexCharCount);
  RETURN TRUE
END IndexCharArgHandler;

(* --- rindexchar S CH BEFORE --- *)

PROCEDURE RIndexCharArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF rIndexCharCount = 0 THEN
    rIndexCharS := Rope.FromString(arg)
  ELSIF rIndexCharCount = 1 THEN
    rIndexCharCh := arg[0]
  ELSIF rIndexCharCount = 2 THEN
    Out.Int(Rope.RIndexChar(rIndexCharS, rIndexCharCh, ParseInt(arg)), 0); Out.Ln
  END;
  INC(rIndexCharCount);
  RETURN TRUE
END RIndexCharArgHandler;

(* --- contains S CH FROM --- *)

PROCEDURE ContainsArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF containsCount = 0 THEN
    containsS := Rope.FromString(arg)
  ELSIF containsCount = 1 THEN
    containsCh := arg[0]
  ELSIF containsCount = 2 THEN
    IF Rope.Contains(containsS, containsCh, ParseInt(arg)) THEN
      Out.String("TRUE")
    ELSE
      Out.String("FALSE")
    END;
    Out.Ln
  END;
  INC(containsCount);
  RETURN TRUE
END ContainsArgHandler;

(* --- overwrite S POS NEW --- *)

PROCEDURE OverwriteArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF overwriteCount = 0 THEN
    overwriteS := Rope.FromString(arg)
  ELSIF overwriteCount = 1 THEN
    overwritePos := ParseInt(arg)
  ELSIF overwriteCount = 2 THEN
    Rope.Write(Rope.Overwrite(overwriteS, overwritePos, Rope.FromString(arg))); Out.Ln
  END;
  INC(overwriteCount);
  RETURN TRUE
END OverwriteArgHandler;

(* --- head S COUNT PAD --- *)

PROCEDURE HeadArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF headCount = 0 THEN
    headS := Rope.FromString(arg)
  ELSIF headCount = 1 THEN
    headLen := ParseInt(arg)
  ELSIF headCount = 2 THEN
    Rope.Write(Rope.Head(headS, headLen, arg[0])); Out.Ln
  END;
  INC(headCount);
  RETURN TRUE
END HeadArgHandler;

(* --- tail S COUNT PAD --- *)

PROCEDURE TailArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF tailCount = 0 THEN
    tailS := Rope.FromString(arg)
  ELSIF tailCount = 1 THEN
    tailLen := ParseInt(arg)
  ELSIF tailCount = 2 THEN
    Rope.Write(Rope.Tail(tailS, tailLen, arg[0])); Out.Ln
  END;
  INC(tailCount);
  RETURN TRUE
END TailArgHandler;

(* --- containspattern S PATTERN FROM --- *)

PROCEDURE ContainsPatternArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF containsPatternCount = 0 THEN
    containsPatternS := Rope.FromString(arg)
  ELSIF containsPatternCount = 1 THEN
    COPY(arg, containsPatternPattern)
  ELSIF containsPatternCount = 2 THEN
    IF Rope.ContainsPattern(containsPatternS, containsPatternPattern, ParseInt(arg)) THEN
      Out.String("TRUE")
    ELSE
      Out.String("FALSE")
    END;
    Out.Ln
  END;
  INC(containsPatternCount);
  RETURN TRUE
END ContainsPatternArgHandler;

(* --- iterate S --- *)

(* The Visitor RopeTool passes to Rope.Iterate: print the character and
   keep going -- there is no early-stop scenario to demonstrate from a
   plain "print every character" command, so this always returns TRUE. *)
PROCEDURE PrintCharVisitor(ch: CHAR): BOOLEAN;
BEGIN
  Out.Char(ch); Out.Ln;
  RETURN TRUE
END PrintCharVisitor;

PROCEDURE IterateArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Rope.Iterate(Rope.FromString(arg), PrintCharVisitor);
  RETURN TRUE
END IterateArgHandler;

(* --- iterator S --- *)

(* Same output as iterate above (one character per line), but walking
   with Rope.NewIterator's Get/Incr instead of Rope.Iterate's Visitor
   callback -- the other half of Rope.Mod's two, separate iteration
   APIs (see the module comment there), so each gets its own command
   rather than one standing in for both. *)
PROCEDURE IteratorArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR r: Rope.Rope; it: Rope.Iterator; i, len: LONGINT;
BEGIN
  r := Rope.FromString(arg);
  len := Rope.Length(r);
  it := Rope.NewIterator(r, 0);
  FOR i := 0 TO len - 1 DO
    Out.Char(it.Get()); Out.Ln;
    it.Incr
  END;
  RETURN TRUE
END IteratorArgHandler;

(* --- lines FILE --- *)

(* Prints a line's length, a space, and the line. *)
PROCEDURE PrintLine(line: Rope.Rope);
BEGIN
  Out.Int(Rope.Length(line), 0); Out.Char(" ");
  Rope.Write(line); Out.Ln
END PrintLine;

(* The one RopeTool command that reads input, demonstrating
   Rope.ReadLine (standard input, when FILE is "-") and
   Rope.ReadLineRider (anything else, opened with Files.Old): each line is
   read whole, however long, without a buffer as long as the line. *)
PROCEDURE LinesArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR f: Files.File; rd: Files.Rider; line: Rope.Rope;
BEGIN
  IF arg = "-" THEN
    WHILE Rope.ReadLine(line) DO PrintLine(line) END
  ELSE
    f := Files.Old(arg);
    IF f = NIL THEN
      Out.String('Error: cannot open "'); Out.String(arg); Out.String('"'); Out.Ln;
      HALT(1)
    END;
    Files.Set(rd, f, 0);
    WHILE Rope.ReadLineRider(rd, line) DO PrintLine(line) END;
    Files.Close(f)
  END;
  RETURN TRUE
END LinesArgHandler;

(* --- readfile FILE --- *)

(* Demonstrates Rope.ReadFile: the whole file, byte for byte.  Printed
   escaped (Rope.Escape) so that what makes a byte-exact read different
   from reading line by line -- a CR, a form feed, a 0X, whether there
   is a final line feed -- shows in the output rather than being lost to
   the terminal or to tests/run-tests.sh's trailing-white-space
   stripping. *)
PROCEDURE ReadFileArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR r: Rope.Rope;
BEGIN
  IF ~Rope.ReadFile(arg, r) THEN
    Out.String('Error: cannot read "'); Out.String(arg); Out.String('"'); Out.Ln;
    HALT(1)
  END;
  Out.Int(Rope.Length(r), 0); Out.Char(" ");
  Rope.Write(Rope.Escape(r)); Out.Ln;
  RETURN TRUE
END ReadFileArgHandler;

(* --- blit S SRCSTART DST DSTSTART LEN --- *)

(* Demonstrates Rope.Blit, arguments in its own order: copies LEN
   characters of S from SRCSTART into DST at DSTSTART, then prints DST,
   so the characters of DST that Blit left alone show too.  DST is
   copied into an array of exactly its own length (not an
   ArgParser.String, whose LEN is MaxStringLength + 1 whatever the
   argument's length), so Blit's LEN(dst) check is against DST itself. *)
PROCEDURE BlitArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR i, n: LONGINT;
BEGIN
  IF blitCount = 0 THEN
    blitS := Rope.FromString(arg)
  ELSIF blitCount = 1 THEN
    blitSrc := ParseInt(arg)
  ELSIF blitCount = 2 THEN
    n := 0;
    WHILE (n < LEN(arg)) & (arg[n] # 0X) DO INC(n) END;
    NEW(blitDst, n);
    FOR i := 0 TO n - 1 DO blitDst[i] := arg[i] END
  ELSIF blitCount = 3 THEN
    blitDstStart := ParseInt(arg)
  ELSIF blitCount = 4 THEN
    Rope.Blit(blitS, blitSrc, blitDst^, blitDstStart, ParseInt(arg));
    FOR i := 0 TO LEN(blitDst^) - 1 DO Out.Char(blitDst[i]) END;
    Out.Ln
  END;
  INC(blitCount);
  RETURN TRUE
END BlitArgHandler;

(* --- Ported back from the Ada Ropes package --- *)

(* The characters of s up to its 0X, as ASCII lower case, into t: how
   findnocase and countnocase lower their PATTERN, since FindMapped and
   CountMapped map only the rope, never the pattern. *)
PROCEDURE LowerString(s: ARRAY OF CHAR; VAR t: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) & (i < LEN(t) - 1) DO t[i] := Rope.LowerChar(s[i]); INC(i) END;
  t[i] := 0X
END LowerString;

(* --- replace S POS LEN BY --- *)

PROCEDURE ReplaceArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF replaceCount = 0 THEN
    replaceS := Rope.FromString(arg)
  ELSIF replaceCount = 1 THEN
    replacePos := ParseInt(arg)
  ELSIF replaceCount = 2 THEN
    replaceLen := ParseInt(arg)
  ELSIF replaceCount = 3 THEN
    Rope.Write(Rope.Replace(replaceS, replacePos, replaceLen, Rope.FromString(arg))); Out.Ln
  END;
  INC(replaceCount);
  RETURN TRUE
END ReplaceArgHandler;

(* --- replacechar S POS CH --- *)

(* Rope.ReplaceChar traps (HALT) for a POS outside S, as Fetch does; the
   check here reports that as an error instead of a bare trap. *)
PROCEDURE ReplaceCharArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF replaceCharCount = 0 THEN
    replaceCharS := Rope.FromString(arg)
  ELSIF replaceCharCount = 1 THEN
    replaceCharPos := ParseInt(arg)
  ELSIF replaceCharCount = 2 THEN
    IF (replaceCharPos < 0) OR (replaceCharPos >= Rope.Length(replaceCharS)) THEN
      Out.String("Error: POS out of range"); Out.Ln;
      HALT(1)
    END;
    Rope.Write(Rope.ReplaceChar(replaceCharS, replaceCharPos, arg[0])); Out.Ln
  END;
  INC(replaceCharCount);
  RETURN TRUE
END ReplaceCharArgHandler;

(* --- count S PATTERN --- *)

PROCEDURE CountArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF countCount = 0 THEN
    countS := Rope.FromString(arg)
  ELSIF countCount = 1 THEN
    Out.Int(Rope.Count(countS, arg), 0); Out.Ln
  END;
  INC(countCount);
  RETURN TRUE
END CountArgHandler;

(* --- countset S CHARS --- *)

PROCEDURE CountSetArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR set: Rope.CharSet;
BEGIN
  IF countSetCount = 0 THEN
    countSetS := Rope.FromString(arg)
  ELSIF countSetCount = 1 THEN
    Rope.MakeCharSet(arg, set);
    Out.Int(Rope.CountSet(countSetS, set), 0); Out.Ln
  END;
  INC(countSetCount);
  RETURN TRUE
END CountSetArgHandler;

(* --- indexset S CHARS FROM / rindexset S CHARS BEFORE --- *)

PROCEDURE IndexSetArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF indexSetCount = 0 THEN
    indexSetS := Rope.FromString(arg)
  ELSIF indexSetCount = 1 THEN
    Rope.MakeCharSet(arg, indexSetSet)
  ELSIF indexSetCount = 2 THEN
    Out.Int(Rope.IndexSet(indexSetS, indexSetSet, TRUE, ParseInt(arg)), 0); Out.Ln
  END;
  INC(indexSetCount);
  RETURN TRUE
END IndexSetArgHandler;

PROCEDURE RIndexSetArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF rIndexSetCount = 0 THEN
    rIndexSetS := Rope.FromString(arg)
  ELSIF rIndexSetCount = 1 THEN
    Rope.MakeCharSet(arg, rIndexSetSet)
  ELSIF rIndexSetCount = 2 THEN
    Out.Int(Rope.RIndexSet(rIndexSetS, rIndexSetSet, TRUE, ParseInt(arg)), 0); Out.Ln
  END;
  INC(rIndexSetCount);
  RETURN TRUE
END RIndexSetArgHandler;

(* --- nonblank S FROM / rnonblank S BEFORE --- *)

PROCEDURE NonBlankArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF nonBlankCount = 0 THEN
    nonBlankS := Rope.FromString(arg)
  ELSIF nonBlankCount = 1 THEN
    Out.Int(Rope.IndexNonBlank(nonBlankS, ParseInt(arg)), 0); Out.Ln
  END;
  INC(nonBlankCount);
  RETURN TRUE
END NonBlankArgHandler;

PROCEDURE RNonBlankArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF rNonBlankCount = 0 THEN
    rNonBlankS := Rope.FromString(arg)
  ELSIF rNonBlankCount = 1 THEN
    Out.Int(Rope.RIndexNonBlank(rNonBlankS, ParseInt(arg)), 0); Out.Ln
  END;
  INC(rNonBlankCount);
  RETURN TRUE
END RNonBlankArgHandler;

(* --- findtoken S CHARS FROM --- *)

(* Prints START LEN: Substring(S, START, LEN) is the token. *)
PROCEDURE FindTokenArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR start, len: LONGINT;
BEGIN
  IF findTokenCount = 0 THEN
    findTokenS := Rope.FromString(arg)
  ELSIF findTokenCount = 1 THEN
    Rope.MakeCharSet(arg, findTokenSet)
  ELSIF findTokenCount = 2 THEN
    Rope.FindToken(findTokenS, findTokenSet, TRUE, ParseInt(arg), start, len);
    Out.Int(start, 0); Out.Char(" "); Out.Int(len, 0); Out.Ln
  END;
  INC(findTokenCount);
  RETURN TRUE
END FindTokenArgHandler;

(* --- translate S FROM TO --- *)

PROCEDURE TranslateArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR m: Rope.Mapping;
BEGIN
  IF translateCount = 0 THEN
    translateS := Rope.FromString(arg)
  ELSIF translateCount = 1 THEN
    COPY(arg, translateFrom)
  ELSIF translateCount = 2 THEN
    IF ~Rope.MakeMapping(translateFrom, arg, m) THEN
      Out.String("Error: FROM and TO must be the same length, with no character repeated in FROM"); Out.Ln;
      HALT(1)
    END;
    Rope.Write(Rope.Translate(translateS, m)); Out.Ln
  END;
  INC(translateCount);
  RETURN TRUE
END TranslateArgHandler;

(* --- cmpnocase A B --- *)

PROCEDURE CmpNoCaseArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF cmpNoCaseCount = 0 THEN
    cmpNoCaseA := Rope.FromString(arg)
  ELSIF cmpNoCaseCount = 1 THEN
    Out.Int(Rope.CompareNoCase(cmpNoCaseA, Rope.FromString(arg)), 0); Out.Ln
  END;
  INC(cmpNoCaseCount);
  RETURN TRUE
END CmpNoCaseArgHandler;

(* --- hash S / hashnocase S --- *)

(* The same values GNAT's Ada.Strings.Hash and Hash_Case_Insensitive
   give, as the Ada Ropes package's rope_tool hash and hashci print. *)
PROCEDURE HashArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Out.Int(Rope.Hash(Rope.FromString(arg)), 0); Out.Ln;
  RETURN TRUE
END HashArgHandler;

PROCEDURE HashNoCaseArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  Out.Int(Rope.HashNoCase(Rope.FromString(arg)), 0); Out.Ln;
  RETURN TRUE
END HashNoCaseArgHandler;

(* --- findnocase S PATTERN FROM / countnocase S PATTERN --- *)

(* Rope.FindMapped and Rope.CountMapped with Rope.LowerChar, and PATTERN
   lowered first. *)
PROCEDURE FindNoCaseArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF findNoCaseCount = 0 THEN
    findNoCaseS := Rope.FromString(arg)
  ELSIF findNoCaseCount = 1 THEN
    LowerString(arg, findNoCasePattern)
  ELSIF findNoCaseCount = 2 THEN
    Out.Int(Rope.FindMapped(findNoCaseS, findNoCasePattern, ParseInt(arg), Rope.LowerChar), 0); Out.Ln
  END;
  INC(findNoCaseCount);
  RETURN TRUE
END FindNoCaseArgHandler;

PROCEDURE CountNoCaseArgHandler*(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR pattern: ArgParser.String;
BEGIN
  IF countNoCaseCount = 0 THEN
    countNoCaseS := Rope.FromString(arg)
  ELSIF countNoCaseCount = 1 THEN
    LowerString(arg, pattern);
    Out.Int(Rope.CountMapped(countNoCaseS, pattern, Rope.LowerChar), 0); Out.Ln
  END;
  INC(countNoCaseCount);
  RETURN TRUE
END CountNoCaseArgHandler;

BEGIN
  catCount := 0;
  replaceCount := 0; replaceCharCount := 0; countCount := 0; countSetCount := 0;
  indexSetCount := 0; rIndexSetCount := 0; nonBlankCount := 0; rNonBlankCount := 0;
  findTokenCount := 0; translateCount := 0; cmpNoCaseCount := 0; findNoCaseCount := 0; countNoCaseCount := 0;
  subCount := 0;
  fetchCount := 0;
  cmpCount := 0;
  findCount := 0;
  repeatCount := 0;
  insertCount := 0;
  removeCount := 0;
  rfindCount := 0;
  splitCount := 0;
  makeCount := 0;
  bigCatCount := 0;
  indexCharCount := 0;
  rIndexCharCount := 0;
  containsCount := 0;
  overwriteCount := 0;
  headCount := 0;
  tailCount := 0;
  containsPatternCount := 0;
  blitCount := 0;

  catParser := ArgParser.NewParser("cat A B  Print the concatenation of A and B.", CatArgHandler);
  subParser := ArgParser.NewParser("sub S START LEN  Print the substring of S from START, LEN characters.", SubArgHandler);
  lenParser := ArgParser.NewParser("len S  Print the length of S.", LenArgHandler);
  fetchParser := ArgParser.NewParser("fetch S I  Print the character of S at index I.", FetchArgHandler);
  cmpParser := ArgParser.NewParser("cmp A B  Print -1, 0 or 1: how A compares to B.", CmpArgHandler);
  findParser := ArgParser.NewParser("find S PATTERN FROM  Print the index of PATTERN in S at or after FROM, or -1.", FindArgHandler);
  repeatParser := ArgParser.NewParser("repeat S N  Print N concatenated copies of S.", RepeatArgHandler);
  insertParser := ArgParser.NewParser("insert S POS INS  Print S with INS inserted before index POS.", InsertArgHandler);
  removeParser := ArgParser.NewParser("remove S POS LEN  Print S with LEN characters removed starting at POS.", RemoveArgHandler);
  rfindParser := ArgParser.NewParser("rfind S PATTERN BEFORE  Print the index of the last PATTERN in S at or before BEFORE, or -1.", RFindArgHandler);
  splitParser := ArgParser.NewParser("split S SEP  Print each piece of S split on SEP, one per line.", SplitArgHandler);
  trimParser := ArgParser.NewParser("trim S  Print S with leading and trailing whitespace removed.", TrimArgHandler);
  trimLeftParser := ArgParser.NewParser("triml S  Print S with leading whitespace removed.", TrimLeftArgHandler);
  trimRightParser := ArgParser.NewParser("trimr S  Print S with trailing whitespace removed.", TrimRightArgHandler);
  upperParser := ArgParser.NewParser("upper S  Print S with ASCII letters uppercased.", UpperArgHandler);
  lowerParser := ArgParser.NewParser("lower S  Print S with ASCII letters lowercased.", LowerArgHandler);
  capitalizeParser := ArgParser.NewParser("capitalize S  Print S with its first character uppercased (ASCII only).", CapitalizeArgHandler);
  uncapitalizeParser := ArgParser.NewParser("uncapitalize S  Print S with its first character lowercased (ASCII only).", UncapitalizeArgHandler);
  escapedParser := ArgParser.NewParser("escaped S  Print S with special and non-printable characters escaped.", EscapedArgHandler);
  makeParser := ArgParser.NewParser("make LEN CH  Print a rope of LEN copies of CH.", MakeArgHandler);
  bigCatParser := ArgParser.NewParser("bigcat N1 CH1 N2 CH2  Print the length of N1 copies of CH1 concatenated with N2 copies of CH2.", BigCatArgHandler);
  indexCharParser := ArgParser.NewParser("indexchar S CH FROM  Print the index of CH in S at or after FROM, or -1.", IndexCharArgHandler);
  rIndexCharParser := ArgParser.NewParser("rindexchar S CH BEFORE  Print the index of CH in S at or before BEFORE, or -1.", RIndexCharArgHandler);
  containsParser := ArgParser.NewParser("contains S CH FROM  Print TRUE or FALSE: whether CH occurs in S at or after FROM.", ContainsArgHandler);
  overwriteParser := ArgParser.NewParser("overwrite S POS NEW  Print S with the characters from POS replaced by NEW.", OverwriteArgHandler);
  headParser :=
    ArgParser.NewParser("head S COUNT PAD  Print the first COUNT characters of S, padded with PAD if COUNT exceeds Length(S).", HeadArgHandler);
  tailParser :=
    ArgParser.NewParser("tail S COUNT PAD  Print the last COUNT characters of S, padded with PAD if COUNT exceeds Length(S).", TailArgHandler);
  containsPatternParser := ArgParser.NewParser(
    "containspattern S PATTERN FROM  Print TRUE or FALSE: whether PATTERN occurs in S at or after FROM.", ContainsPatternArgHandler);
  iterateParser := ArgParser.NewParser("iterate S  Print each character of S, one per line, via Rope.Iterate.", IterateArgHandler);
  iteratorParser :=
    ArgParser.NewParser("iterator S  Print each character of S, one per line, via Rope.NewIterator/Get/Incr.", IteratorArgHandler);
  linesParser := ArgParser.NewParser(
    "lines FILE  Read FILE (standard input if FILE is -) and print each line's length, a space, and the line.", LinesArgHandler);
  blitParser := ArgParser.NewParser(
    "blit S SRCSTART DST DSTSTART LEN  Print DST with LEN characters of S from SRCSTART copied into it at DSTSTART.", BlitArgHandler);
  readFileParser := ArgParser.NewParser(
    "readfile FILE  Read all of FILE, byte for byte, and print its length, a space, and its contents escaped.", ReadFileArgHandler);

  replaceParser := ArgParser.NewParser(
    "replace S POS LEN BY  Print S with the LEN characters at POS replaced by BY.", ReplaceArgHandler);
  replaceCharParser := ArgParser.NewParser(
    "replacechar S POS CH  Print S with the character at POS replaced by CH.", ReplaceCharArgHandler);
  countParser := ArgParser.NewParser(
    "count S PATTERN  Print the number of non-overlapping occurrences of PATTERN in S.", CountArgHandler);
  countSetParser := ArgParser.NewParser(
    "countset S CHARS  Print the number of characters of S that are any of CHARS.", CountSetArgHandler);
  indexSetParser := ArgParser.NewParser(
    "indexset S CHARS FROM  Print the index of the first character of S at or after FROM that is any of CHARS, or -1.",
    IndexSetArgHandler);
  rIndexSetParser := ArgParser.NewParser(
    "rindexset S CHARS BEFORE  Print the index of the last character of S at or before BEFORE that is any of CHARS, or -1.",
    RIndexSetArgHandler);
  nonBlankParser := ArgParser.NewParser(
    "nonblank S FROM  Print the index of the first non-space character of S at or after FROM, or -1.", NonBlankArgHandler);
  rNonBlankParser := ArgParser.NewParser(
    "rnonblank S BEFORE  Print the index of the last non-space character of S at or before BEFORE, or -1.", RNonBlankArgHandler);
  findTokenParser := ArgParser.NewParser(
    "findtoken S CHARS FROM  Print START LEN: the first run of characters of S at or after FROM that are any of CHARS.",
    FindTokenArgHandler);
  translateParser := ArgParser.NewParser(
    "translate S FROM TO  Print S with each character in FROM replaced by the one at the same place in TO.", TranslateArgHandler);
  cmpNoCaseParser := ArgParser.NewParser(
    "cmpnocase A B  Print -1, 0 or 1: how A compares to B, ignoring ASCII case.", CmpNoCaseArgHandler);
  hashParser := ArgParser.NewParser("hash S  Print the hash of S.", HashArgHandler);
  hashNoCaseParser := ArgParser.NewParser("hashnocase S  Print the hash of S, ignoring ASCII case.", HashNoCaseArgHandler);
  findNoCaseParser := ArgParser.NewParser(
    "findnocase S PATTERN FROM  Print the index of PATTERN in S at or after FROM, ignoring ASCII case, or -1.",
    FindNoCaseArgHandler);
  countNoCaseParser := ArgParser.NewParser(
    "countnocase S PATTERN  Print the number of non-overlapping occurrences of PATTERN in S, ignoring ASCII case.",
    CountNoCaseArgHandler);

  parser := ArgParser.NewParser("ropetool [options] command arguments...", TopArgHandler);
  parser.AddOption(ArgParser.MakeOption("h", "help", "Display help message and exit.", DoHelp));
  parser.AddCommand(ArgParser.MakeCommand("cat", catParser));
  parser.AddCommand(ArgParser.MakeCommand("sub", subParser));
  parser.AddCommand(ArgParser.MakeCommand("len", lenParser));
  parser.AddCommand(ArgParser.MakeCommand("fetch", fetchParser));
  parser.AddCommand(ArgParser.MakeCommand("cmp", cmpParser));
  parser.AddCommand(ArgParser.MakeCommand("find", findParser));
  parser.AddCommand(ArgParser.MakeCommand("repeat", repeatParser));
  parser.AddCommand(ArgParser.MakeCommand("insert", insertParser));
  parser.AddCommand(ArgParser.MakeCommand("remove", removeParser));
  parser.AddCommand(ArgParser.MakeCommand("rfind", rfindParser));
  parser.AddCommand(ArgParser.MakeCommand("split", splitParser));
  parser.AddCommand(ArgParser.MakeCommand("trim", trimParser));
  parser.AddCommand(ArgParser.MakeCommand("triml", trimLeftParser));
  parser.AddCommand(ArgParser.MakeCommand("trimr", trimRightParser));
  parser.AddCommand(ArgParser.MakeCommand("upper", upperParser));
  parser.AddCommand(ArgParser.MakeCommand("lower", lowerParser));
  parser.AddCommand(ArgParser.MakeCommand("capitalize", capitalizeParser));
  parser.AddCommand(ArgParser.MakeCommand("uncapitalize", uncapitalizeParser));
  parser.AddCommand(ArgParser.MakeCommand("escaped", escapedParser));
  parser.AddCommand(ArgParser.MakeCommand("make", makeParser));
  parser.AddCommand(ArgParser.MakeCommand("bigcat", bigCatParser));
  parser.AddCommand(ArgParser.MakeCommand("indexchar", indexCharParser));
  parser.AddCommand(ArgParser.MakeCommand("rindexchar", rIndexCharParser));
  parser.AddCommand(ArgParser.MakeCommand("contains", containsParser));
  parser.AddCommand(ArgParser.MakeCommand("overwrite", overwriteParser));
  parser.AddCommand(ArgParser.MakeCommand("head", headParser));
  parser.AddCommand(ArgParser.MakeCommand("tail", tailParser));
  parser.AddCommand(ArgParser.MakeCommand("containspattern", containsPatternParser));
  parser.AddCommand(ArgParser.MakeCommand("iterate", iterateParser));
  parser.AddCommand(ArgParser.MakeCommand("iterator", iteratorParser));
  parser.AddCommand(ArgParser.MakeCommand("lines", linesParser));
  parser.AddCommand(ArgParser.MakeCommand("readfile", readFileParser));
  parser.AddCommand(ArgParser.MakeCommand("blit", blitParser));
  parser.AddCommand(ArgParser.MakeCommand("replace", replaceParser));
  parser.AddCommand(ArgParser.MakeCommand("replacechar", replaceCharParser));
  parser.AddCommand(ArgParser.MakeCommand("count", countParser));
  parser.AddCommand(ArgParser.MakeCommand("countset", countSetParser));
  parser.AddCommand(ArgParser.MakeCommand("indexset", indexSetParser));
  parser.AddCommand(ArgParser.MakeCommand("rindexset", rIndexSetParser));
  parser.AddCommand(ArgParser.MakeCommand("nonblank", nonBlankParser));
  parser.AddCommand(ArgParser.MakeCommand("rnonblank", rNonBlankParser));
  parser.AddCommand(ArgParser.MakeCommand("findtoken", findTokenParser));
  parser.AddCommand(ArgParser.MakeCommand("translate", translateParser));
  parser.AddCommand(ArgParser.MakeCommand("cmpnocase", cmpNoCaseParser));
  parser.AddCommand(ArgParser.MakeCommand("hash", hashParser));
  parser.AddCommand(ArgParser.MakeCommand("hashnocase", hashNoCaseParser));
  parser.AddCommand(ArgParser.MakeCommand("findnocase", findNoCaseParser));
  parser.AddCommand(ArgParser.MakeCommand("countnocase", countNoCaseParser));

  parser.ParseArguments(1)
END RopeTool.
