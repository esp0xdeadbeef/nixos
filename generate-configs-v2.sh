#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# generate‑configs‑v3.sh  –  rebuild <host>/configuration.nix (+ home.nix)
#
#  • Exits on first real error  (set -euo pipefail)
#  • Skips hosts that have no dir            → “skip: … (missing dir)”
#  • Skips scopes whose seed file is absent  → “skip: … (seed file absent)”
#  • Writes **relative paths that match the old, correct form**
#        • host‑local   →  ./hardware/…
#        • shared tree  →  ../1-general/…
#  • Always strips files matching  build_*  (and any host‑specific extra‑excludes)
#  • Cleans its tempfile automatically
# ---------------------------------------------------------------------------

set -euo pipefail
shopt -s nullglob

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

# ---------------------------------------------------------------------------
# Per‑host additional exclusions (regex OR‑ed by “|”).
# build_ is auto‑added, so you don’t need to repeat it below.
# ---------------------------------------------------------------------------
declare -A NIXOS_EXCLUDES=(
  [l-esp]='llms|is-vm|autologin|mxbuild'
  [l-werk]='is-vm|autologin|usb-firewall.nix'
  [l-x13s]='mxbuild|llms|is-vm|virtualization|not-on-aarch64|/work|/werk|1-custom-packages'
  [s-router-vpn-1]='usb-firewall.nix|virtualization|llms|network|browsers|graphics|pdf|rdp|scripting-languages|darkmode|pentesting|usb-tools|1-custom-packages|services|audio|nix-specific'
  [s-test-vm]='usb-firewall.nix|virtualization|llms|browsers|graphics|pdf|rdp|scripting-languages|pentesting|usb-tools|1-custom-packages|services|audio'
  [s-test-vm-impermanence]='usb-firewall.nix|virtualization|llms|browsers|graphics|pdf|rdp|scripting-languages|pentesting|usb-tools|1-custom-packages|services|audio'
  [s-test-vm-impermanence-2]='usb-firewall.nix|virtualization|llms|browsers|graphics|pdf|rdp|scripting-languages|pentesting|usb-tools|1-custom-packages|services|audio|^(?!.*(nmcli|environment|terminal-optimisers)).*'
  [s-lxc-test]=''
)

CONFIGS=("${!NIXOS_EXCLUDES[@]}")
ALWAYS_EXCLUDE='build_'        # stripped for *every* host

# ---------------------------------------------------------------------------
gen_imports() {
  local scope=$1   # "nixos" | "home-manager"
  local cfg=$2

  # host‑specific extra excludes + mandatory build_
  local extra_excludes="$ALWAYS_EXCLUDE"
  [[ -n ${NIXOS_EXCLUDES[$cfg]} ]] && extra_excludes+="|${NIXOS_EXCLUDES[$cfg]}"

  local base="./${scope}/${cfg}"
  [[ -d $base ]] || { printf 'skip: %s (missing dir)\n' "$base" >&2; return 0; }

  # ---------- seed / target names (and prune file) --------------------------
  local build_file target_file prune_file
  case "$scope" in
    nixos)        build_file="build_configuration.nix"
                  target_file="configuration.nix"
                  prune_file="configuration.nix" ;;
    home-manager) build_file="build_home.nix"
                  target_file="home.nix"
                  prune_file="home.nix" ;;
    *)            echo "Unknown scope $scope" >&2; return 1 ;;
  esac

  [[ -f "${base}/${build_file}" ]] || {
    printf 'skip: %s/%s (seed file absent)\n' "$base" "$build_file" >&2
    return 0
  }

  : >"$tmpfile"   # truncate temp

  # ---------- helper: print relative path in proper form --------------------
  _emit_rel() {
    local file=$1
    local rel
    rel=$(realpath --relative-to="$base" "$file")
    # Prepend "./" for files that live *inside* the host dir
    [[ $rel != ../* ]] && rel="./$rel"
    printf '    %s\n' "$rel" >>"$tmpfile"
  }

  # ---------- 1. host‑specific modules --------------------------------------
  find "$base" \
       \( -path '*/old/*' -o -name "$prune_file" -o -name 'build_*' \) -prune -o \
       -type f -name '*.nix' -print0 |
    while IFS= read -r -d '' f; do _emit_rel "$f"; done

  # ---------- 2. shared modules ---------------------------------------------
  local shared="./${scope}/1-general"
  if [[ -d $shared ]]; then
    find "$shared" -type f -name '*.nix' -print0 |
      while IFS= read -r -d '' f; do _emit_rel "$f"; done
  fi

  # ---------- 3. de‑duplicate + strip excludes ------------------------------
  sort -u "$tmpfile" -o "$tmpfile"
  grep -Ev "(${extra_excludes})" "$tmpfile" > "${tmpfile}.f"
  mv "${tmpfile}.f" "$tmpfile"

  # ---------- 4. patch seed -> final ----------------------------------------
  awk -v r="$(<"$tmpfile")" \
      '{gsub(/STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH/, r)}1' \
      "${base}/${build_file}" > "${base}/${target_file}"
}

# ---------------------------------------------------------------------------
# main – NixOS is mandatory, Home‑Manager only if its seed file exists
# ---------------------------------------------------------------------------
for cfg in "${CONFIGS[@]}"; do
  gen_imports nixos "$cfg"
  gen_imports home-manager "$cfg"   # gen_imports itself will skip hosts w/o seed
done
