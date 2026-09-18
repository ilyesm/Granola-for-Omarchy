#!/usr/bin/env python3
"""Granola status, next event, and recording control for the Omarchy bar."""
from __future__ import annotations

import base64
import json
import os
import signal
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME = Path.home()
INSTALL_DIR = Path(os.environ.get("GRANOLA_INSTALL_DIR", HOME / "Applications" / "granola"))
LAUNCHER = INSTALL_DIR / "granola.sh"
ELECTRON = INSTALL_DIR / "electron"
DATA_DIR = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "Granola"
PLUGIN_DIR = Path(__file__).resolve().parent.parent
READ_EVENTS = Path(__file__).resolve().parent / "read_events.js"
BS3 = INSTALL_DIR / "resources" / "app.asar.unpacked" / "node_modules" / "better-sqlite3-multiple-ciphers" / "lib" / "index.js"
EVENT_CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "ilyesm.granola" / "next-event.json"
EVENT_CACHE_TTL_SEC = 20
LATEST_CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "ilyesm.granola" / "latest.json"
LATEST_CACHE_TTL_SEC = 6 * 3600


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
        "nextEvent": None,
        "nowEvent": None,
        "upcoming": [],
        "appVersion": "",
        "latestVersion": "",
        "updateAvailable": False,
    }


def granola_main_pids() -> list[int]:
    pids: list[int] = []
    needle = str(ELECTRON)
    proc = Path("/proc")
    if not proc.is_dir():
        return pids
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "cmdline").read_bytes()
        except OSError:
            continue
        blob = raw.decode("utf-8", "replace")
        if not blob.startswith(needle):
            continue
        if "--type=" in blob:
            continue
        pids.append(int(entry.name))
    return pids


def pulse_recording(pids: list[int]) -> bool:
    if not pids:
        return False
    want = {str(pid) for pid in pids}
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
    block: list[str] = []
    hits = False

    def block_matches(lines: list[str]) -> bool:
        text = "\n".join(lines)
        if "Corked: yes" in text:
            return False
        owned = any(f'application.process.id = "{pid}"' in text for pid in want)
        named = "granola" in text.lower() and "application.name" in text.lower()
        return owned or named

    for line in completed.stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith("Source Output #"):
            if block_matches(block):
                hits = True
                break
            block = [stripped]
            continue
        block.append(stripped)
    return hits or block_matches(block)


def granola_windows() -> list[dict]:
    try:
        completed = subprocess.run(
            ["hyprctl", "clients", "-j"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if completed.returncode != 0 or not completed.stdout.strip():
        return []
    try:
        clients = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return []
    hits = []
    for client in clients:
        blob = " ".join(
            str(client.get(key) or "")
            for key in ("class", "initialClass", "title", "initialTitle")
        ).lower()
        if "granola" in blob:
            hits.append(client)
    return hits


def read_version() -> str:
    path = INSTALL_DIR / "version"
    try:
        text = path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""
    return text.splitlines()[0] if text else ""


def decrypt_dek() -> str | None:
    dek_path = DATA_DIR / "storage.dek"
    try:
        dek = dek_path.read_bytes()
    except OSError:
        return None
    if not dek.startswith(b"v11") and not dek.startswith(b"v10"):
        return None
    try:
        import secretstorage
        from cryptography.hazmat.backends import default_backend
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    except ImportError:
        return None
    password = None
    try:
        conn = secretstorage.dbus_init()
        for collection in secretstorage.get_all_collections(conn):
            try:
                items = list(collection.get_all_items())
            except Exception:
                continue
            for item in items:
                try:
                    if item.get_label() == "Granola Safe Storage":
                        password = item.get_secret()
                        break
                except Exception:
                    continue
            if password:
                break
    except Exception:
        return None
    if not password:
        return None
    payload = dek[3:]
    try:
        key = PBKDF2HMAC(
            algorithm=hashes.SHA1(),
            length=16,
            salt=b"saltysalt",
            iterations=1,
            backend=default_backend(),
        ).derive(password)
        plain = Cipher(algorithms.AES(key), modes.CBC(b" " * 16), backend=default_backend()).decryptor().update(payload)
        pad = plain[-1]
        if pad < 1 or pad > 16:
            return None
        plain = plain[:-pad]
        raw = base64.b64decode(plain)
    except Exception:
        return None
    if len(raw) != 32:
        return None
    return raw.hex()


def load_events(key_hex: str) -> tuple[list[dict], bool]:
    db_path = DATA_DIR / "granola.db"
    if not db_path.is_file() or not READ_EVENTS.is_file() or not ELECTRON.is_file() or not BS3.is_file():
        return [], False
    env = os.environ.copy()
    env["GRANOLA_BS3"] = str(BS3)
    env["ELECTRON_RUN_AS_NODE"] = "1"
    env["NODE_PATH"] = str(INSTALL_DIR / "resources" / "app.asar" / "node_modules")
    try:
        completed = subprocess.run(
            [str(ELECTRON), str(READ_EVENTS), str(db_path)],
            input=key_hex + "\n",
            capture_output=True,
            text=True,
            timeout=8,
            env=env,
        )
    except (OSError, subprocess.TimeoutExpired):
        return [], False
    if completed.returncode != 0 or not completed.stdout.strip():
        return [], False
    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return [], False
    if isinstance(parsed, list):
        return parsed, False
    if isinstance(parsed, dict):
        events = parsed.get("events") if isinstance(parsed.get("events"), list) else []
        return events, parsed.get("recordingHint") is True
    return [], False


def cached_snapshot() -> dict | None:
    try:
        age = datetime.now(timezone.utc).timestamp() - EVENT_CACHE.stat().st_mtime
        if age > EVENT_CACHE_TTL_SEC:
            return None
        parsed = json.loads(EVENT_CACHE.read_text(encoding="utf-8"))
        if isinstance(parsed, dict):
            return parsed
        if isinstance(parsed, list):
            return {"events": parsed, "recordingHint": False}
    except (OSError, json.JSONDecodeError):
        return None
    return None


def store_snapshot(events: list[dict], recording_hint: bool) -> None:
    try:
        EVENT_CACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = EVENT_CACHE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps({"events": events, "recordingHint": recording_hint}), encoding="utf-8")
        tmp.chmod(0o600)
        tmp.replace(EVENT_CACHE)
    except OSError:
        pass


def format_when(start_iso: str, end_iso: str) -> str:
    try:
        start = datetime.fromisoformat(start_iso.replace("Z", "+00:00")).astimezone()
        end = datetime.fromisoformat(end_iso.replace("Z", "+00:00")).astimezone()
    except ValueError:
        return ""
    now = datetime.now().astimezone()
    same_day = start.date() == now.date()
    day = "Today" if same_day else start.strftime("%a %-d %b")
    def clock(dt: datetime) -> str:
        return dt.strftime("%-I:%M %p").replace(" 0", " ").lstrip("0")
    return f"{day} {clock(start)} – {clock(end)}"


def people_label(names: list) -> str:
    clean = [str(name).strip() for name in names if str(name).strip()]
    if not clean:
        return ""
    if len(clean) == 1:
        return clean[0]
    if len(clean) == 2:
        return f"{clean[0]} and {clean[1]}"
    return f"{clean[0]} + {len(clean) - 1}"


def parse_iso(value: str) -> datetime | None:
    try:
        return datetime.fromisoformat(str(value or "").replace("Z", "+00:00"))
    except ValueError:
        return None


def public_event(event: dict | None, now: datetime | None = None) -> dict | None:
    if not event:
        return None
    start = str(event.get("start") or "")
    end = str(event.get("end") or "")
    start_at = parse_iso(start)
    end_at = parse_iso(end)
    current = now or datetime.now(timezone.utc)
    happening = bool(start_at and end_at and start_at <= current <= end_at)
    people = event.get("people") if isinstance(event.get("people"), list) else []
    return {
        "id": str(event.get("id") or ""),
        "title": str(event.get("title") or "Untitled"),
        "start": start,
        "end": end,
        "when": format_when(start, end),
        "location": str(event.get("location") or ""),
        "people": people,
        "peopleLabel": people_label(people),
        "happening": happening,
        "soon": event_is_soon(start, end),
    }


def event_is_soon(start_iso: str, end_iso: str, lead_min: int = 15) -> bool:
    try:
        start = datetime.fromisoformat(start_iso.replace("Z", "+00:00"))
        end = datetime.fromisoformat(end_iso.replace("Z", "+00:00"))
    except ValueError:
        return False
    now = datetime.now(timezone.utc)
    return start - now <= timedelta(minutes=lead_min) and end >= now


def calendar_snapshot() -> tuple[list[dict], bool]:
    cached = cached_snapshot()
    if cached is not None:
        events = cached.get("events") if isinstance(cached.get("events"), list) else []
        return events, cached.get("recordingHint") is True
    key = decrypt_dek()
    if not key:
        return [], False
    events, hint = load_events(key)
    store_snapshot(events, hint)
    return events, hint


def next_event() -> dict | None:
    events, _hint = calendar_snapshot()
    return events[0] if events else None


def collect() -> dict:
    status = default_status()
    installed = LAUNCHER.is_file() and os.access(LAUNCHER, os.X_OK)
    status["installed"] = installed
    status["loggedIn"] = (DATA_DIR / "stored-accounts.json.enc").is_file() or (DATA_DIR / "granola.db").is_file()
    status["version"] = read_version()
    pids = granola_main_pids()
    status["pids"] = pids
    status["pid"] = pids[0] if pids else 0
    status["running"] = bool(pids)
    windows = granola_windows()
    status["hasWindow"] = bool(windows)
    events, _recording_hint = calendar_snapshot()
    capturing = pulse_recording(pids) if pids else False
    # A leftover Electron process or a note created in the last few minutes
    # is not a recording. Only show it when the window is up and Pulse has
    # an active (uncorked) capture from Granola.
    status["recording"] = bool(pids) and bool(windows) and capturing
    now = datetime.now(timezone.utc)
    published = [item for item in (public_event(event, now) for event in events) if item]
    happening = [item for item in published if item.get("happening")]
    later = [item for item in published if not item.get("happening")]
    now_event = happening[0] if happening else None
    status["nowEvent"] = now_event
    status["nextEvent"] = now_event or (later[0] if later else None)
    status["upcoming"] = (later if now_event else later[1:])[:5]
    event = status["nextEvent"]
    app_ver, latest_ver, update = update_info()
    status["appVersion"] = app_ver
    status["latestVersion"] = latest_ver
    status["updateAvailable"] = update
    if not installed:
        status["kind"] = "missing"
        status["statusText"] = "Not installed"
    elif status["recording"]:
        status["kind"] = "recording"
        status["statusText"] = "Recording"
    elif event:
        status["kind"] = "upcoming" if status["running"] else "idle"
        status["statusText"] = event["title"]
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


def parse_version(value: str) -> tuple[int, ...]:
    parts = []
    for item in str(value or "").split("."):
        if not item.isdigit():
            break
        parts.append(int(item))
    return tuple(parts)


def installed_app_version() -> str:
    path = INSTALL_DIR / "granola-app-version"
    try:
        return path.read_text(encoding="utf-8").strip().splitlines()[0]
    except OSError:
        return ""


def fetch_latest_version() -> str:
    try:
        req = urllib.request.Request(
            "https://api.granola.ai/v1/download-latest",
            method="HEAD",
            headers={"User-Agent": "ilyesm.granola"},
        )
        with urllib.request.urlopen(req, timeout=2) as response:
            location = response.geturl()
    except Exception:
        return ""
    name = location.rsplit("/", 1)[-1]
    if name.startswith("Granola-") and "-mac" in name:
        return name[len("Granola-"):].split("-mac", 1)[0]
    return ""


def cached_latest() -> str | None:
    try:
        age = datetime.now(timezone.utc).timestamp() - LATEST_CACHE.stat().st_mtime
        if age > LATEST_CACHE_TTL_SEC:
            return None
        data = json.loads(LATEST_CACHE.read_text(encoding="utf-8"))
        return str(data.get("version") or "")
    except (OSError, json.JSONDecodeError):
        return None


def store_latest(version: str) -> None:
    try:
        LATEST_CACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = LATEST_CACHE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps({"version": version}), encoding="utf-8")
        tmp.chmod(0o600)
        tmp.replace(LATEST_CACHE)
    except OSError:
        pass


def update_info() -> tuple[str, str, bool]:
    installed = installed_app_version()
    latest = cached_latest()
    if latest is None:
        latest = fetch_latest_version()
        if latest:
            store_latest(latest)
        else:
            latest = ""
    have = parse_version(installed)
    want = parse_version(latest)
    available = bool(have and want and want > have)
    return installed, latest, available


def run(command: list[str]) -> None:
    subprocess.Popen(
        command,
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
    )


def focus_window() -> None:
    for client in granola_windows():
        address = client.get("address")
        if not address:
            continue
        expr = "hl.dispatch(hl.dsp.focus({ window = 'address:%s' }))" % address
        try:
            subprocess.run(["hyprctl", "eval", expr], check=False, capture_output=True, timeout=2)
            return
        except (OSError, subprocess.TimeoutExpired):
            continue
    if LAUNCHER.is_file():
        run([str(LAUNCHER)])


def start_recording(status: dict) -> dict:
    if not status["installed"]:
        status["ok"] = False
        status["lastError"] = "Granola is not installed"
        return status
    url = "granola://new-document?auto_transcribe=1&creation_source=application_menu"
    run([str(LAUNCHER), url])
    status["statusText"] = "Starting recording…"
    return status


def stop_recording(status: dict) -> dict:
    focus_window()
    status["statusText"] = "Open Granola to stop"
    return status


def open_app(status: dict) -> dict:
    if not status["installed"]:
        status["ok"] = False
        status["lastError"] = "Granola is not installed"
        return status
    if status["running"]:
        focus_window()
        status["statusText"] = "Focused"
        return status
    run([str(LAUNCHER)])
    status["statusText"] = "Opening…"
    return status


def install_app() -> dict:
    script = PLUGIN_DIR / "granola-linux.sh"
    if not script.is_file():
        status = default_status()
        status["ok"] = False
        status["lastError"] = "Installer script is missing"
        return status
    try:
        subprocess.Popen(["xdg-terminal-exec", str(script)], start_new_session=True)
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
    if action in ("record", "start"):
        return dump(start_recording(status))
    if action == "stop":
        return dump(stop_recording(status))
    if action == "open":
        return dump(open_app(status))
    if action in ("install", "update"):
        return dump(install_app())
    if action in ("quit",):
        return dump(quit_app(status))
    status["ok"] = False
    status["lastError"] = f"Unknown action: {action}"
    return dump(status)


if __name__ == "__main__":
    raise SystemExit(main())
