#!/usr/bin/env python3
"""check_do_syntax.py - catch Tcl traps in the .do scripts.

Questa's `echo` runs its argument through Tcl, so a literal [PASS] in a
message is treated as a COMMAND SUBSTITUTION and produces

    ** Error: invalid command name "PASS"

after the test has already run and passed - confusing, because the
simulation itself was fine. Square brackets in message strings must be
escaped as \\[ and \\].

Also checks brace/bracket balance, which is the other way a .do file
fails late and unhelpfully.

Run:  python3 Simulation/questa/check_do_syntax.py
Exit: 0 clean, 1 if something would break.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def check_brackets_in_strings(path):
    problems = []
    for i, line in enumerate(path.read_text(encoding="utf-8",
                                            errors="replace").split("\n"), 1):
        if line.strip().startswith("#"):
            continue
        for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', line):
            body = m.group(1)
            for mm in re.finditer(r"\[", body):
                # Count the backslashes immediately before the bracket.
                # An ODD count means it is escaped; EVEN (including zero)
                # means Tcl will treat it as a command substitution.
                #
                # This distinction matters: writing \\[ instead of \[ looks
                # escaped but is not - the \\ collapses to one literal
                # backslash and the bracket is still live.
                j = mm.start() - 1
                n = 0
                while j >= 0 and body[j] == "\\":
                    n += 1
                    j -= 1
                if n % 2 == 0:
                    frag = body[max(0, mm.start() - 8):mm.start() + 20]
                    why = ("not escaped" if n == 0
                           else f"{n} backslashes - an even count does NOT escape")
                    problems.append(
                        (i, f'"[" in a string is {why}: ...{frag}...  '
                            f"-> Tcl runs it as a command; use exactly one \\[")
                    )
    return problems


def check_balance(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    stripped = "\n".join(l for l in text.split("\n")
                         if not l.strip().startswith("#"))
    problems = []
    for open_c, close_c, name in (("{", "}", "brace"), ("[", "]", "bracket")):
        n_open = stripped.count(open_c)
        n_close = stripped.count(close_c)
        if n_open != n_close:
            problems.append(
                (0, f"unbalanced {name}s: {n_open} '{open_c}' vs "
                    f"{n_close} '{close_c}'")
            )
    return problems


def main():
    files = sorted(HERE.rglob("*.do"))
    if not files:
        print("no .do files found next to this script")
        return 1

    rc = 0
    for f in files:
        problems = check_brackets_in_strings(f) + check_balance(f)
        rel = f.relative_to(HERE)
        if problems:
            rc = 1
            print(f"### {rel}  -- WOULD FAIL IN QUESTA")
            for ln, msg in sorted(problems):
                where = f"line {ln}" if ln else "file"
                print(f"    {where}: {msg}")
        else:
            print(f"### {rel}: OK")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
