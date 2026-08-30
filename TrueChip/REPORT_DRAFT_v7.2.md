# TrueChip v7.2 - technical report draft

> This is a Markdown draft intentionally kept before PDF export. Insert the
> final images and the newest run/board evidence first.

## 1. Problem and protection target

TrueChip is a hardware-authentication prototype for detecting counterfeit or
cloned products. The competition implementation demonstrates AES-128
challenge-response through UART, with the FPGA path using an RO-PUF-derived
device value and the ASIC path hardening the digital security core on SKY130.

## 2. Architecture

```text
UART RX -> Protocol V2 + CRC -> command FIFO -> boot key-ready gate
         -> authentication FSM -> AES-128 -> framed UART response

FPGA path: RO-PUF -> puf_id -> key diversification -> AES authentication
ASIC path: layout seed stand-in -> digital AES/UART security-core hardening
```

**[INSERT FIGURE 1: system block diagram]**

## 3. Security protocol

- Request: `A5 | VER | CMD | LEN | PAYLOAD | CRC16-CCITT`.
- `GET_ID` returns a public 128-bit UID.
- `CHALLENGE` returns `AES-128(diversified_key, nonce XOR UID)`.
- The hardware keeps a history of recent nonces and enforces cooldown and
  lockout policies.

## 4. RO-PUF contribution

The v7.2 RTL separates `ro_enable` from `cnt_clr_n`. The oscillator gate now
stops the rings without erasing their counters; the counters are cleared only
while the rings are stopped. The regression test catches the former v7.1
failure mode in which `puf_id` became all zero.

**[INSERT FIGURE 2: RO-PUF waveform showing `ro_enable`, `cnt_clr_n` and counter hold]**

**[INSERT FIGURE 3: SignalTap showing `puf_valid` and non-zero `puf_id`]**

Until board characterization is attached, describe the PUF as a proof-of-
concept, not as proven 128-bit entropy.

## 5. RTL and FPGA verification

Insert the final regression output, AES known-answer result, parser CRC result,
full-chip result and physical UART challenge output here.

**[INSERT FIGURE 4: RTL waveform for GET_ID/CHALLENGE]**

**[INSERT FIGURE 5: board + terminal showing successful challenge]**

Report the final Quartus compile from the same RTL revision as the bitstream.

## 6. SKY130 digital layout

The current physical-design target is `secure_asic_top`, which deliberately
excludes the FPGA-specific ring-oscillator loop. The correct claim is a
“digital AES/UART security-core layout on SKY130”. A future ASIC RO-PUF needs a
separate physical macro with LEF/GDS and characterization.

Insert the newest run's exact values for die/core area, utilization, cell
count, setup/hold timing, DRC, LVS, XOR, CVC/ERC and antenna status.

**[INSERT FIGURE 6: final GDS/KLayout full view]**

**[INSERT FIGURE 7: detailed layout view with standard cells and PDN]**

## 7. Threat model and limitations

State explicitly that the prototype does not yet provide side-channel
countermeasures, fault-injection protection, a complete fuzzy extractor, a
production provisioning root of trust or a response CRC. The current lockout
policy can also create a denial-of-service trade-off.

## 8. Future work

The next product step is an external NFC/RFID front-end connected to the
transport-independent digital core. An integrated passive tag would additionally
need RF/antenna, rectifier, regulation, clock/data recovery, load modulation,
NVM, ESD/pads and secure personalization.

## 9. Evidence index

| Figure/table | Evidence source |
|---|---|
| Figure 1 | `docs/evidence/architecture.png` |
| Figure 2 | `docs/evidence/ro_puf_waveform.png` |
| Figure 3 | `docs/evidence/signaltap_puf_id.png` |
| Figure 4 | `docs/evidence/full_chip_waveform.png` |
| Figure 5 | `docs/evidence/board_uart_demo.png` |
| Figure 6 | `docs/evidence/layout_full.png` |
| Figure 7 | `docs/evidence/layout_detail.png` |

Replace every placeholder before PDF export and verify that every numerical
claim points to a captured log or measurement.
