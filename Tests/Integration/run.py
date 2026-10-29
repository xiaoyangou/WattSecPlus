#!/usr/bin/env python3
"""Compile and run production AppKit integration checks on macOS. Saves/restores UI preferences."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="wattsec-integration-") as directory:
    directory = Path(directory)
    source = (root / "WattSecPlus/WattSecPlusApp.swift").read_text().replace("@main\nstruct WattSecPlusApp", "struct WattSecPlusApp")
    generated = directory / "Integration.swift"
    generated.write_text(source + "\n" + Path(__file__).with_name("checks.swift").read_text())
    executable = directory / "integration"
    subprocess.run(["swiftc", "-module-cache-path", str(directory / "cache"), str(generated),
                    str(root / "WattSecPlus/BatteryStatus.swift"), str(root / "WattSecPlus/SMC.swift"),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
