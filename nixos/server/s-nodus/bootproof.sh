#!/usr/bin/env bash
# Prove the s-nodus boot chain reached NixOS stage 0.
#
# One assertion per handoff, read off the SERIAL CONSOLE -- the only channel
# that carries BL2/BL31/U-Boot output, because those run before Linux exists.
#
# WHY THIS EXISTS
# ---------------
# "It boots" has been judged by eye more than once in this project, and that is
# how a card was once reported fixed while three of its four regions were wrong.
# Each stage of this chain prints a unique marker, so each handoff can be an
# assertion instead of an impression:
#
#   1 BootROM -> BL2        "NOTICE:  BL2:"
#   2 BL2 DRAM init         "EMI: ... complex R/W mem test passed"
#   3 BL2 -> BL31           "NOTICE:  BL2: Booting BL31"
#   4 BL31 alive            "NOTICE:  BL31: v"
#   5 BL31 -> U-Boot        "U-Boot 20xx.xx"
#   6 U-Boot -> loader      "Scanning global bootmeth 'efi" / "Booting /"
#   7 kernel start          "Linux version" / "Booting Linux"
#   8 NixOS stage 0         "systemd[1]: Detected architecture"
#
# RUN IT FROM THE CONSOLE HOST (the machine holding /dev/ttyACM0), against a
# logged transcript, not tmux scrollback: tmux keeps 1999 lines, which is a few
# minutes of this board's log volume, so a boot that hangs loses its own
# evidence before anyone can read it.
#
# USAGE
#   ./bootproof.sh [transcript-file]
#   ./bootproof.sh                     # reads tmux pane from CONSOLE_HOST
#
# Start a log that survives a hang:
#   tio /dev/ttyACM0 -b 115200 | tee -a /var/log/s-nodus-console.log
set -uo pipefail

CONSOLE_HOST=${CONSOLE_HOST:-deadbeef@100.64.0.14}
CONSOLE_SESSION=${CONSOLE_SESSION:-0:0.0}

if [ $# -ge 1 ]; then
  T=$(cat "$1")
else
  T=$(ssh -o BatchMode=yes "$CONSOLE_HOST" \
        "sudo -n tmux capture-pane -p -S -1999 -t $CONSOLE_SESSION" 2>/dev/null) || {
    echo "!! cannot read console from $CONSOLE_HOST" >&2
    echo "   pass a transcript file instead: $0 /var/log/s-nodus-console.log" >&2
    exit 2
  }
fi

[ -n "$T" ] || { echo "!! empty transcript" >&2; exit 2; }

fail=0
chk() {
  if grep -qE "$2" <<<"$T"; then
    printf '  OK   %s\n' "$1"
  else
    printf '  FAIL %s\n' "$1"
    fail=1
  fi
}

echo "s-nodus boot chain:"
chk "1 BootROM -> BL2"       'NOTICE:  BL2:'
chk "2 BL2 DRAM init"        'EMI: (Detected DRAM size|complex R/W mem test passed)'
chk "3 BL2 -> BL31"          'NOTICE:  BL2: Booting BL31'
chk "4 BL31 alive"           'NOTICE:  BL31: v'
chk "5 BL31 -> U-Boot"       'U-Boot 20[0-9]+\.'
chk "6 U-Boot -> loader"     "Scanning global bootmeth 'efi|Booting /\\\\?EFI"
chk "7 kernel start"         'Booting Linux|Linux version'
chk "8 NixOS stage 0"        'systemd\[1\]: (Detected architecture|System hostname)'

# Which BL2 actually ran: OpenWrt's build stamps a date, ours stamps the Nix
# epoch (Jan 1 1980).  Reporting it prevents "vendor preloader" being mistaken
# for "our preloader" again.
printf '\nBL2 identity:\n'
grep -E 'NOTICE:  BL2: (v|Built)' <<<"$T" | sed 's/^/  /' || echo "  (none found)"

if [ "$fail" -ne 0 ]; then
  echo
  echo "chain INCOMPLETE -- see failing handoff above"
fi
exit "$fail"
