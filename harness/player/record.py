"""Bounded simulator motion capture; wait for the recorder's signal handler before stopping."""
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

device, destination = sys.argv[1:]
log = Path(destination).with_suffix(".record.log")
with log.open("w") as output:
    recorder = subprocess.Popen(
        ["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", destination],
        stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
    )
    deadline = time.monotonic() + 30
    while recorder.poll() is None and time.monotonic() < deadline:
        if "Recording started" in log.read_text(errors="replace"):
            time.sleep(2)
            break
        time.sleep(0.1)
    if recorder.poll() is None:
        os.killpg(recorder.pid, signal.SIGINT)
    try:
        recorder.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(recorder.pid, signal.SIGTERM)
        try:
            recorder.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(recorder.pid, signal.SIGKILL)
            recorder.wait()
    print(f"Simulator motion capture exited {recorder.returncode}")
