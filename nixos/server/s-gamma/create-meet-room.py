#!/usr/bin/env python3
"""Create a new Galene meeting room and write its groups/<uuid>.json + .ics.

The admin username and its hashed password are read from SOPS-managed runtime
files (paths via environment), never committed to the repository. Room name is
a fresh UUID. An iCalendar (.ics) event is written alongside so the meeting
can be imported / invited to calendar clients.

Usage examples
    meet-create-room --title "Kickoff" --date "2026-09-21" --duration "full day"
    meet-create-room --title "Review" --date "2026-09-21 15:00" --duration "1 hour"
    meet-create-room --title "Planning" --date "2026-10-01" --duration "2 weeks"

A start without an explicit timezone is Dutch local time (Europe/Amsterdam)
and is converted to UTC in the generated .ics.
"""
import argparse
import json
import os
import re
import sys
import uuid
import datetime as _dt
from zoneinfo import ZoneInfo


LOCAL_TZ = ZoneInfo("Europe/Amsterdam")


DURATION_RE = re.compile(
    r"^(?:(?P<num>\d+(?:\.\d+)?)\s*)?(?P<unit>seconds?|mins?|minutes?|hours?|days?|weeks?|months?)$",
    re.IGNORECASE,
)


UNIT_SECONDS = {
    "second": 1,
    "minute": 60,
    "hour": 3600,
    "day": 86400,
    "week": 604800,
    "month": 2592000,
}


def parse_human_duration(s: str) -> int:
    """Parse '1 hour', '90 minutes', '2 weeks', 'full day' -> seconds."""
    s = s.strip().lower()
    if re.fullmatch(r"full\s*days?", s):
        return int(UNIT_SECONDS["day"])
    m = DURATION_RE.match(s)
    if not m:
        raise ValueError(f"could not parse duration: '{s}'")
    gd = m.groupdict()
    num_str = gd["num"]
    num = float(num_str) if num_str else 1.0
    unit = gd["unit"].rstrip("s")  # normalize plurals
    if unit == "month":
        raise ValueError("duration in months is ambiguous; use days/weeks")
    secs = int(num * UNIT_SECONDS[unit])
    if secs <= 0:
        raise ValueError(f"duration must be positive: '{s}'")
    return secs


def parse_start(s: str) -> _dt.datetime:
    """Parse a start time, interpreted as Dutch local time.

    Naive input is taken as Europe/Amsterdam local time, so `--date
    "2026-09-21 15:00"` means 15:00 in the Netherlands (CEST/CET as
    appropriate), not 15:00 UTC. An explicit UTC/offset form
    (`...Z`, `...+02:00`) is respected as given.
    """
    s = s.strip()
    # Full-day date only (no time component)
    try:
        dt = _dt.datetime.strptime(s, "%Y-%m-%d")
        return dt.replace(tzinfo=LOCAL_TZ)
    except ValueError:
        pass
    # space-separated date + time (local time)
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S"):
        try:
            dt = _dt.datetime.strptime(s, fmt)
            return dt.replace(tzinfo=LOCAL_TZ)
        except ValueError:
            pass
    # ISO date/time (handles trailing Z and explicit offsets)
    if s.endswith(("Z", "z")):
        s = s[:-1] + "+00:00"
    try:
        dt = _dt.datetime.fromisoformat(s)
    except ValueError:
        raise ValueError(f"could not parse meeting date: '{s}'")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=LOCAL_TZ)
    return dt


ALL_DAY = "FULL_DAY"


def is_all_day(dt: _dt.datetime) -> bool:
    return getattr(dt, "_allday", False)


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
        "--title",
        required=True,
        help="Meeting title (required); used as the calendar SUMMARY.",
    )
    ap.add_argument(
        "--date",
        required=True,
        help="Meeting start date; a bare date '2026-09-21' is a full-day "
             "meeting starting 00:00 Europe/Amsterdam, or give a time in "
             "Dutch local time '2026-09-21 15:00' (or an explicit UTC/offset "
             "form '2026-09-21T15:00:00Z').",
    )
    ap.add_argument(
        "--duration",
        required=True,
        help="Meeting length as natural text, e.g. '1 hour', '90 minutes', "
             "'2 hours', 'full day', '2 weeks'. Room closes at start + this.",
    )
    args = ap.parse_args()

    try:
        meeting_start = parse_start(args.date)
    except ValueError as e:
        ap.error(str(e))
    try:
        duration_secs = parse_human_duration(args.duration)
    except ValueError as e:
        ap.error(str(e))

    title = args.title.strip()
    if not title:
        ap.error("--title must not be empty")

    start = meeting_start.astimezone(_dt.timezone.utc)
    expires = start + _dt.timedelta(seconds=duration_secs)
    local_end = expires.astimezone(LOCAL_TZ)

    hostname = os.environ.get("MEET_HOSTNAME") or "meet"
    admin_user = os.environ.get("MEET_ADMIN_USERNAME") or ""
    groups_dir = os.environ["MEET_GROUPS_DIR"]
    hash_file = os.environ.get("MEET_ADMIN_HASH_FILE") or ""

    with open(hash_file) as f:
        admin_hash = json.load(f)  # pbkdf2 password object

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
        # No "not-before": the room is joinable as soon as it exists, so
        # people who get the link early can join/test ahead of the invite.
        "allow-recording": True,
        "expires": fmt_rfc3339(expires),
    }

    json_path = os.path.join(groups_dir, f"{room}.json")
    with open(json_path, "w") as f:
        json.dump(description, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.chmod(json_path, 0o640)
    set_owner(json_path, "galene")

    now = _dt.datetime.now(_dt.timezone.utc)
    meet_url = f"https://{hostname}/group/{room}/"
    desc_lines = [
        title,
        f"When: {meeting_start.strftime('%A %d %B %Y')} "
        f"{meeting_start:%H:%M}-{local_end:%H:%M} {meeting_start.tzname()} "
        f"({start:%H:%M}-{expires:%H:%M} UTC)",
        "",
        f"Join the meeting: {meet_url}",
        "",
        "Everyone can join with the link and any display name (no login).",
        "The room is open from now until the meeting end time.",
    ]
    description_txt = "\n".join(desc_lines)

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
            f"SUMMARY:{escape_ics(title)}",
            f"DESCRIPTION:{escape_ics(description_txt)}",
            f"LOCATION:{meet_url}",
            f"URL:{meet_url}",
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
    print(f"title:   {title}")
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
