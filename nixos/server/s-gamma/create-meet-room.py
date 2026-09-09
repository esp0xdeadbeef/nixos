#!/usr/bin/env python3
"""Create a new Galene meeting room and write its groups/<uuid>.json + .ics.

The admin username and its hashed password are read from SOPS-managed runtime
files (paths via environment), never committed to the repository. Room name is
a fresh UUID. An iCalendar (.ics) event is written alongside so the meeting
can be imported / invited to calendar clients.

Usage examples
    meet-create-room --start '2026-09-21 14:00' --subject 'Uitleg'
    meet-create-room --start '2026-09-21T14:00:00Z' --duration 5400
    meet-create-room --subject 'Vandaag'                 # from now, 1 week
"""
import argparse
import json
import os
import sys
import uuid
import datetime as _dt


def parse_dt(s: str) -> _dt.datetime:
    """Parse a naive or UTC/Z datetime string into an aware UTC datetime."""
    s = s.strip()
    if s.endswith(("Z", "z")):
        s = s[:-1] + "+00:00"
    dt = _dt.datetime.fromisoformat(s)
    if dt.tzinfo is None:
        # Interpret a bare wall-clock time as UTC (the host runs in UTC).
        dt = dt.replace(tzinfo=_dt.timezone.utc)
    return dt.astimezone(_dt.timezone.utc)


def fmt_ics(dt: _dt.datetime) -> str:
    return dt.strftime("%Y%m%dT%H%M%SZ")


def fmt_rfc3339(dt: _dt.datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def escape_ics(value: str) -> str:
    return (
        value
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )


def main() -> int:
    ap = argparse.ArgumentParser(prog="meet-create-room")
    ap.add_argument(
        "--start",
        help="Meeting start, ISO-8601, e.g. '2026-09-21 14:00' or "
             "'2026-09-21T14:00:00Z'. If omitted the room is usable now.",
    )
    ap.add_argument(
        "--subject",
        default=os.environ.get("MEET_ROOM_SUBJECT", ""),
        help="Invite/SUMMARY text (default empty).",
    )
    ap.add_argument(
        "--duration",
        type=int,
        default=int(os.environ.get("MEET_ROOM_DURATION", "3600")),
        help="Meeting length in seconds (default 3600). Close = start + duration.",
    )
    ap.add_argument(
        "--ttl",
        type=int,
        default=int(os.environ.get("MEET_ROOM_TTL", "604800")),
        help="Seconds from now the room stays open when no --start is given "
             "(default 604800 = 1 week).",
    )
    args = ap.parse_args()

    hostname = os.environ.get("MEET_HOSTNAME") or "meet"
    admin_user = os.environ.get("MEET_ADMIN_USERNAME") or ""
    groups_dir = os.environ["MEET_GROUPS_DIR"]
    hash_file = os.environ.get("MEET_ADMIN_HASH_FILE") or ""

    with open(hash_file) as f:
        admin_hash = json.load(f)  # pbkdf2 password object

    now = _dt.datetime.now(_dt.timezone.utc)
    start = now
    expires = now
    if args.start:
        start = parse_dt(args.start)
        expires = start + _dt.timedelta(seconds=args.duration)
    else:
        expires = start + _dt.timedelta(seconds=args.ttl)

    if not admin_user:
        with open(os.path.join("/run/secrets", "meet", "admin_username")) as f:
            admin_user = f.read().strip()

    room = uuid.uuid4().hex  # 32 hex chars, filesystem safe
    if not room:
        print("failed to generate room name", file=sys.stderr)
        return 1

    os.makedirs(groups_dir, mode=0o750, exist_ok=True)

    description = {
        "users": {
            admin_user: {
                "password": admin_hash,
                "permissions": "op",
            }
        },
        "wildcard-user": {
            "password": {"type": "wildcard"},
            "permissions": "present",
        },
        "allow-recording": True,
        "not-before": fmt_rfc3339(start),
        "expires": fmt_rfc3339(expires),
    }

    json_path = os.path.join(groups_dir, f"{room}.json")
    with open(json_path, "w") as f:
        json.dump(description, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.chmod(json_path, 0o640)
    set_owner(json_path, "galene")

    meet_url = f"https://{hostname}/group/{room}/"

    # iCalendar (.ics) event: start..expires, URL in LOCATION.
    ics = "\r\n".join(
        [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            f"PRODID:-//{hostname}//s-gamma meet//EN",
            "BEGIN:VEVENT",
            f"UID:{room}@{hostname}",
            f"DTSTAMP:{fmt_ics(now)}",
            f"DTSTART:{fmt_ics(start)}",
            f"DTEND:{fmt_ics(expires)}",
            f"SUMMARY:{escape_ics(args.subject or 'Online meeting')}",
            f"DESCRIPTION:Join the meeting: {meet_url}",
            f"LOCATION:{meet_url}",
            "END:VEVENT",
            "END:VCALENDAR",
            "",
        ]
    )
    ics_path = os.path.join(groups_dir, f"{room}.ics")
    with open(ics_path, "w", newline="") as f:
        f.write(ics)
    os.chmod(ics_path, 0o644)

    print(f"room:    {room}")
    print(f"url:     {meet_url}")
    print(f"start:   {fmt_rfc3339(start)}")
    print(f"expires: {fmt_rfc3339(expires)}")
    print(f"ics:     {ics_path}")
    return 0


def set_owner(path: str, user: str) -> None:
    try:
        import grp
        import pwd

        uid = pwd.getpwnam(user).pw_uid
        gid = grp.getgrnam(user).gr_gid
        os.chown(path, uid, gid)
    except (KeyError, ImportError):
        # Running outside the target host; ownership is set at activation.
        pass


if __name__ == "__main__":
    sys.exit(main())
