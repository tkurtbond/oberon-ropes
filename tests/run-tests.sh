#!/bin/bash
# Run the fixtures in this directory against the example programs and
# report how many passed.  With -v, also announce each test and its
# outcome as it goes.  The programs are run from BINDIR, relative to the
# directory above (default: that directory itself), so a build made
# elsewhere, like poc's in poc-build, can be tested too.
#
# A fixture is tests/NAME.test, with these lines, in this order:
#
#   program NAME     the example program to run, in the directory above
#   arg VALUE        one command line argument; repeat for each argument
#                    (a bare "arg" is an empty argument)
#   status N         the expected exit status
#   output           everything after this line is the expected output
#
# Lines starting with # before "output" are comments.  Trailing white
# space is ignored when comparing output, and so are the "Terminated by
# Halt(N)." lines that voc's runtime prints after a HALT (poc's does not).

verbose=0
[ "$1" = -v ] && verbose=1

bindir=${BINDIR:-.}

cd "$(dirname "$0")/.." || exit 2

ok=0
failed=0
failures=()

strip () { sed -e 's/[[:space:]]*$//' -e '/^Terminated by Halt(.*)\.$/d'; }

for fixture in tests/*.test; do
  name=$(basename "$fixture" .test)
  program=
  status=
  args=()
  while IFS= read -r line; do
    case $line in
      '#'*)      ;;
      'program '*) program=${line#program } ;;
      arg)       args+=("") ;;
      'arg '*)   args+=("${line#arg }") ;;
      'status '*)  status=${line#status } ;;
      output)    break ;;
    esac
  done < "$fixture"

  expected=$(sed '1,/^output$/d' "$fixture" | strip)
  actual=$("$bindir/$program" "${args[@]}" 2>&1)
  got=$?
  actual=$(printf '%s\n' "$actual" | strip)

  if [ "$got" = "$status" ] && [ "$actual" = "$expected" ]; then
    ok=$((ok + 1))
    [ "$verbose" -eq 1 ] && echo "ok: $name"
  else
    failed=$((failed + 1))
    failures+=("$name")
    echo "FAILED: $name  ($program ${args[*]})"
    [ "$got" = "$status" ] || echo "  exit status: expected $status, got $got"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/  /'
  fi
done

echo
echo "$ok ok, $failed failed"
[ "$failed" -eq 0 ]
