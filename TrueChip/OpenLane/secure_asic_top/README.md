# OpenLane / SKY130 hardening target: `secure_asic_top` (TrueChip v7.2)

This directory is the **digital ASIC layout target** for TrueChip v7. It is
separate from the FPGA top `secure_soc_top`, because the FPGA `ro_puf.v` uses
technology/placement-dependent ring oscillators and must not be sent as ordinary
RTL through a conventional synchronous digital SKY130 flow.

## What is included

- UART RX/TX at 115200 baud when `clk=50 MHz` and `CLKS_PER_BIT=434`.
- Protocol V2 request parser with CRC16-CCITT.
- 8-entry command FIFO.
- AES-128 boot key diversification and challenge/response.
- Replay history, rate limiting and lockout logic.
- A fixed `LAYOUT_DEVICE_SEED` **only as a layout stand-in** for a future
  hardened PUF/OTP macro. It is not unclonable and must not be presented as a
  production hardware root of trust.

## Why the RO-PUF is excluded from this first GDS

An RO-PUF is inherently physical: its entropy comes from device/process and
placement/routing variation. A generic RTL synthesis flow can optimize away
combinational oscillator loops or make timing analysis meaningless. For an ASIC
version, harden/characterize the PUF separately and integrate it as a macro with
physical/timing views (at minimum LEF + GDS; ideally timing/netlist views too).

Therefore the competition artifact from this folder should be named something
like **"TrueChip digital AES/UART security-core layout on SKY130"**, while the
Cyclone-V RO-PUF remains the FPGA proof-of-concept until a dedicated ASIC PUF
macro exists.

## Before every run

From this directory:

```bash
python3 sync_rtl.py
```

This prevents the OpenLane copy of the RTL from drifting from `../../RTL/`.
The ASIC `src/uart_rx.v` is intentionally excluded because it uses the
technology-neutral `async_reg` attribute, while the FPGA copy uses Quartus's
`altera_attribute`; `sync_rtl.py` preserves that deliberate exception.

## OpenLane 2

Typical invocation from a shell where OpenLane/PDK are installed:

```bash
openlane config.json
```

If your installation requires explicit PDK selection, use `--pdk sky130A`.
The config targets `sky130A` and the default high-density standard-cell library
`sky130_fd_sc_hd` at an initial 20 ns clock period (50 MHz).

## Classic OpenLane

Classic OpenLane also accepts a design directory containing `config.json`:

```bash
./flow.tcl -design /absolute/path/to/TrueChip_v7_submission_ready/OpenLane/secure_asic_top \
  -tag truechip_v7 -overwrite
```

Exact CLI syntax can vary with the installed OpenLane revision; use the command
style of your installation if it differs, but keep the design/config contents.

## First-run policy

Do not tighten area or clock aggressively before obtaining one clean baseline.
Start with `FP_CORE_UTIL=35` and 20 ns. After a complete run:

1. Check synthesis for unintended latches, combinational loops, black boxes and
   very large muxes.
2. Check setup **and hold** timing after route, not only synthesis timing.
3. Require routing/antenna/DRC/LVS signoff summaries to be clean or explicitly
   explain every remaining violation.
4. Only then reduce die area/core utilization target or clock period.

## Files/logs to send back for review

Zip the whole newest `runs/<RUN_TAG>/` if convenient. At minimum include:

- top-level `openlane.log` and `warnings.log` (Classic), or the OpenLane 2 run
  step logs/metrics;
- resolved/final config and OpenLane/PDK version metadata;
- Yosys synthesis statistics and warnings;
- floorplan/placement/CTS/routing reports;
- post-route STA reports for max/setup and min/hold corners;
- DRC summary and detailed DRC report if non-zero;
- Netgen LVS log/report;
- final GDS, DEF, LEF, gate-level netlist, SPEF/SDF if generated;
- one or more screenshots of the final layout.

Do **not** claim "DRC clean", "LVS clean" or "timing met" in the report until
those exact logs are present and reviewed.

## Evidence snapshot in this candidate

`runs/run_1/` contains the historical run metadata and curated reports, but
does not contain `results/`. The local scorecard therefore remains blocked on
CVC/ERC and warns about antenna, slew, fanout and missing final layout views.
Run the flow again with the current `config.json`, copy the complete newest
`runs/<tag>/results/` directory, then rerun `check_signoff.py` before replacing
the status in the competition report.

## Next physical-security step

The future ASIC PUF should be a separately hardened/characterized macro, then
integrated into a new top that replaces `LAYOUT_DEVICE_SEED`. The integration
package should include LEF/GDS plus appropriate black-box/netlist/timing views.
A stable PUF ID also needs measured environmental/restart reliability and a
proper stabilization/error-correction strategy; FPGA majority voting alone is
not a full fuzzy extractor.
