# TrueChip v7.2 - Secure AES Authentication Chip (UART now, NFC/RFID future work)

> **Purpose of this README:** this is the project context/source-of-truth that
> should travel with every ZIP. When the project is uploaded into a new AI/chat
> session, read this file first, then inspect the newest Quartus/OpenLane logs
> before proposing RTL or layout changes. Do not assume a previous run passed if
> its logs are not inside the ZIP.

**Context freeze:** 29/08/2026 (Vietnam time) — patch level **v7.2**  
**Đọc trước:** `CHANGELOG_v7.2.md`, `VALIDATION_v7.2.md`, `TEST_PLAN_v7.2.md`.

> **v7.2 sửa một lỗi chức năng P0:** `ro_puf.v` dùng chung một tín hiệu để
> vừa gate vòng dao động vừa xóa bộ đếm, nên `puf_id` luôn bằng `128'd0`
> trên **mọi** board. Chip vẫn xác thực đúng nên Quartus, timing và test
> board đều không phát hiện — thứ mất đi là toàn bộ luận điểm per-device
> uniqueness. **Sau khi sửa, khóa trên board đã đổi: phải cấp phát lại
> database trước khi demo** (xem `TEST_PLAN_v7.2.md` Giai đoạn 0).

Trước khi tin bất kỳ khẳng định nào trong file này:
```bash
bash Simulation/run_regression.sh                              # phải 8/8
python3 OpenLane/secure_asic_top/check_signoff.py runs/<run>   # phải không còn BLOCKER
```

**Immediate competition direction:** AES-128 hardware authentication + UART FPGA
prototype + SKY130 digital RTL-to-GDS hardening.  
**Future product direction:** replace/augment UART transport with NFC/RFID for
anti-counterfeit/authentication of high-value goods and high-value pharmaceutical
/ health products.  
**Commercial target:** silicon IC cost **below USD 1/chip at high volume** if
market demand justifies production. This is a business/engineering target, **not
a result demonstrated by the current RTL or SKY130 layout**.

---

## 1. Competition context and submission evidence

The 2026 security-IC competition expects at least logic/RTL, simulation and
verification. For the preliminary submission, the technical report is expected
to show items such as layout, waveform, DRC/LVS and timing, together with an FPGA
demo video. The judging criteria also explicitly emphasize correct function,
clear protection target/threat model, security evidence, implementation quality
(including cost/resources), creativity, applicability/scalability and technical
completeness.

**Project implication:** a screenshot of a layout alone is not enough. The
submission package should contain reproducible RTL/tests plus the actual
synthesis/STA/DRC/LVS evidence from the exact run being reported.

### Working schedule

| Milestone | Competition window |
|---|---|
| Training / implementation | 16/07/2026 - 09/09/2026 |
| Submit preliminary entry | 10/09/2026 - 19/09/2026 |
| Preliminary judging | 20/09/2026 - 30/09/2026 |
| Final refinement | 01/10/2026 - 19/10/2026 |
| Final / awards | 20/10/2026 - 31/10/2026 |

---

## 2. What TrueChip is trying to prove now

TrueChip is currently a **hardware-authentication prototype**, not a complete
commercial NFC tag IC. The near-term competition claim should be narrow and
verifiable:

1. A host sends a framed challenge through UART.
2. The chip identifies itself with a public 128-bit UID.
3. A per-device/diversified AES-128 key is established at boot in the FPGA
   architecture.
4. The chip returns `AES-128(secret_key, nonce XOR UID)`.
5. Replay history, rate limiting and lockout add protocol-level abuse resistance.
6. A server independently recomputes and verifies the response.
7. The FPGA path demonstrates the RO-PUF concept; the ASIC layout path hardens
   the **digital AES/UART security core** on SKY130.

This separation is deliberate. It prevents the report from claiming that an
FPGA-specific ring-oscillator PUF has already been correctly implemented as a
SKY130 ASIC macro when it has not.

---

## 3. Toolchain / environment

- **FPGA:** Intel Quartus Prime **25.1** (user machine), Cyclone V project under
  `Quartus/`.
- **RTL:** synthesizable Verilog (with SystemVerilog testbench where useful).
- **ASIC physical design:** **OpenLane / OpenROAD** with **SKY130 (`sky130A`)**.
- **Initial standard-cell library:** `sky130_fd_sc_hd`.
- **Initial ASIC clock target:** 50 MHz (`CLOCK_PERIOD = 20 ns`).
- **Software:** Python, pyserial, pycryptodome, Flask/PostgreSQL verification
  service.
- **Evidence status in this candidate:** the curated `run_1` reports show a
  completed digital flow with clean detailed-route DRC, Magic DRC, KLayout DRC,
  LVS and signoff STA. The same scorecard still reports CVC/ERC as aborted,
  29 antenna violations, 621 max-slew violations and 726 max-fanout
  violations. The run's `results/` directory (GDS/DEF/LEF/netlist/SPEF) is not
  present, so this candidate is **not yet the final submission package**.
  See `FINALIZATION_STATUS_2026-08-29.md` for the exact evidence ledger.

---

## 4. Repository map (v7)

```text
TrueChip_v7_submission_ready/
├── RTL/
│   ├── secure_soc_top.v       # FPGA top: UART + RO-PUF + AES/authentication
│   ├── secure_asic_top.v      # SKY130 DIGITAL layout top; no raw RO-PUF loops
│   ├── ro_puf.v               # FPGA RO-PUF proof-of-concept only
│   ├── cmd_parser.v           # Protocol V2 + CRC16-CCITT request parser
│   ├── auth_fsm.v             # response framing, AES command, replay/rate-limit/lockout
│   ├── aes128.v / aes_sbox.v
│   ├── uart_rx.v / uart_tx.v
│   └── chip_rom.v             # prototype-only UID/master-key constants
├── Quartus/                   # Quartus project + FPGA constraints
├── Simulation/                # unit tests + full-chip self-checking TB
│   ├── run_regression.sh      # runs everything, exits non-zero on any failure
│   ├── secure_asic_top_tb.v   # full-chip Protocol V2 test vs golden AES values
│   ├── ro_puf_tb.v            # regression for the v7.1 counter-clear P0 bug
│   └── fpga_only/             # legacy FPGA-top TB not for generic ASIC regression
├── OpenLane/secure_asic_top/  # config, SDC, synced layout RTL and run instructions
│   ├── check_signoff.py       # scorecard for a run: PASS/WARN/BLOCKER + verdict
│   └── run_klayout_drc.sh     # standalone KLayout DRC (OpenLane skips it on sky130A)
├── secure_chip_web/           # UART client + server + provisioning helpers
├── test/                      # physical-board UART tests, including AES challenge
└── docs/                      # requirements/layout plan document
```

---

## 5. Protocol V2 - canonical definition

### Request: host -> chip

```text
A5 | VER | CMD | LEN | PAYLOAD | CRC_H | CRC_L
```

- `MAGIC = 0xA5`
- `VER = 0x01`
- `CMD_GET_ID = 0x01`, `LEN=0`
- `CMD_CHALLENGE = 0x02`, `LEN=16`, payload is a 128-bit nonce
- CRC = CRC16-CCITT, polynomial `0x1021`, init `0xFFFF`
- CRC covers `VER | CMD | LEN | PAYLOAD`

### Response: chip -> host

```text
A5 | VER | STATUS | LEN | PAYLOAD
```

Current status values:

| Status | Meaning |
|---:|---|
| `0x00` | OK |
| `0x03` | REPLAY |
| `0x04` | RATE_LIMIT |
| `0x05` | LOCKED |

Current hardware responses do **not** append CRC. This is acceptable for the
competition freeze because request framing and cryptographic response checking
already exist, but a response CRC is a sensible future transport-integrity
upgrade.

---

## 6. Architecture currently implemented

### 6.1 FPGA top - `secure_soc_top`

Data path:

```text
UART RX
  -> Protocol V2 parser / CRC
  -> 8-entry command FIFO
  -> boot key-ready gate
  -> auth_fsm
  -> shared AES-128 core
  -> UART TX
```

At boot the FPGA RO-PUF produces `puf_id`. The shared AES core computes:

```text
diversified_key = AES-128(master_key, puf_id)
```

After `key_ready=1`, CHALLENGE computes:

```text
plaintext = nonce XOR chip_uid
response  = AES-128(diversified_key, plaintext)
```

`master_key` and `chip_uid` are hard-coded in `chip_rom.v` **only for the
competition prototype**.

### 6.2 Security controls in `auth_fsm`

- History window of the 8 most recent challenge nonces.
- Default 10 ms challenge cooldown at 50 MHz (`COOLDOWN_CYCLES=500000`).
- `STATUS_RATE_LIMIT` for requests within cooldown, without starting AES.
- Repeated rejected requests increment a failure counter.
- Default threshold 5 -> `STATUS_LOCKED`, then lock until real reset/power cycle.

**Threat-model caveat:** the lockout is useful as a demonstration of local abuse
control, but permanent-until-reset lockout can itself be used for denial of
service. For a passive NFC product, power-cycling on field removal also changes
its meaning. Treat the current lockout as a prototype policy, not a finished
commercial security policy.

### 6.3 RO-PUF status

`ro_puf.v` is an FPGA-oriented physical PUF experiment using ring oscillators,
counters and repeated measurements/majority voting. Majority voting improves
repeatability but is **not a full fuzzy extractor/ECC key-reconstruction
solution**, and 128 output bits must not be described as "128 bits of proven
entropy" without measurement.

Before strong PUF claims, measure at minimum:

- intra-device reliability across repeated power cycles;
- temperature / voltage sensitivity;
- inter-device Hamming distance across multiple boards/chips;
- bit bias/uniformity and unstable-bit rate;
- effect of placement/routing constraints;
- resulting key failure rate after the chosen stabilization/error-correction
  method.

---

## 7. Critical v7 code-review fixes already applied

### 7.1 Fixed a boot security-gate bug in `secure_soc_top.v`

In v6 the FIFO **pop** was gated by `key_ready`, but `cmd_get_id` /
`cmd_challenge` remained visible to `auth_fsm` before the boot KDF completed.
That meant a queued CHALLENGE could be consumed using an invalid/zero
`diversified_key`, and GET_ID could also be re-served while the FIFO head did not
advance.

v7 gates the command signals themselves:

```verilog
auth_cmd_* = key_ready && !fifo_empty && ...;
fifo_pop   = auth_cmd_valid && auth_ready;
```

This should be recompiled in Quartus before submission.

### 7.2 Fixed PC software vs hardware protocol mismatch

The hardware parser was already Protocol V2 with CRC, but
`secure_chip_web/client/chip_tester.py` still sent the old raw `0x01` /
`0x02+nonce` format and expected raw 16-byte replies. v7 uses the same framed
Protocol V2 request and response format as RTL.

The old `secure_chip_web/protocol.py` also mapped `0x04/0x05` to unrelated
software meanings. v7 maps them to `RATE_LIMIT` / `LOCKED` and delegates to the
canonical common helper.

### 7.3 Added a real CHALLENGE board test

`test/test_uart_challenge.py` now verifies an actual AES transaction, then checks
rate-limit and replay behavior. It requires the provisioned **diversified key**
(or lab-only master-key + device-ID input) so Python can independently compute
`AES(key, nonce XOR UID)`.

This closes an important evidence gap: the earlier positive UART tests mostly
proved GET_ID/parser behavior, not the full AES authentication path.

### 7.4 Corrected stale testbenches

- `Simulation/cmd_parser_tb.v` now sends valid CRC bytes and verifies CRC reject.
- `Simulation/auth_fsm_tb.sv` sets `COOLDOWN_CYCLES=0` so its immediate replay
  test actually reaches `STATUS_REPLAY` instead of being intercepted by rate
  limiting.
- Duplicate `auth_fsm_tb.v` was removed to avoid duplicate module definitions.
- The old FPGA-top TB was moved to `Simulation/fpga_only/` because raw RO-PUF
  rings are not a clean generic zero-delay simulation target and that TB also
  predates final Protocol V2 framing.

### 7.5 UART RX robustness

`uart_rx.v` now marks the two-flop asynchronous input synchronizer and discards
a byte if the stop bit is low rather than always asserting `rx_valid`.

### 7.6 Server replay bookkeeping order

The Flask server now checks the cryptographic response **before** consuming the
one-time nonce in the database. This avoids letting an invalid response burn a
nonce before authentication. The unique `(uid, nonce)` database key still makes
successful nonce reservation atomic against replay races.

### 7.7 Cleaned Python packaging

The file containing pip package names was incorrectly named `requirements.py`
(and was not valid Python). v7 renames it to `secure_chip_web/requirements.txt`.

---

## 8. What must NOT go directly into the SKY130 digital flow

### `ro_puf.v` is not ordinary ASIC RTL

A ring oscillator is intentionally a combinational loop whose behavior depends
on transistor/process variation and physical placement/routing. A normal digital
synthesis/PnR/STA flow may optimize the loop away or treat it as an invalid
timing structure.

Therefore the first competition GDS target is:

```text
RTL/secure_asic_top.v
```

It includes UART + parser + FIFO + AES + authentication controls, but replaces
the physical PUF output with a fixed `LAYOUT_DEVICE_SEED` **only so the digital
security core can be hardened and timed**. That seed is not a security feature.

A future SKY130 RO-PUF must be hardened/characterized separately and integrated
hierarchically as a macro with physical views (at minimum LEF + GDS, and ideally
netlist/timing/parasitic views). Do not claim the current digital GDS contains a
production RO-PUF.

---

## 9. OpenLane/OpenROAD starting point

Use:

```text
OpenLane/secure_asic_top/
```

The folder contains:

- `config.json`
- `constraints.sdc`
- `src/*.v`
- `sync_rtl.py`
- a dedicated `README.md` with run/log instructions.

Initial settings intentionally favor getting one clean baseline first:

- PDK: `sky130A`
- SCL: `sky130_fd_sc_hd`
- clock: 20 ns / 50 MHz
- initial core utilization: 35%
- 1:1 aspect ratio
- async `rst_n` and external `uart_rx_i` are cut from synchronous input timing;
  the internal UART synchronizer remains timed.

**Do not optimize for smallest die area before the first complete clean run.**
First establish synthesis, floorplan, CTS, route, post-route STA, DRC and LVS.
Then tune density/area/clock one variable at a time.

### Minimum evidence to return after each OpenLane run

At minimum include the newest run's:

- top-level log / warnings and tool/PDK version information;
- resolved config;
- synthesis cell/area statistics and warnings;
- floorplan utilization and routing congestion information;
- CTS summary;
- post-route setup/max and hold/min timing reports;
- DRC summary/detail;
- Netgen LVS log/report;
- final GDS/DEF/LEF and final netlist/SPEF/SDF where generated;
- final layout screenshot.

If a run fails, send the **failed step log plus the preceding warnings**, not
only a screenshot of the last error line.

---

## 10. Verification still required before the competition report freezes

The current package is a cleaned submission candidate, not a claim that all
gates are closed. The final report must be frozen only after the latest
Quartus/OpenLane run and the real-board evidence are copied into the package.

The code in this ZIP has been statically reviewed and software-side checks can
be run in a normal Python environment, but the following must be confirmed on
the user's actual toolchain:

- Quartus 25.1: clean compile of v7; review all warnings, not only "0 errors".
- RTL simulation: AES vectors, parser CRC tests, auth FSM tests.
- FPGA board: GET_ID positive/negative tests and `test_uart_challenge.py`.
- FPGA PUF: at least repeated measurements; ideally >=2 physical boards/chips.
- OpenLane/OpenROAD SKY130: complete physical flow and real reports.
- Post-route: both setup and hold timing; DRC and LVS.

**No report sentence should claim a result that is not backed by an attached log
or measured output.**

---

## 11. Production-security gaps to state openly

These are not reasons to abandon the design; they are boundaries between the
competition prototype and a production secure IC.

- `master_key` and UID are RTL constants in the prototype. Production needs
  secure per-device provisioning and OTP/eFuse/NVM or a validated PUF-based key
  reconstruction design.
- RO-PUF majority voting is not a complete fuzzy extractor/ECC scheme.
- The current server lets the reader/client choose the nonce. A production
  service should preferably issue/authorize short-lived server challenges and
  define replay/relay behavior explicitly.
- The prototype PostgreSQL database stores per-device secret keys in application-readable form. Production should use protected/wrapped keys or an HSM/key service so compromise of the application database does not directly disclose the fleet authentication secrets.
- Side-channel resistance of `aes128.v` is not established. A normal functional
  AES core is not automatically DPA/CPA-resistant.
- Fault injection/tamper response is not established.
- Lockout can cause denial of service and needs a product-specific policy.
- Response frames have no transport CRC today.
- UART is a lab/demo transport, not the future consumer product interface.

For the competition, these limitations are best presented as an explicit threat
model + future-work plan rather than hidden.

---

## 12. Future work - NFC/RFID product direction

### 12.1 Product goal

Future TrueChip should authenticate products where counterfeit risk justifies a
secure tag, especially:

- high-value goods / luxury or premium products;
- high-value medicines / pharmaceuticals;
- selected health products where provenance/authenticity matters.

The current AES/authentication core should remain as transport-independent as
possible so UART can later be replaced by an NFC/RFID interface without
rewriting the cryptographic trust logic.

### 12.2 Recommended development path

**Phase A - competition (now):** UART + AES + FPGA RO-PUF demonstration + digital
SKY130 layout.

**Phase B - practical NFC proof-of-concept:** connect the digital TrueChip core
to an **external NFC/RFID front-end/transceiver** through a simple digital
interface. This validates phone/app/user flow and market use-case before taking
on custom RF/analog silicon risk.

**Phase C - integrated NFC/RFID IC:** only after the protocol/product is proven,
integrate or license the RF/analog front end and NVM, or harden them as macros in
a suitable mixed-signal process.

### 12.3 Blocks a true passive NFC/RFID IC may require

Depending on the selected standard and active/passive architecture:

- 13.56 MHz RF front end and antenna interface;
- rectifier / energy harvesting for passive operation;
- voltage regulation / POR / brownout behavior;
- clock recovery and data recovery;
- demodulator and load-modulation/backscatter path;
- ESD/pad ring and antenna protection;
- protocol/state-machine support for the selected NFC/RFID standard;
- OTP/EEPROM/NVM for UID, provisioning data, counters or keys;
- very-low-power AES/authentication core and clock/power gating;
- secure challenge protocol and anti-replay policy;
- optional PUF/key reconstruction if measurements justify it;
- test modes, wafer sort/final test and secure personalization flow.

A plain OpenLane digital flow does **not** create these RF/analog/NVM functions.
They require analog/mixed-signal design or proven macros/IP and a process that
supports the required devices/memory.

### 12.4 Standards decision still open

Do not lock the design to a standard merely because it is called "NFC". Select
based on phone compatibility, read range, memory model, power budget and security
protocol. Candidate families to evaluate include ISO/IEC 14443 / NFC Forum
phone-centric tags and ISO/IEC 15693 vicinity tags. The final choice is future
work and should be justified by the actual product use case.

### 12.5 Sub-USD-1 IC cost target

The target of **< USD 1 per chip at mass production** is plausible only as a
commercial target to be validated. The current SKY130 GDS cannot prove it.
A cost model must include:

```text
die area + wafer price + yield + mask/NRE amortization + test + secure
personalization + package/bump + NVM/RF IP + logistics
```

For a complete NFC label/tag, also account for antenna/inlay/assembly, which is
outside bare-die cost. A mature 130/180 nm mixed-signal/NVM process may ultimately
be more appropriate than the exact open SKY130 competition flow; that decision
should be made after area/power/NVM/RF requirements and expected volume are
known.

---

## 13. Provisioning model to resolve before a product pilot

The verification server stores a `secret_key` per UID, but the normal chip
protocol intentionally does not export its secret. Therefore manufacturing must
have a trusted enrollment/provisioning path that binds:

```text
UID <-> per-device/diversified secret <-> product record
```

For the competition, a lab-only process can provision the known diversified key
to the database. For production, define a secure station/HSM/OTP/eFuse or
PUF-enrollment process; do not add a normal UART command that simply reads out
the production key.

---

## 14. Priority order from 24/08/2026

1. Recompile **v7** in Quartus 25.1 and return complete compile/timing warnings.
2. Run RTL unit simulations; fix any compile/simulation issue caused by the v7
   protocol/testbench cleanup.
3. Run `test_uart_challenge.py` with the correct provisioned diversified key and
   capture output/waveform/video evidence.
4. Collect PUF measurements on real hardware (preferably multiple boards).
5. Run the first OpenLane SKY130 baseline using `secure_asic_top`.
6. Return the newest OpenLane run directory/logs; iterate until STA/DRC/LVS are
   defensible.
7. Freeze figures/waveforms/tables for the competition PDF.
8. Keep NFC/RFID and sub-$1 commercialization in the **Future Work / Roadmap**
   section, not as a completed current capability.

---

## 15. What to include in the next ZIP sent for review

Send the entire updated project plus the newest logs. Prefer this structure:

```text
TrueChip_next.zip
├── README.md
├── RTL/
├── Simulation/
├── Quartus/
│   └── <latest compile/timing reports/logs>
├── OpenLane/secure_asic_top/
│   └── runs/<newest_run>/...
├── test/
│   └── <captured UART test outputs if available>
└── docs/
```

In the next review, the reviewer/AI should first compare the new logs against the
RTL/config in the same ZIP, identify the **first real failing stage**, and avoid
changing multiple unrelated design variables at once.

---

## 16. Submission claim wording (safe and defensible)

Use wording along these lines in the report:

> TrueChip demonstrates an AES-128 hardware challenge-response authentication
> architecture with UART Protocol V2, CRC-protected requests, replay detection,
> rate limiting and lockout on FPGA. A ring-oscillator PUF is evaluated as a
> device-specific physical identity/key-diversification source in the FPGA
> prototype. For physical-design evidence, the synchronous digital AES/UART
> security core is hardened separately on SKY130 using OpenLane/OpenROAD; ASIC
> RO-PUF macro integration and NFC/RFID front-end integration are future work.

This wording avoids claiming a production NFC chip, a production fuzzy extractor
or a completed ASIC PUF before those items are actually implemented/measured.

---

*Last updated: 24/08/2026 - v7 review/layout-preparation pass.*
