#!/usr/bin/env python3
"""Granola install/runtime status for the Omarchy bar plugin. Stdlib only."""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
INSTALL_DIR = Path(os.environ.get("GRANOLA_INSTALL_DIR", HOME / "Applications" / "granola"))
LAUNCHER = INSTALL_DIR / "granola.sh"
ELECTRON = INSTALL_DIR / "electron"
DESKTOP = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local" / "share")) / "applications" / "granola.desktop"
DATA_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "Granola"


def dump(payload: dict) -> int:
    print(json.dumps(payload, separators=(",", ":")))
    return 0 if payload.get("ok", True) else 1


def default_status() -> dict:
    return {
        "ok": True,
        "installed": False,
        "running": False,
        "recording": False,
        "loggedIn": False,
        "hasWindow": False,
        "pid": 0,
        "pids": [],
        "launcher": str(LAUNCHER),
        "version": "",
        "statusText": "Not installed",
        "kind": "missing",
        "lastError": "",
    }


def granola_pids() -> list[int]:
    pids: list[int] = []
    needle = str(ELECTRON)
    proc = Path("/proc")
    if not proc.is_dir():
        return pids
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmd = (entry / "cmdline").read_bytes().split(b"\0")[0].decode("utf-8", "replace")
        except OSError:
            continue
        if cmd == needle or cmd.endswith("/granola/electron"):
            pids.append(int(entry.name))
    return pids


def pulse_recording(pids: list[int]) -> bool:
    if not pids:
        return False
    try:
        completed = subprocess.run(
            ["pactl", "list", "source-outputs"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if completed.returncode != 0:
        return False
    block = []
    want = {str(pid) for pid in pids}
    for line in completed.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("Source Output #"):
            if any(f"application.process.id = \"{pid}\"" in "\n".join(block) for pid in want):
                return True
            if any("granola" in item.lower() for item in block):
                return True
            block = [stripped]
            continue
        block.append(stripped)
    joined = "\n".join(block)
    return any(f'application.process.id = "{pid}"' in joined for pid in want) or "granola" in joined.lower()


def has_window() -> bool:
    try:
        completed = subprocess.run(
            ["hyprctl", "clients", "-j"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if completed.returncode != 0 or not completed.stdout.strip():
        return False
    try:
        clients = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return False
    for client in clients:
        blob = " ".join(
            str(client.get(key) or "")
            for key in ("class", "initialClass", "title", "initialTitle")
        ).lower()
        if "granola" in blob:
            return True
    return False


def read_version() -> str:
    path = INSTALL_DIR / "version"
    try:
        text = path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""
    return text.splitlines()[0] if text else ""


def collect() -> dict:
    status = default_status()
    installed = LAUNCHER.is_file() and os.access(LAUNCHER, os.X_OK)
    status["installed"] = installed
    status["loggedIn"] = (DATA_DIR / "stored-accounts.json.enc").is_file() or (DATA_DIR / "granola.db").is_file()
    status["version"] = read_version()
    pids = granola_pids()
    status["pids"] = pids
    status["pid"] = pids[0] if pids else 0
    status["running"] = bool(pids)
    status["hasWindow"] = has_window() if pids else False
    status["recording"] = pulse_recording(pids) if pids else False
    if not installed:
        status["kind"] = "missing"
        status["statusText"] = "Not installed"
    elif status["recording"]:
        status["kind"] = "recording"
        status["statusText"] = "Recording"
    elif status["running"]:
        status["kind"] = "running"
        status["statusText"] = "Running" if status["loggedIn"] else "Running · sign in"
    elif status["loggedIn"]:
        status["kind"] = "idle"
        status["statusText"] = "Ready"
    else:
        status["kind"] = "idle"
        status["statusText"] = "Installed"
    return status


def run(command: list[str]) -> None:
    subprocess.Popen(
        command,
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
    )


def open_app(status: dict) -> dict:
    if not status["installed"]:
        status["ok"] = False
        status["lastError"] = "Granola is not installed"
        return status
    run([status["launcher"]])
    status["statusText"] = "Opening…"
    return status


def install_app() -> dict:
    script = Path(__file__).resolve().parent.parent / "granola-linux.sh"
    if not script.is_file():
        status = default_status()
        status["ok"] = False
        status["lastError"] = "Installer script is missing"
        return status
    terminal = ["xdg-terminal-exec", str(script)]
    try:
        subprocess.Popen(terminal, start_new_session=True)
    except OSError:
        run(["ghostty", "-e", str(script)])
    status = collect()
    status["statusText"] = "Installer launched"
    return status


def quit_app(status: dict) -> dict:
    for pid in status.get("pids") or []:
        try:
            os.kill(int(pid), signal.SIGTERM)
        except OSError:
            continue
    status["running"] = False
    status["recording"] = False
    status["hasWindow"] = False
    status["pids"] = []
    status["pid"] = 0
    status["kind"] = "idle" if status["installed"] else "missing"
    status["statusText"] = "Stopped" if status["installed"] else "Not installed"
    return status


def main() -> int:
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action in ("status", ""):
        return dump(collect())
    status = collect()
    if action == "open":
        return dump(open_app(status))
    if action == "install":
        return dump(install_app())
    if action in ("quit", "stop"):
        return dump(quit_app(status))
    status["ok"] = False
    status["lastError"] = f"Unknown action: {action}"
    return dump(status)


if __name__ == "__main__":
    raise SystemExit(main())
