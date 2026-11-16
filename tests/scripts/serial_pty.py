"""Run serial adapter tests and two bridge processes through POSIX PTYs."""
import os
from pathlib import Path
import pty
import select
import subprocess
import struct
import zlib
import time
import tty

ROOT = Path(__file__).resolve().parents[2]


def line(process, expected, timeout=5):
    ready, _, _ = select.select([process.stdout], [], [], timeout)
    if not ready:
        raise AssertionError(f"timed out waiting for {expected}")
    result = process.stdout.readline().decode().strip()
    print(result)
    assert expected in result, (expected, result)


def finish(process):
    output, _ = process.communicate(timeout=5)
    print(output.decode(), end="")
    assert process.returncode == 0, (process.args, process.returncode)


def cleanup(processes, descriptors):
    for process in processes:
        if process.poll() is None:
            process.kill()
        process.wait()
    for descriptor in descriptors:
        os.close(descriptor)


def cobs(data):
    """Reference encoder used to inject wire frames through the serial adapter."""
    output = bytearray([0])
    code_index, code = 0, 1
    for value in data:
        if value == 0:
            output[code_index] = code
            code_index, code = len(output), 1
            output.append(0)
        else:
            output.append(value)
            code += 1
            if code == 255:
                output[code_index] = code
                code_index, code = len(output), 1
                output.append(0)
    output[code_index] = code
    return b"\x00" + output + b"\x00"


def transport_test():
    master, slave = pty.openpty()
    tty.setraw(slave)
    process = subprocess.Popen(
        [str(ROOT / "tests/bin/serial_transport_tests"), os.ttyname(slave)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0,
    )
    try:
        line(process, "ready")
        # Mid-frame startup, malformed code, and overflow must not escape.
        os.write(master, b"startup\x00\x03\x22\x00" + b"\x01" * 1050 + b"\x00")
        # Reference encoding of 00 11 13 FF 00, split across a timeout.
        os.write(master, b"\x01\x04\x11")
        line(process, "partial retained")
        os.write(master, b"\x13\xff\x01\x00\x02\x2a\x02\x2b\x00")
        echoed = b""
        deadline = time.monotonic() + 3
        while len(echoed) < 6 and time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                echoed += os.read(master, 4096)
        assert echoed == b"\x00\x02\x2a\x02\x2b\x00", echoed
        line(process, "ready for checksum recovery")
        wire = bytearray(struct.pack(">HHIHI", 0xBEAC, 7, 1, 3, 0) + b"\x2a\x00\x2b")
        wire[10:14] = struct.pack(">I", zlib.crc32(wire))
        corrupt = bytearray(wire)
        corrupt[-1] ^= 1  # Valid COBS, damaged payload, original CRC retained.
        os.write(master, cobs(corrupt) + cobs(wire))
        finish(process)
    finally:
        cleanup([process], [master, slave])


def demo_test():
    left, left_slave = pty.openpty()
    right, right_slave = pty.openpty()
    tty.setraw(left_slave)
    tty.setraw(right_slave)
    processes = []
    try:
        subscriber = subprocess.Popen(
            [str(ROOT / "demo/bin/serial_subscriber"), os.ttyname(right_slave), "200"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0,
        )
        processes.append(subscriber)
        line(subscriber, "ready")
        publisher = subprocess.Popen(
            [str(ROOT / "demo/bin/serial_publisher"), os.ttyname(left_slave), "200"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0,
        )
        processes.append(publisher)
        deadline = time.monotonic() + 20
        while any(p.poll() is None for p in processes):
            if time.monotonic() > deadline:
                raise AssertionError("serial demo timed out")
            readable, _, _ = select.select([left, right], [], [], 0.05)
            for source in readable:
                target = right if source == left else left
                data = os.read(source, 4096)
                # Split chunks to exercise stream reads, not datagram reads.
                for start in range(0, len(data), 7):
                    remaining = data[start:start + 7]
                    while remaining:
                        remaining = remaining[os.write(target, remaining):]
        for process in processes:
            finish(process)
    finally:
        cleanup(processes, [left, left_slave, right, right_slave])


if __name__ == "__main__":
    transport_test()
    demo_test()
    print("serial_pty: PASS (recovery, timeout, binary transparency, 200 typed readings)")
