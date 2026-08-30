# TrueChip v7.2 validation note - 30/08/2026

This note separates evidence that is present in the candidate package from
checks that still require the user's Quartus/OpenLane installation and FPGA
board. It must not be read as a replacement for the final competition report.

## 1. Evidence present in the candidate

### ASIC digital flow - `OpenLane/secure_asic_top/runs/run_5`

The scorecard was rerun against the included `metrics.csv` and signoff
reports. It reports:

| Check | Result in `run_5` | Interpretation |
|---|---:|---|
| Flow status | `flow completed` | Submission run (threshold 250) |
| Detailed-route DRC | 0 | Pass in the included report |
| Magic DRC | 0 | Pass in the included report |
| KLayout DRC | 0 | Pass in the included report |
| LVS | 0 errors | Pass in the included report |
| Signoff STA | setup +1.50 ns; hold +0.09 ns | Positive across four corner logs |
| CVC/ERC | `-1` | **WARN: tool crashed before checking** - see below |
| Antenna | 29 pin / 29 net, worst ratio 2.09 | Warning; ladder closed, 250 chosen |
| Max slew | 621 | Warning; inspect diode-induced load |
| Max fanout | 726 | Warning; separate data and clock-tree entries |
| Final views | `results/` absent from the *uploaded* ZIP | Present on the build machine; MUST be included in the submission ZIP |

The `-27.02 ns` value in `metrics.csv` is a pre-placement estimate and must
not be quoted as the final timing result. Use the signoff STA reports instead.

**CVC/ERC reclassified.** `cvc_total_errors = -1` is produced both by a tool
that crashed and by a tool that found real violations, so the metric alone
cannot distinguish them. Reading the log shows CVC aborted while binding
devices to models (`Resistance error: missing parameter: l in l/w*48`) and
never reached the checking stage - identical in `run_5` and `run_6`, so it is
independent of the antenna configuration. This is a PDK/tool model-resolution
failure, not a confirmed design error. Magic DRC, KLayout DRC and Netgen LVS
are three independent checks that all pass. Full wording in
`SIGNOFF_DISCLOSURE_v7.2.md` section 3.

### Antenna ladder - closed

| Threshold | Antenna (worst ratio) | Diodes | Slew | Fanout (data) | Setup |
|---|---|---|---|---|---|
| 90 (`run_4`) | 9 / 9 | 22,826 | 687 | 2,151 (2,026) | +0.46 ns |
| **250 (`run_5`)** | **29 / 29 (2.09)** | **6,654** | **621** | **726 (604)** | **+1.50 ns** |
| 200 (`run_6`) | 27 / 27 (2.93) | 8,786 | 589 | 882 (757) | +1.36 ns |

`run_6` bought two fewer antenna violations at the cost of 2,132 extra diodes,
a worse worst-case ratio, higher data fanout and less setup margin. The ladder
is closed and `config.json` is pinned at 250 so it reproduces `run_5`.

### Layout RTL sync - `uart_rx.v` is forked, and verified

`uart_rx.v` is deliberately NOT copied by `sync_rtl.py`: the CDC synchroniser
needs `altera_attribute` for Quartus and `async_reg` for Yosys, and copying
either way would drop the marker on the other technology.

A fork is a silent-divergence hazard, so it is checked rather than trusted.
`sync_rtl.py` now strips attributes, comments and declaration formatting from
both copies and compares the remaining logic, failing with a non-zero exit
code if they differ. Verified 30/08/2026:

- attribute-stripped logic is identical (the only textual difference is
  `reg rx_d1; reg rx_d2;` versus `reg rx_d1, rx_d2;`);
- Yosys synthesis of both copies gives identical statistics - 300 cells with
  an identical cell-type histogram;
- therefore `run_5` and `run_6` hardened the correct logic, and no re-run is
  required for this difference;
- the check was mutation-tested: inverting one assignment in the FPGA copy
  makes `sync_rtl.py` fail as intended.

### FPGA Quartus evidence included in the package

The included output reports were produced by Quartus Prime 25.1std.0, Lite
Edition, for Cyclone V `5CSXFC6D6F31C6`:

- fitter status: Successful;
- ALM: 8,718 / 41,910 (21%);
- registers: 14,047;
- pins: 49 / 499 (10%);
- `CLOCK_50` setup slack: +7.986 ns;
- `CLOCK_50` hold slack: +0.298 ns.

These are read from the included reports. Quartus must still be recompiled
after the final v7.2 RTL/configuration is frozen.

### RTL and software

- The source contains AES, UART, parser, authentication and RO-PUF testbenches.
- The Python sources pass the syntax check available in this review workspace.
- The RO-PUF testbench explicitly catches the v7.1 all-zero counter-clear bug,
  checks non-degenerate output, zero-padding and repeatability in simulation.

## 2. Checks not run in this review workspace

The 30/08/2026 review workspace had Icarus Verilog 12.0, Verilator 5.020 and
Yosys 0.33, and re-ran the following against this exact package:

- `bash Simulation/run_regression.sh` -> **8 passed, 0 failed** (exit 0);
- `verilator --lint-only -Wall` on the eight OpenLane sources -> **0 error,
  0 warning**;
- `check_signoff.py` on both `run_5` and `run_6` -> **SUBMITTABLE WITH
  DISCLOSURE** (5 warnings each), numbers matching the tables above exactly;
- Yosys equivalence of the two `uart_rx.v` copies;
- a full-tree scan for corrupted files -> none found.

It still does **not** claim a Quartus compile, a new OpenLane run, KLayout/Magic
execution, or any board UART/PUF result - those need the user's toolchain and
hardware.

## 3. Required closure before submission

1. Run `bash Simulation/run_regression.sh`; preserve the complete output.
2. Recompile `Quartus/TrueChip.qpf` after v7.2; review all warnings, not only
   the error count.
3. OpenLane: **done** - `run_5` is the submission run; no further run needed
   unless the RTL changes.
4. `check_signoff.py runs/run_5`: **done** - SUBMITTABLE WITH DISCLOSURE.
5. If KLayout was skipped, run `./OpenLane/secure_asic_top/run_klayout_drc.sh
   runs/<newest_run>` from the appropriate design directory.
6. Include the complete `runs/<newest_run>/results/` directory, especially GDS,
   DEF, LEF, final netlist and generated timing/parasitic views.
7. Load the new bitstream, record `puf_id` on the board, re-provision the
   database, then run `test/test_uart_challenge.py` and save its output.
8. Characterize the RO-PUF: repeated power cycles on one board and, ideally,
   at least two boards/chips; report reliability, bias/uniformity and
   inter-device Hamming distance.
9. Add layout, waveform, SignalTap, board and video evidence before exporting
   the final PDF.

## 4. Claims that remain deliberately bounded

- The FPGA RO-PUF is a proof-of-concept until measured on real boards.
- The SKY130 artifact is the digital AES/UART security-core layout; it does not
  contain a production ASIC RO-PUF macro.
- Majority voting is not a complete fuzzy extractor/ECC key reconstruction
  scheme.
- The current AES core is functionally verified, not proven side-channel
  resistant.
- The sub-USD-1/chip statement is a future commercial target, not a measured
  result from this layout.
