import serial
import time
import sys

# ============================================================
# TRUECHIP UART POSITIVE TEST - PROTOCOL V2
# ============================================================

PORT = "COM3"
BAUD = 115200

MAGIC = 0xA5
VERSION = 0x01

CMD_GET_ID = 0x01

EXPECTED_GET_ID = bytes([
    0xA5, 0x01, 0x00, 0x10,
    0x25, 0x83,
    0x25, 0x83,
    0x25, 0x83,
    0x25, 0x83,
    0x25, 0x83,
    0x25, 0x83,
    0x25, 0x83,
    0x25, 0x83,
])


# ============================================================
# CRC16 CCITT
# POLY = 0x1021
# INIT = 0xFFFF
# ============================================================

def crc16_ccitt(data):
    crc = 0xFFFF

    for b in data:
        crc ^= b << 8

        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF

    return crc


# ============================================================
# BUILD PACKET
#
# A5 | VER | CMD | LEN | PAYLOAD | CRC16
#
# CRC covers:
# VER | CMD | LEN | PAYLOAD
# ============================================================

def packet(cmd, payload=b""):
    body = bytes([
        VERSION,
        cmd,
        len(payload)
    ]) + payload

    crc = crc16_ccitt(body)

    return (
        bytes([MAGIC]) +
        body +
        bytes([
            (crc >> 8) & 0xFF,
            crc & 0xFF
        ])
    )


def get_id_packet():
    return packet(CMD_GET_ID)


# ============================================================
# UTILITY
# ============================================================

def dump(data):
    return " ".join(f"{b:02x}" for b in data)


def flush_uart(ser):
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.02)


def send_packet(ser, data):
    print("TX:", dump(data))

    for i, b in enumerate(data):
        print(f"  TX[{i:02d}] = {b:02x}")

    ser.write(data)
    ser.flush()


def read_exact(ser, n, timeout=4.0):
    rx = bytearray()

    deadline = time.time() + timeout

    while len(rx) < n and time.time() < deadline:

        waiting = ser.in_waiting

        if waiting:
            rx.extend(ser.read(waiting))
        else:
            time.sleep(0.005)

    return bytes(rx)


# ============================================================
# CHECKERS
# ============================================================

def check_get_id(rx):
    if rx != EXPECTED_GET_ID:
        raise AssertionError(
            "GET_ID mismatch\n"
            f"Expected: {dump(EXPECTED_GET_ID)}\n"
            f"Got     : {dump(rx)}"
        )


# ============================================================
# TEST 1
# BASIC GET_ID
# ============================================================

def test_get_id(ser):

    print("TEST 1: GET_ID")

    flush_uart(ser)

    tx = get_id_packet()

    send_packet(ser, tx)

    rx = read_exact(ser, len(EXPECTED_GET_ID))

    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))

    check_get_id(rx)

    print("[PASS] GET_ID\n")


# ============================================================
# TEST 2
# BACK-TO-BACK GET_ID x3
#
# Verifies:
# - RX FIFO
# - parser
# - command handling
# - TX FIFO
# - multiple packets without idle gap
# ============================================================

def test_back_to_back(ser):

    print("TEST 2: BACK-TO-BACK GET_ID x3")

    flush_uart(ser)

    tx = get_id_packet() * 3

    send_packet(ser, tx)

    expected_len = len(EXPECTED_GET_ID) * 3

    rx = read_exact(ser, expected_len)

    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))

    if len(rx) != expected_len:
        raise AssertionError(
            f"expected {expected_len} RX bytes, "
            f"got {len(rx)}"
        )

    for i in range(3):

        start = i * len(EXPECTED_GET_ID)
        end = start + len(EXPECTED_GET_ID)

        response = rx[start:end]

        check_get_id(response)

    print("[PASS] BACK-TO-BACK GET_ID x3\n")


# ============================================================
# TEST 3
# PACKET SEPARATION
#
# Valid packet + idle + valid packet
#
# Verifies parser can return to IDLE after a valid packet.
# ============================================================

def test_separated_packets(ser):

    print("TEST 3: SEPARATED GET_ID x2")

    flush_uart(ser)

    tx = get_id_packet()

    # First packet
    send_packet(ser, tx)

    rx1 = read_exact(
        ser,
        len(EXPECTED_GET_ID)
    )

    print("RX1 LEN =", len(rx1))
    print("RX1     =", dump(rx1))

    check_get_id(rx1)

    # Small idle interval
    time.sleep(0.05)

    # Second packet
    send_packet(ser, tx)

    rx2 = read_exact(
        ser,
        len(EXPECTED_GET_ID)
    )

    print("RX2 LEN =", len(rx2))
    print("RX2     =", dump(rx2))

    check_get_id(rx2)

    print("[PASS] SEPARATED GET_ID x2\n")


# ============================================================
# TEST 4
# FINAL HEALTH CHECK
#
# Confirms DUT still responds correctly after all previous
# positive traffic.
# ============================================================

def test_final_health(ser):

    print("TEST 4: FINAL GET_ID HEALTH CHECK")

    flush_uart(ser)

    send_packet(
        ser,
        get_id_packet()
    )

    rx = read_exact(
        ser,
        len(EXPECTED_GET_ID)
    )

    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))

    check_get_id(rx)

    print("[PASS] FINAL HEALTH CHECK\n")


# ============================================================
# MAIN
# ============================================================

def main():

    print("==============================================")
    print(" TRUECHIP UART POSITIVE TEST - PROTOCOL V2")
    print("==============================================\n")

    print(f"PORT : {PORT}")
    print(f"BAUD : {BAUD}\n")

    print("PACKET = A5 | VER | CMD | LEN | PAYLOAD | CRC16")
    print("CRC16  = CCITT / POLY 0x1021 / INIT 0xFFFF")
    print("CRC covers VER | CMD | LEN | PAYLOAD\n")

    tests = [
        ("GET_ID", test_get_id),
        ("BACK-TO-BACK GET_ID x3", test_back_to_back),
        ("SEPARATED GET_ID x2", test_separated_packets),
        ("FINAL GET_ID HEALTH CHECK", test_final_health),
    ]

    passed = 0
    failed = []

    ser = None

    try:

        ser = serial.Serial(
            PORT,
            BAUD,
            timeout=0.1
        )

        time.sleep(0.2)

        flush_uart(ser)

        print("[PASS] Serial port opened\n")

        for name, test_fn in tests:

            try:

                test_fn(ser)

                passed += 1

            except Exception as e:

                failed.append(
                    (name, str(e))
                )

                print(
                    f"[FAIL] {name}: {e}\n"
                )

                flush_uart(ser)

        # ----------------------------------------------------
        # FINAL RESULT
        # ----------------------------------------------------

        print("==============================================")
        print("FINAL RESULT")
        print("==============================================\n")

        for name, _ in tests:

            is_failed = any(
                failed_name == name
                for failed_name, _ in failed
            )

            if is_failed:
                print("[FAIL]", name)
            else:
                print("[PASS]", name)

        print()
        print(f"TOTAL PASS = {passed}")
        print(f"TOTAL FAIL = {len(failed)}")
        print("----------------------------------------------")

        if failed:

            print("[FAIL] UART POSITIVE TESTS FAILED")

            sys.exit(1)

        print("[PASS] ALL UART POSITIVE TESTS PASSED")

    except serial.SerialException as e:

        print("[FAIL] UART OPEN FAILED")
        print(e)

        sys.exit(2)

    finally:

        if ser is not None:

            ser.close()

            print("[INFO] Serial port closed")


if __name__ == "__main__":
    main()