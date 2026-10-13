#!/usr/bin/env python3
"""Run pure history checks without accessing accounts, APIs or real logs."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="aicost-test-") as temporary:
    executable = pathlib.Path(temporary) / "history-checks"
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", str(ROOT / "Sources/UsageHistory.swift"), str(ROOT / "Tests/HistoryChecks.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
