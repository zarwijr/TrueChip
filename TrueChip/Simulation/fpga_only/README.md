# FPGA-only simulation note

`secure_soc_top_tb_legacy.v` is retained only as historical FPGA-top scaffolding.
Do **not** include it in generic zero-delay ASIC RTL regression: `secure_soc_top`
instantiates the FPGA RO-PUF/ring-oscillator structure, whose behavior depends on
FPGA primitives/placement and is not a normal synchronous digital simulation
model. It also predates the final Protocol V2 CRC framing.

For generic RTL regression use the unit tests in `Simulation/` and the ASIC
hardening top `RTL/secure_asic_top.v`. Validate the real RO-PUF on Cyclone V with
Quartus/SignalTap and board measurements.
