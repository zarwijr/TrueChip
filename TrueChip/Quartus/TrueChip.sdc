# ============================================================
# TrueChip.sdc
# ============================================================

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

derive_pll_clocks
derive_clock_uncertainty

# Asynchronous push-button inputs
set_false_path -from [get_ports {KEY[*]}]

# Asynchronous UART RX
set_false_path -from [get_ports {GPIO[0]}]

# UART TX is asynchronous serial output
set_false_path -to [get_ports {GPIO[1]}]

# LEDs are board-level status outputs
set_false_path -to [get_ports {LEDR[*]}]

# RO-PUF debug pin
set_false_path -to [get_ports {GPIO[2]}]

set_false_path -to [get_ports {GPIO[3]}]

# ============================================================
# RO-PUF timing exceptions (v2 - sua sau khi thay log Quartus that)
#
# Dong cu "set_false_path -through get_nets {u_ro_puf|gen_ro[*].n*}"
# la NO-OP: sau synthesis, Quartus doi ten cac node to hop ben trong
# RO (thanh vd. u_ro_puf|n0~634) - wildcard RTL goc khong con khop
# duoc net nao ("Ignored filter... could not be matched with a
# net"). Day la ly do log bien dich thuc te bao warning nay.
#
# Cac canh bao "Found combinational loop of 2 nodes" quanh
# u_ro_puf|n0~XXX la BAN CHAT cua mot ring oscillator (vong phan
# hoi to hop) - KHONG phai loi, khong can/khong the "sua" bang
# false-path (STA khong tinh setup/hold cho mach khong co create_
# clock lien quan, nen vong nay tu dong nam ngoai cac phep kiem
# tra do). Dem so hau to n0~NNN khac nhau la mot cach kiem tra
# gian tiep: neu co dung 256 gia tri (NUM_RO) thi 256 vong dao
# dong con nguyen ven, chua bi Quartus gop.
#
# Van de THAT can sua: "ro_enable was determined to be a clock but
# was found without an associated clock assignment" va "Design is
# not fully constrained for setup/hold requirements". ro_out[gi]
# (256 mien clock tu do cua tung RO) va ro_enable (clear dung
# chung, fan-out 4096 qua CLKCTRL) chua duoc khai bao quan he voi
# CLOCK_50, nen STA khong co co so phan tich duong tu cnt_r sang
# logic dong bo CLOCK_50 (vd. raw_bits <= ro_cnt[...] trong
# ro_puf.v). Khac voi net to hop ben trong RO, TEN THANH GHI
# (cnt_r trong generate block gen_cnt) On DINH qua synthesis (khong
# bi doi ten nhu node to hop), nen dung duoc lam muc tieu wildcard
# dang tin cay:
set_false_path -to   [get_registers {u_ro_puf|gen_cnt[*].cnt_r[*]}]
set_false_path -from [get_registers {u_ro_puf|gen_cnt[*].cnt_r[*]}]

# LUU Y: dong nay loai cnt_r khoi moi phan tich setup/hold/recovery/
# removal thong thuong - hop ly vi tan so ro_out[gi] CHINH LA dai
# luong vat ly can do (khong phai loi timing can "dong"), va thiet
# ke da tu dam bao an toan bang FREEZE_WAIT_CYCLES trong ro_puf.v
# (cho on dinh truoc khi doc cnt_r) thay vi dua vao STA.
#
# XAC NHAN TU LOG BUILD GAN NHAT (Sun Aug 23 2026): chi rieng 2 dong
# set_false_path o tren la CHUA DU - Warning (332060) "ro_enable was
# determined to be a clock but was found without an associated clock
# assignment" va Info (332102) "Design is not fully constrained" van
# con xuat hien sau khi bien dich. Ly do: set_false_path chi loai
# DUONG DI khoi phan tich, no khong khai bao ro_enable la 1 clock voi
# Timing Analyzer - ma STA da tu xac dinh ro_enable "hanh xu nhu
# clock" (vi no xuat hien trong sensitivity list dang "negedge
# ro_enable" cua thanh ghi cnt_r) va dang cho mot khai bao clock
# tuong ming cho no, khong phai mot ngoai le duong di.
#
# SUA DUNG GOC: khai bao ro_enable la 1 virtual clock, roi noi ro no
# bat dong bo hoan toan voi CLOCK_50 (dung ban chat: day la tin hieu
# dieu khien cua so lay mau PUF, khong lien quan mien clock he thong).
create_clock -name ro_enable_vclk -period 40.0 \
    [get_registers {u_ro_puf|ro_enable}]

set_clock_groups -asynchronous \
    -group [get_clocks {CLOCK_50}] \
    -group [get_clocks {ro_enable_vclk}]

# *** CHUA THE TU BIEN DICH KIEM CHUNG TRONG SANDBOX NAY (khong co
# Quartus/mang). Cu phap create_clock tren get_registers duoc Quartus
# ho tro cho clock/clock-enable noi bo (khong phai port vat ly), nhung
# BAT BUOC ban phai bien dich lai va tu kiem tra:
#   1. Warning (332060) ve ro_enable co con xuat hien khong.
#   2. Info (332102) "Design is not fully constrained" co con khong.
#   3. Neu Quartus bao loi ten node "u_ro_puf|ro_enable" khong khop
#      (vi ten node sau synthesis co the khac ten RTL, giong truong
#      hop cac net to hop n0~NNN da gap o tren), mo Timing Analyzer,
#      tim ten chinh xac cua thanh ghi ro_enable sau synthesis (vi du
#      qua "Report Clocks" hoac Node Finder loc theo "ro_enable"),
#      roi thay vao 2 lenh tren.
#   Neu sau khi sua ten van con 1 trong 2 canh bao o (1)/(2), gui lai
#   log build moi de xac dinh buoc tiep theo (nhieu kha nang can them
#   khai bao tuong tu cho tung ro_out[gi], nhung log hien tai KHONG
#   thay ro_out[gi] bi flag rieng nhu ro_enable).