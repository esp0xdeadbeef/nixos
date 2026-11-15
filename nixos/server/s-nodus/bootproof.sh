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
# WHERE EACH HALF OF THE EVIDENCE LIVES
# -------------------------------------
# The chain straddles the moment Linux starts, and the two halves are recorded
# in different places:
#
#   handoffs 1-6 (BL2, BL31, U-Boot) print BEFORE a kernel exists, so they are
#   only ever visible on the SERIAL CONSOLE (`ttyACM0` on the console host).
#   Verified: the board's own journal contains zero "NOTICE:  BL2/BL31" lines.
#
#   handoffs 7-8 happen after the kernel is up, so the board's OWN ring buffer
#   and journal have them -- persistently, and without tmux's 1999-line cap.
#
# So the script reads the console for 1-6 and the board's journal for 7-8.
#
# USAGE
#   ./bootproof.sh [transcript-file]
#   ./bootproof.sh                     # console host + board over ssh
#
# The tmux pane is capped at 1999 lines (a few minutes of this board's log
# volume), so for an experiment that may hang, start a durable log first:
#   tio /dev/ttyACM0 -b 115200 | tee -a /var/log/s-nodus-console.log
# and pass that file:  ./bootproof.sh /var/log/s-nodus-console.log
set -uo pipefail

CONSOLE_HOST=${CONSOLE_HOST:-deadbeef@100.64.0.14}
CONSOLE_SESSION=${CONSOLE_SESSION:-0:0.0}
BOARD=${BOARD:-deadbeef@100.64.0.18}

# Firmware half (1-6): serial console only.
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

# Linux half (7-8): the board's own journal, which starts at "Booting Linux".
J=$(ssh -o BatchMode=yes "$BOARD" "sudo -n journalctl -b --no-pager -o short 2>/dev/null" 2>/dev/null)
[ -n "$J" ] || echo "!! cannot read the board journal from $BOARD (7-8 will fail)" >&2

fail=0
# chk <name> <pattern> [source]; source defaults to the console transcript.
chk() {
  local src=${3:-T}
  if [ "$src" = "J" ]; then src=$J; else src=$T; fi
  if grep -qE "$2" <<<"$src"; then
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
chk "7 kernel start"         'Booting Linux|Linux version'                  J
chk "8 NixOS stage 0"        'systemd\[1\]: (Detected architecture|System hostname)' J

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
