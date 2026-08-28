import serial, time, sys

PORT = "COM3"
BAUD = 115200
MAGIC = 0xA5
VERSION = 0x01
CMD_GET_ID = 0x01
CMD_CHALLENGE = 0x02
STATUS_OK = 0x00
STATUS_REPLAY = 0x03
NONCE = bytes(range(0x20, 0x30))

def crc16_ccitt(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = (((crc << 1) ^ 0x1021) if (crc & 0x8000) else (crc << 1)) & 0xFFFF
    return crc

def packet(cmd, payload=b""):
    body = bytes([VERSION, cmd, len(payload)]) + payload
    c = crc16_ccitt(body)
    return bytes([MAGIC]) + body + bytes([(c >> 8) & 0xff, c & 0xff])

def get_id():
    return packet(CMD_GET_ID)

def challenge(nonce=NONCE):
    assert len(nonce) == 16
    return packet(CMD_CHALLENGE, nonce)

def dump(x):
    return " ".join(f"{b:02x}" for b in x)

def flush(ser):
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.02)

def send(ser, data, delay=0):
    print("TX:", dump(data))
    for i, b in enumerate(data):
        print(f"  TX[{i:02d}] = {b:02x}")
    if delay:
        # Intentionally fragmented send (e.g. SHORT/PARTIAL CHALLENGE):
        # byte-by-byte with a real inter-byte gap is the point of the test.
        for b in data:
            ser.write(bytes([b]))
            ser.flush()
            time.sleep(delay)
    else:
        # Send the whole packet in one write() call. Writing byte-by-byte
        # with a flush() after each byte lets the Windows COM driver's
        # latency timer (often 1-16 ms) insert gaps between bytes that
        # exceed the UART core's FRAME_TIMEOUT, causing the parser to
        # abort mid-packet even though the bytes themselves are valid.
        ser.write(bytes(data))
        ser.flush()

def read_for(ser, seconds=0.8):
    out = bytearray()
    end = time.time() + seconds
    while time.time() < end:
        if ser.in_waiting:
            out.extend(ser.read(ser.in_waiting))
            end = time.time() + 0.05
        else:
            time.sleep(0.005)
    return bytes(out)

def read_exact(ser, n, timeout=4):
    out = bytearray()
    end = time.time() + timeout
    while len(out) < n and time.time() < end:
        if ser.in_waiting:
            out.extend(ser.read(ser.in_waiting))
        else:
            time.sleep(0.005)
    return bytes(out)

def run_negative(ser, name, data, fragmented=False):
    print(f"TEST: {name}")
    flush(ser)
    send(ser, data, 0.005 if fragmented else 0)
    rx = read_for(ser)
    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))
    if rx:
        raise AssertionError(f"{name}: unexpected response")
    print(f"[PASS] {name}\n")

def valid_get_id(rx):
    return len(rx) == 20 and rx[:4] == bytes([MAGIC, VERSION, STATUS_OK, 0x10])

def test_01(ser):
    run_negative(ser, "BAD MAGIC", bytes([0, VERSION, CMD_GET_ID, 0]))

def test_02(ser):
    run_negative(ser, "BAD VERSION", bytes([MAGIC, 0xff, CMD_GET_ID, 0]))

def test_03(ser):
    run_negative(ser, "UNKNOWN COMMAND", bytes([MAGIC, VERSION, 0xff, 0]))

def test_04(ser):
    run_negative(ser, "ZERO LENGTH + PAYLOAD",
                 bytes([MAGIC, VERSION, CMD_GET_ID, 0, 0x12, 0x34, 0x56, 0x78]))

def test_05(ser):
    run_negative(ser, "CHALLENGE HEADER ONLY",
                 bytes([MAGIC, VERSION, CMD_CHALLENGE, 0x10]))

def test_06(ser):
    run_negative(ser, "SHORT CHALLENGE",
                 bytes([MAGIC, VERSION, CMD_CHALLENGE, 0x10]) + bytes(range(0x10, 0x18)))

def test_07(ser):
    run_negative(ser, "LONG CHALLENGE",
                 bytes([MAGIC, VERSION, CMD_CHALLENGE, 0x10]) + bytes(range(0x20, 0x34)))

def test_08(ser):
    run_negative(ser, "ONE BYTE PACKET", bytes([MAGIC]))

def test_09(ser):
    run_negative(ser, "TWO BYTE PACKET", bytes([MAGIC, VERSION]))

def test_10(ser):
    run_negative(ser, "THREE BYTE PACKET", bytes([MAGIC, VERSION, CMD_GET_ID]))

def test_11(ser):
    print("TEST: EMPTY PACKET")
    flush(ser)
    time.sleep(0.2)
    rx = read_for(ser, 0.5)
    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))
    if rx:
        raise AssertionError("EMPTY PACKET: unexpected response")
    print("[PASS] EMPTY PACKET\n")

def test_12(ser):
    flush(ser)
    data = bytes([0, 0x11, 0x22, 0x33, 0x44, 0x55]) + get_id()
    send(ser, data)
    rx = read_exact(ser, 20)
    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))
    if not valid_get_id(rx):
        raise AssertionError("GARBAGE BEFORE VALID: GET_ID not recovered")
    print("[PASS] GARBAGE BEFORE VALID\n")

def test_13(ser):
    flush(ser)
    send(ser, get_id() + bytes([0, 0x11, 0x22, 0x33, 0x44]))
    rx = read_exact(ser, 20)
    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))
    if not valid_get_id(rx):
        raise AssertionError("VALID GET_ID + GARBAGE failed")
    print("[PASS] VALID PACKET ACCEPTED\n")

def test_14(ser):
    run_negative(ser, "TRUNCATED GET_ID",
                 bytes([MAGIC, VERSION, CMD_GET_ID, 0]))

def test_15(ser):
    run_negative(ser, "WRONG GET_ID LENGTH",
                 bytes([MAGIC, VERSION, CMD_GET_ID, 0x10]))

def test_16(ser):
    run_negative(ser, "GET_ID EXTRA PAYLOAD",
                 bytes([MAGIC, VERSION, CMD_GET_ID, 0, 0xaa, 0xbb, 0xcc, 0xdd]))

def test_17(ser):
    run_negative(ser, "PARTIAL CHALLENGE",
                 bytes([MAGIC, VERSION, CMD_CHALLENGE, 0x10]) + bytes(range(0x20, 0x2a)),
                 fragmented=True)

def test_18(ser):
    print("TEST: RECOVERY AFTER TRUNCATED PACKET")
    flush(ser)
    truncated = bytes([MAGIC, VERSION, CMD_GET_ID, 0])
    send(ser, truncated)
    rx = read_for(ser, 0.4)
    if rx:
        raise AssertionError("truncated packet generated response")
    send(ser, get_id())
    rx = read_exact(ser, 20)
    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))
    if not valid_get_id(rx):
        raise AssertionError("parser did not recover")
    print("[PASS] PARSER RECOVERY\n")

def count_get_id(rx):
    return sum(valid_get_id(rx[i:i+20]) for i in range(0, len(rx), 20))

def test_19(ser):
    print("TEST: BACK-TO-BACK GET_ID")
    flush(ser)
    data = get_id() * 3
    send(ser, data)
    rx = read_exact(ser, 60)
    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))
    n = count_get_id(rx)
    print("VALID GET_ID RESPONSES =", n)
    if n != 3:
        raise AssertionError(f"expected 3 responses, got {n}")
    print("[PASS] BACK-TO-BACK GET_ID\n")

def test_20(ser):
    print("TEST: MIXED GARBAGE STREAM")
    flush(ser)
    data = bytes([0, 0x11, 0x22, 0x33]) + get_id() + bytes([0x66, 0x77, 0x88]) + get_id()
    send(ser, data)
    rx = read_exact(ser, 40)
    print("RX LEN =", len(rx))
    print("RX     =", dump(rx))
    n = count_get_id(rx)
    print("VALID GET_ID RESPONSES =", n)
    if n != 2:
        raise AssertionError(f"expected 2 responses, got {n}")
    print("[PASS] STREAM RECOVERY\n")

def main():
    print("==============================================")
    print(" TRUECHIP UART NEGATIVE TEST - PROTOCOL V2")
    print("==============================================")
    print(f"\nPORT : {PORT}\nBAUD : {BAUD}\n")
    print("PACKET = A5 | VER | CMD | LEN | PAYLOAD | CRC16")
    print("CRC16  = CCITT / POLY 0x1021 / INIT 0xFFFF")
    print("CRC covers VER | CMD | LEN | PAYLOAD")
    print()

    tests = [
        ("BAD MAGIC", test_01), ("BAD VERSION", test_02),
        ("UNKNOWN COMMAND", test_03), ("ZERO LENGTH + PAYLOAD", test_04),
        ("CHALLENGE HEADER ONLY", test_05), ("SHORT CHALLENGE", test_06),
        ("LONG CHALLENGE", test_07), ("ONE BYTE PACKET", test_08),
        ("TWO BYTE PACKET", test_09), ("THREE BYTE PACKET", test_10),
        ("EMPTY PACKET", test_11), ("GARBAGE BEFORE VALID", test_12),
        ("VALID GET_ID + GARBAGE", test_13), ("TRUNCATED GET_ID", test_14),
        ("WRONG GET_ID LENGTH", test_15), ("GET_ID EXTRA PAYLOAD", test_16),
        ("PARTIAL CHALLENGE", test_17), ("RECOVERY AFTER TRUNCATED", test_18),
        ("BACK-TO-BACK GET_ID", test_19), ("MIXED GARBAGE STREAM", test_20)
    ]

    passed, failed = 0, []
    ser = None
    try:
        ser = serial.Serial(PORT, BAUD, timeout=0.1)
        time.sleep(0.2)
        flush(ser)
        print("[PASS] Serial port opened\n")

        for name, fn in tests:
            try:
                fn(ser)
                passed += 1
            except Exception as e:
                failed.append((name, str(e)))
                print(f"[FAIL] {name}: {e}\n")
                flush(ser)

        print("==============================================")
        print("FINAL RESULT")
        print("==============================================\n")
        for name, _ in tests:
            print("[FAIL]" if any(x == name for x, _ in failed) else "[PASS]", name)
        print(f"\nTOTAL PASS = {passed}")
        print(f"TOTAL FAIL = {len(failed)}")
        print("----------------------------------------------")
        if failed:
            print("[FAIL] UART NEGATIVE TESTS FAILED")
            sys.exit(1)
        print("[PASS] ALL 20 UART NEGATIVE TESTS PASSED")
    except serial.SerialException as e:
        print("[FAIL] UART OPEN FAILED")
        print(e)
        sys.exit(2)
    finally:
        if ser:
            ser.close()
            print("[INFO] Serial port closed")

if __name__ == "__main__":
    main()