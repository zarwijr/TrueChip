# Questa simulation scripts

Waveform scripts for capturing evidence screenshots. Everything Questa
generates (the `work` library, `transcript`, `*.wlf`) stays inside this
folder, so `RTL/` and `Simulation/` are never polluted.

## Three ways to run

### 1. One test at a time (start here)

```
cd Simulation/questa
vsim -c
```
then at the `Questa>` prompt:
```tcl
do run_one.do tb_aes128
do run_one.do ro_puf_tb
do run_one.do secure_asic_top_tb
```

Each one compiles, opens the matching grouped waveform, runs that single
testbench, prints its `[PASS]`/`[FAIL]` lines, and **stops without closing
anything**. Take the screenshot before running the next test.

### 2. Full regression

```
cd Simulation/questa
vsim -c
```
```tcl
do regression.do
```

Runs all eight, prints a PASS/FAIL table, and **stays open** so you can
read it. The summary is also written to two files, so it survives even if
the window scrolls:

- `regression_summary.txt` - just the table
- `regression.log` - full output of every test

For CI or a scripted build, ask for batch mode explicitly and it will
exit with a proper status code:

```
vsim -c -do "set TC_BATCH 1; do regression.do"
```

> `Simulation/run_regression.sh` does the same job but drives **Icarus
> Verilog**, not Questa. On a machine with only Questa it stops with
> `iverilog: command not found`. That is expected - use `regression.do`.

### 3. Waveforms for screenshots

Run these one at a time:

Start Questa **from this directory** so the relative paths resolve:

```
cd Simulation/questa
vsim -gui
```

then in the transcript pane:

```tcl
do unit/aes128.do
```

Or straight from a shell:

```
cd Simulation/questa
vsim -gui -do unit/aes128.do
```

Each script compiles, loads, sets up a grouped waveform, runs to
completion, and then **stops without closing**. The wave window stays on
screen so you can take the screenshot. Nothing else is needed.

## The scripts

| Script | Level | Evidence value |
|---|---|---|
| `unit/aes128.do` | unit | **HIGH** - crypto core vs golden vectors |
| `unit/uart.do` | unit | MEDIUM - serial framing + CDC synchroniser |
| `unit/uart_echo.do` | unit/integration | MEDIUM - end-to-end UART echo |
| `unit/cmd_parser.do` | unit | **HIGH** - CRC accept/reject boundary |
| `unit/ro_puf.do` | unit | **HIGHEST** - regression for the v7.1 P0 bug |
| `integration/auth_fsm.do` | integration | **HIGH** - replay/rate-limit/lockout policy |
| `top/secure_asic_top.do` | top (ASIC) | **HIGHEST** - the module hardened to GDS |
| `top/secure_soc_top.do` | top (FPGA) | **HIGHEST** - full PUF -> KDF -> UART chain |
| `regression.do` | — | all eight, PASS/FAIL table, no waveform |
| `run_one.do` | — | one-command dispatcher with waveform |

`auth_fsm` sits at integration level rather than unit because it
coordinates three blocks at once: the AES core, the UART transmitter and
the nonce history.

## Suggested screenshots for the report

Four pictures carry most of the weight:

1. **`unit/ro_puf.do`** — zoom to where `ro_enable` falls at the end of a
   measurement window. `cnt_r` must **hold** its value. Before the v7.2
   fix it dropped to zero right there, which is what made `puf_id` come
   out as `128'd0` on every board. Put this next to the pre-fix `[FAIL]`
   transcript and it tells the whole debugging story in one image.

2. **`top/secure_asic_top.do`** — one full CHALLENGE exchange on
   `uart_rx_i` / `uart_tx_o`. This is the exact module that went to GDS.

3. **`top/secure_soc_top.do`** — the PUF phase, showing `puf_id` landing
   non-zero and `diversified_key` being derived from it.

4. **`integration/auth_fsm.do`** — a used nonce replayed and answered
   with status `0x03` instead of a ciphertext.

Include the transcript pane in every screenshot: the `[PASS]` lines are
half the evidence.

## Runtime warning

`top/secure_asic_top.do` waits out the real 500,000-cycle cooldown twice,
so it simulates about 20 ms and takes a few minutes of wall time. That is
expected — let it finish.

## Two vsim flags that matter

Every script uses them, and they are the usual reason a waveform looks
broken if you write your own:

- `-voptargs=+acc` keeps internal signals visible. Without it Questa
  optimises them away and most of the wave window is empty.
- `-onfinish stop` stops at `$finish` instead of closing the simulator.
  Without it vsim exits the moment the test ends and the wave window
  disappears before you can capture it.

## Housekeeping

`work/`, `transcript` and `*.wlf` are build artefacts. Safe to delete;
they are regenerated on the next run.

## If a script errors on a signal path

Signal names were verified against the RTL, but if you edit the design
and a path goes stale, Questa will say `no such object`. Find the real
name with:

```tcl
find signals /secure_asic_top_tb/dut/*
```

then fix the `add wave` line.
