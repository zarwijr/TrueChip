#!/usr/bin/env python3
"""check_tb_portability.py - catch Icarus-only testbench constructs.

Icarus Verilog is permissive; Questa is not. Three differences bit this
project in a row, each costing a round trip:

  1. fork ... join_none      - SystemVerilog, rejected in a .v file
  2. $fatal                  - SystemVerilog severity task
  3. forward references      - using a module-level signal above its
                               declaration (Questa vlog-2730)

This script checks (3), which is the one a human will not spot by eye.
(1) and (2) are simple greps and are also checked below.

Run:  python3 Simulation/check_tb_portability.py Simulation/*.v
Exit: 0 clean, 1 if anything would fail in Questa.

Only MODULE-scope declarations and uses are considered - variables
declared inside a task or function have their own scope and are fine.

Icarus cho phep tham chieu tien; Questa tu choi (vlog-2730). Chi xet
khai bao va su dung NGOAI task/function - bien cuc bo trong task co
pham vi rieng nen khong lien quan.
"""
import re, sys

DECL = re.compile(r'^\s*(reg|wire|integer|real|event)\b'
                  r'(?:\s*(?:signed|unsigned))?(?:\s*\[[^\]]*\])?\s+(.+?);\s*$')
IDENT = re.compile(r'\b([a-zA-Z_]\w*)\b')
KW = set('''module endmodule begin end if else for while repeat forever case endcase default
reg wire integer real localparam parameter genvar event initial always assign task endtask
function endfunction posedge negedge or and not xor nand nor xnor buf input output inout
generate endgenerate signed unsigned defparam disable fork join join_any join_none'''.split())

def scope_mask(lines):
    """True neu dong nam trong task/function."""
    inside, depth, mask = False, 0, []
    for l in lines:
        c = re.sub(r'//.*', '', l)
        starting = re.search(r'^\s*(task|function)\b', c)
        if starting: inside, depth = True, depth + 1
        mask.append(inside)
        if re.search(r'^\s*end(task|function)\b', c):
            depth -= 1
            if depth <= 0: inside, depth = False, 0
    return mask

def check(path):
    lines = open(path, encoding='utf-8', errors='replace').read().split('\n')
    mask = scope_mask(lines)
    decl = {}
    for i, l in enumerate(lines, 1):
        if mask[i-1]: continue                      # bo qua trong task
        c = re.sub(r'//.*', '', l)
        m = DECL.match(c)
        if not m: continue
        names = re.sub(r'=\s*[^,]+', '', m.group(2))
        names = re.sub(r'\[[^\]]*\]', '', names)
        for n in [x.strip() for x in names.split(',')]:
            n = n.split()[0] if n.split() else ''
            if n and n not in KW and n not in decl:
                decl[n] = i
    bad, seen = [], set()
    for i, l in enumerate(lines, 1):
        if mask[i-1]: continue
        c = re.sub(r'//.*', '', l)
        if DECL.match(c): continue
        for tok in IDENT.findall(c):
            if tok in decl and i < decl[tok] and tok not in seen:
                seen.add(tok); bad.append((i, tok, decl[tok]))
    return bad

def grep_sv(path):
    """SystemVerilog constructs that a .v file must not use."""
    hits = []
    for i, l in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        c = re.sub(r"//.*", "", l)
        if re.search(r"\bjoin_none\b|\bjoin_any\b", c):
            hits.append((i, "fork...join_none/join_any is SystemVerilog"))
        if re.search(r"\$fatal\b|\$error\b|\$warning\b|\$info\b", c):
            hits.append((i, "$fatal/$error/$warning/$info are SystemVerilog"))
    return hits


def check_overflow(path):
    """Delay literals above 2^31-1 overflow a 32-bit signed integer."""
    hits = []
    for i, l in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        for m in re.finditer(r"#(\d[\d_]*)", re.sub(r"//.*", "", l)):
            v = int(m.group(1).replace("_", ""))
            if v > 2**31 - 1:
                hits.append((i, f"delay #{m.group(1)} overflows 32-bit signed"))
    return hits


rc = 0
for f in sorted(sys.argv[1:]):
    problems = []
    for ln, tok, dl in check(f):
        problems.append((ln, f"'{tok}' used here but declared on line {dl}"))
    # .sv files are compiled with -sv, so SystemVerilog is legal there.
    if not f.endswith(".sv"):
        problems += grep_sv(f)
    problems += check_overflow(f)

    if problems:
        rc = 1
        print(f"### {f}  -- WOULD FAIL IN QUESTA")
        for ln, msg in sorted(problems):
            print(f"    line {ln}: {msg}")
    else:
        print(f"### {f}: OK")

sys.exit(rc)
