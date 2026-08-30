# TrueChip v7.2 - finalization status

## Decision

The design is technically promising but is **not ready for final submission**
from the evidence currently packaged. The remaining items are evidence and
signoff closure, not a request to redesign the AES/UART architecture.

## What is already strong

| Area | Current evidence |
|---|---|
| Competition fit | Hardware AES-128 authentication, UART, FPGA RO-PUF path and digital SKY130 layout path |
| ASIC flow | Historical `run_1` completed; detailed-route DRC, Magic DRC, KLayout DRC and LVS report zero errors |
| ASIC timing | Signoff reports show positive setup and hold slack at four corners |
| FPGA | Included Quartus reports show successful fit and positive `CLOCK_50` setup/hold slack |
| Security logic | CRC request framing, AES challenge-response, replay history, rate limiting and lockout are implemented |
| RO-PUF correction | v7.2 separates oscillator gating from counter clearing and includes a regression for the v7.1 all-zero bug |

## Current blockers/warnings

| Priority | Item | Required action |
|---|---|---|
| P0 | CVC/ERC = -1 in `run_1` | Run again with current `DECAP_CELL`; record whether CVC completes. If the PDK model still fails, disclose the exact error. |
| P0 | `runs/run_1/results/` absent | Include the newest complete results directory: GDS/DEF/LEF/netlist/SPEF/SDF as generated. |
| P1 | 29 antenna, 621 slew, 726 fanout | Re-run current antenna configuration and tune one variable at a time; report residuals honestly. |
| P1 | No final images | Add layout, waveform and SignalTap images after the new run. |
| P1 | No board log/video | Reflash v7.2, read the new `puf_id`, re-provision the database and record the UART challenge test. |
| P1 | No silicon PUF characterization | Measure repeated power cycles and, ideally, at least two boards/chips. |
| P2 | No final PDF | Keep the report as Markdown until images and final evidence are inserted, then export PDF. |

## Exact evidence package expected at freeze

```text
TrueChip_v7_2_submission/
├── README.md
├── FINALIZATION_STATUS_2026-08-29.md
├── VALIDATION_v7.2.md
├── REPORT_DRAFT_v7.2.md
├── RTL/
├── Simulation/
├── Quartus/
├── OpenLane/secure_asic_top/runs/<newest_run>/
│   ├── results/
│   ├── reports/
│   └── logs/
├── test/
├── secure_chip_web/
└── docs/evidence/                 # images and captured test outputs
```

The final report must call the ASIC result “digital AES/UART security-core
layout on SKY130” and the FPGA result “RO-PUF proof-of-concept”. It must not
call the current GDS a complete ASIC RO-PUF.
