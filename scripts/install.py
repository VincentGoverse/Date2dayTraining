#!/usr/bin/env python3
"""Install Date Weekday Quiz and its own login LaunchAgent; preserve backups."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time

LABEL = "com.vincentgoverse.dateweekdayquiz"
APP_NAME = "Date Weekday Quiz.app"


def read_plist(path: Path) -> dict:
    with path.open("rb") as stream:
        return plistlib.load(stream)


def launch_agent(app: Path, home: Path) -> dict:
    return {
        "Label": LABEL,
        # LaunchServices avoids duplicate app processes from an existing Login Item.
        "ProgramArguments": ["/usr/bin/open", "-gj", str(app)],
        "RunAtLoad": True,
        "LimitLoadToSessionType": ["Aqua"],
        "ProcessType": "Interactive",
        "AssociatedBundleIdentifiers": [LABEL],
        "StandardOutPath": str(home / "Library/Logs/Date Weekday Quiz.launcher.log"),
        "StandardErrorPath": str(home / "Library/Logs/Date Weekday Quiz.launcher.log"),
    }


def stop_app(app: Path) -> None:
    """Stop only processes running the exact executable being replaced."""
    executable = str(app / "Contents/MacOS/applet")
    result = subprocess.run(
        ["/bin/ps", "-axo", "pid=,comm="], text=True, capture_output=True, check=True
    )
    pids = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and fields[1] == executable:
            pids.append(int(fields[0]))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 5
    while pids and time.monotonic() < deadline:
        still_running = []
        for pid in pids:
            try:
                os.kill(pid, 0)
                still_running.append(pid)
            except ProcessLookupError:
                pass
        pids = still_running
        if pids:
            time.sleep(0.1)
    if pids:
        raise RuntimeError("The existing quiz did not quit. Quit it and run the installer again.")


def run_launchctl(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["/bin/launchctl", *args], text=True, capture_output=True, check=check
    )


def verify_staged_app(app: Path) -> None:
    """Remove copied Finder metadata from the new bundle, then verify its seal."""
    # Never follow a link out of this freshly copied bundle, or touch the source
    # app or the existing installation. File Providers can add FinderInfo to .app
    # folders under Documents even when the compiled script has not changed.
    # xattr -s acts on symlinks themselves; -r skips absent attributes. Use the
    # macOS utility because Apple's bundled Python does not expose os.listxattr.
    for attribute in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
        subprocess.run(
            ["/usr/bin/xattr", "-drs", attribute, str(app)],
            text=True, capture_output=True, check=True,
        )
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--strict", str(app)],
        text=True, capture_output=True, check=True,
    )


def install(args: argparse.Namespace) -> None:
    source = args.app.expanduser().resolve()
    mock_home = args.stage.expanduser().resolve() if args.stage else None
    user_home = mock_home or Path.home()
    destination = (
        args.destination.expanduser().resolve()
        if args.destination else user_home / "Applications" / APP_NAME
    )
    agent_path = user_home / "Library/LaunchAgents" / f"{LABEL}.plist"
    app_info = source / "Contents/Info.plist"
    if not app_info.is_file() or not (source / "Contents/MacOS/applet").is_file():
        raise RuntimeError(f"Built app not found: {source}")
    info = read_plist(app_info)
    if info.get("CFBundleIdentifier") != LABEL or not info.get("OSAAppletStayOpen"):
        raise RuntimeError("Use scripts/build.sh to build the stay-open app before installing.")
    if source == destination:
        raise RuntimeError("Build source and install destination must be different.")
    if destination.suffix != ".app":
        raise RuntimeError("Install destination must end in .app.")
    if destination.exists():
        previous = read_plist(destination / "Contents/Info.plist")
        if previous.get("CFBundleName") != "Date Weekday Quiz":
            raise RuntimeError(f"Refusing to replace an unrelated app at {destination}")
    if agent_path.exists() and read_plist(agent_path).get("Label") != LABEL:
        raise RuntimeError(f"Refusing to replace an unrelated LaunchAgent at {agent_path}")

    plan = {
        "source": str(source),
        "install_app": str(destination),
        "login_launch_agent": str(agent_path),
        "launch_command": launch_agent(destination, user_home)["ProgramArguments"],
        "start_now": not (args.no_start or mock_home),
        "preserve_existing_login_items": True,
        "mode": "dry run" if args.dry_run else "staging only" if mock_home else "install",
    }
    print(json.dumps(plan, indent=2))
    if args.dry_run:
        return

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup_dir = user_home / "Library/Application Support/Date Weekday Quiz/Backups" / timestamp
    destination.parent.mkdir(parents=True, exist_ok=True)
    agent_path.parent.mkdir(parents=True, exist_ok=True)
    (user_home / "Library/Logs").mkdir(parents=True, exist_ok=True)
    backup_dir.mkdir(parents=True)
    had_app = destination.exists()
    had_agent = agent_path.exists()
    if had_app:
        shutil.copytree(destination, backup_dir / APP_NAME)
    if had_agent:
        shutil.copy2(agent_path, backup_dir / agent_path.name)

    # Fully copy the new bundle before stopping the old process or changing files.
    staging_dir = Path(tempfile.mkdtemp(prefix=".date-weekday-quiz-install-", dir=destination.parent))
    staged_app = staging_dir / APP_NAME
    displaced_app = staging_dir / "previous.app"
    service = f"gui/{os.getuid()}/{LABEL}"
    domain = f"gui/{os.getuid()}"
    changed_app = False
    agent_changed = False
    service_stopped = False
    try:
        shutil.copytree(source, staged_app)
        verify_staged_app(staged_app)
        if not mock_home:
            run_launchctl("bootout", service, check=False)
            service_stopped = True
            stop_app(destination)
        if had_app:
            destination.rename(displaced_app)
        staged_app.rename(destination)
        changed_app = True
        staged_plist = agent_path.with_name(f".{agent_path.name}.{timestamp}")
        with staged_plist.open("wb") as stream:
            plistlib.dump(launch_agent(destination, user_home), stream)
        staged_plist.chmod(0o644)
        staged_plist.replace(agent_path)
        agent_changed = True
        if not mock_home and not args.no_start:
            run_launchctl("bootstrap", domain, str(agent_path))
        print(f"Installed: {destination}")
        print(f"Backup: {backup_dir}")
        if mock_home:
            print("Staging complete. No processes or login services were changed.")
        elif args.no_start:
            print("Installed for the next login; the quiz is currently stopped.")
        else:
            print("Login launch registered and app launch requested.")
    except Exception:
        if changed_app:
            shutil.rmtree(destination)
        if displaced_app.exists():
            displaced_app.rename(destination)
        if agent_changed:
            if had_agent:
                shutil.copy2(backup_dir / agent_path.name, agent_path)
            elif agent_path.exists():
                agent_path.unlink()
        if not mock_home and had_agent and service_stopped:
            run_launchctl("bootstrap", domain, str(agent_path), check=False)
        raise
    finally:
        shutil.rmtree(staging_dir, ignore_errors=True)


def main() -> int:
    project = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=project / "build" / APP_NAME)
    parser.add_argument("--destination", type=Path, help="Override the installed .app path.")
    parser.add_argument("--dry-run", action="store_true", help="Print the plan without writing or stopping anything.")
    parser.add_argument("--stage", type=Path, help="Install to a mock home directory without starting or stopping processes.")
    parser.add_argument("--no-start", action="store_true", help="Install for the next login without starting the app now.")
    args = parser.parse_args()
    if args.stage and args.destination:
        parser.error("--stage and --destination cannot be combined")
    try:
        install(args)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Install failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.strip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
