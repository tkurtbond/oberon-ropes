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
  iterateParser, iteratorParser, linesParser, readFileParser: ArgParser.Parser;

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
    Out.Int(Rope.Compare(cmpA, Rope.FromString(arg)), 0); Out.Ln
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
  Rope.Write(Rope.Escaped(Rope.FromString(arg))); Out.Ln;
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
   escaped (Rope.Escaped) so that what makes a byte-exact read different
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
  Rope.Write(Rope.Escaped(r)); Out.Ln;
  RETURN TRUE
END ReadFileArgHandler;

BEGIN
  catCount := 0;
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
  readFileParser := ArgParser.NewParser(
    "readfile FILE  Read all of FILE, byte for byte, and print its length, a space, and its contents escaped.", ReadFileArgHandler);

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

  parser.ParseArguments(1)
END RopeTool.
