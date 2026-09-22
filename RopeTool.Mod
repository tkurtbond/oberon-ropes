MODULE RopeTool;

(* Command-line demo of Rope.Mod: each subcommand builds one or two ropes
   from its string arguments with Rope.FromString and prints the result of
   one Rope operation.  Built on ArgParser, following the multiple
   sub-parsers pattern in Commands.Mod: each subcommand is its own
   sub-parser with its own ArgHandler, called once per positional
   argument, so a handler accumulates arguments until it has seen enough
   to act. *)

IMPORT ArgParser, Out, Rope;

VAR
  parser, catParser, subParser, lenParser, fetchParser,
  cmpParser, findParser, repeatParser, insertParser: ArgParser.Parser;

  catCount: INTEGER; catA: Rope.Rope;
  subCount: INTEGER; subS: Rope.Rope; subStart: LONGINT;
  fetchCount: INTEGER; fetchS: Rope.Rope;
  cmpCount: INTEGER; cmpA: Rope.Rope;
  findCount: INTEGER; findS: Rope.Rope; findPattern: ArgParser.String;
  repeatCount: INTEGER; repeatS: Rope.Rope;
  insertCount: INTEGER; insertS: Rope.Rope; insertPos: LONGINT;

PROCEDURE PrintRope(r: Rope.Rope);
  VAR buf: ARRAY ArgParser.MaxStringLength + 1 OF CHAR;
BEGIN
  Rope.ToString(r, buf);
  Out.String(buf)
END PrintRope;

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
    PrintRope(Rope.Cat(catA, Rope.FromString(arg))); Out.Ln
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
    PrintRope(Rope.Substring(subS, subStart, ParseInt(arg))); Out.Ln
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
    PrintRope(Rope.Repeat(repeatS, ParseInt(arg))); Out.Ln
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
    PrintRope(Rope.Insert(insertS, insertPos, Rope.FromString(arg))); Out.Ln
  END;
  INC(insertCount);
  RETURN TRUE
END InsertArgHandler;

BEGIN
  catCount := 0;
  subCount := 0;
  fetchCount := 0;
  cmpCount := 0;
  findCount := 0;
  repeatCount := 0;
  insertCount := 0;

  catParser := ArgParser.NewParser("cat A B  Print the concatenation of A and B.", CatArgHandler);
  subParser := ArgParser.NewParser("sub S START LEN  Print the substring of S from START, LEN characters.", SubArgHandler);
  lenParser := ArgParser.NewParser("len S  Print the length of S.", LenArgHandler);
  fetchParser := ArgParser.NewParser("fetch S I  Print the character of S at index I.", FetchArgHandler);
  cmpParser := ArgParser.NewParser("cmp A B  Print -1, 0 or 1: how A compares to B.", CmpArgHandler);
  findParser := ArgParser.NewParser("find S PATTERN FROM  Print the index of PATTERN in S at or after FROM, or -1.", FindArgHandler);
  repeatParser := ArgParser.NewParser("repeat S N  Print N concatenated copies of S.", RepeatArgHandler);
  insertParser := ArgParser.NewParser("insert S POS INS  Print S with INS inserted before index POS.", InsertArgHandler);

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

  parser.ParseArguments(1)
END RopeTool.
