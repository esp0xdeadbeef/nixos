{ bashInteractive
, buildFHSEnv
, coreutils
, curl
, dbus
, dmidecode
, expat
, fetchurl
, file
, findutils
, fontconfig
, freetype
, gawk
, gcc
, glib
, gpgme
, gtk3
, ipmitool
, lib
, libGL
, libdrm
, libuuid
, libxkbcommon
, lshw
, ncurses
, nss
, pciutils
, rsync
, smartmontools
, usbutils
, util-linux
, which
, writeShellApplication
, xauth
, zlib
, zstd
, libice
, libsm
, libx11
, libxscrnsaver
, libxau
, libxcomposite
, libxcursor
, libxdamage
, libxdmcp
, libxext
, libxfixes
, libxi
, libxinerama
, libxrandr
, libxrender
, libxtst
, libxcb
, libxml2
, libxml2_13
}:

let
  isoUrl = "https://dl.dell.com/FOLDER14030849M/1/SUU_980-x64-LIN-7.ISO";
  isoName = "SUU_980-x64-LIN-7.ISO";
  isoSha256 = "e97d46586b519e5f72cf77cde883474dbe4e5bb7abaae8bb023067411750f525";

  gpgmeCompat = gpgme.overrideAttrs (_old: {
    version = "1.24.3";

    src = fetchurl {
      url = "mirror://gnupg/gpgme/gpgme-1.24.3.tar.bz2";
      hash = "sha256-v8F/W9GxeMhkn92RiVbSdwgPM98Aai3ECs3s3OaMUN0=";
    };

    patches = [ ];
    doCheck = false;
    passthru = { };
  });

  fhsRunner = writeShellApplication {
    name = "dell-suu-fhs-run";

    runtimeInputs = [
      bashInteractive
      coreutils
      findutils
    ];

    text = ''
      usage() {
        cat <<'USAGE'
      usage: dell-suu-fhs-run <mounted-suu-source> [--gui | --cli | --shell | --launcher PATH] [-- ARGS...]

      Runs the official Dell Server Update Utility from an already mounted SUU
      ISO/source inside an FHS runtime.
      USAGE
      }

      if [ "$#" -lt 1 ]; then
        usage >&2
        exit 64
      fi

      source_dir=$1
      shift
      launcher=
      mode=cli
      shell=0
      args=()

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --cli)
            mode=cli
            shift
            ;;
          --gui)
            mode=gui
            shift
            ;;
          --shell)
            shell=1
            shift
            ;;
          --launcher)
            if [ "$#" -lt 2 ]; then
              echo "dell-suu: --launcher needs a path" >&2
              exit 64
            fi
            launcher=$2
            shift 2
            ;;
          --help|-h)
            usage
            exit 0
            ;;
          --)
            shift
            args+=("$@")
            break
            ;;
          *)
            args+=("$1")
            shift
            ;;
        esac
      done

      cd "$source_dir"
      export SUUDIR="$source_dir"
      export LD_LIBRARY_PATH="$source_dir''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

      cleanup_stale_suulauncher_lock() {
        local lock_file lock_pid lock_user

        lock_user=$(id -un 2>/dev/null || printf root)
        lock_file="''${HOME:-/root}/suulauncher-$lock_user"

        if [ ! -e "$lock_file" ]; then
          return 0
        fi

        lock_pid=$(tr -cd '0-9' < "$lock_file" || true)
        if [ -n "$lock_pid" ] && [ -d "/proc/$lock_pid" ]; then
          return 0
        fi

        rm -f "$lock_file"
      }

      if [ "$shell" -eq 1 ]; then
        exec ${bashInteractive}/bin/bash
      fi

      if [ -n "$launcher" ]; then
        exec "$launcher" "''${args[@]}"
      fi

      if [ "$mode" = gui ]; then
        cleanup_stale_suulauncher_lock

        if [ -x ./suulauncher ]; then
          exec ./suulauncher "''${args[@]}"
        fi

        echo "dell-suu: no executable ./suulauncher found below $source_dir" >&2
        exit 66
      fi

      for candidate in ./suu ./internalsuu ./suulauncher; do
        if [ -x "$candidate" ]; then
          exec "$candidate" "''${args[@]}"
        fi
      done

      found=$(find . -maxdepth 3 -type f \( -name suu -o -name internalsuu -o -name suulauncher \) -perm -0100 -print -quit)
      if [ -n "$found" ]; then
        exec "$found" "''${args[@]}"
      fi

      echo "dell-suu: no SUU launcher found below $source_dir" >&2
      echo "dell-suu: use --shell to inspect the mounted source manually" >&2
      exit 66
    '';
  };

  fhs = buildFHSEnv {
    name = "dell-suu-fhs";
    runScript = "${fhsRunner}/bin/dell-suu-fhs-run";
    includeClosures = true;

    targetPkgs = _pkgs: [
      bashInteractive
      coreutils
      curl
      dbus
      dmidecode
      expat
      file
      findutils
      fontconfig
      freetype
      gawk
      gcc.cc.lib
      glib
      gpgmeCompat
      gtk3
      ipmitool
      libGL
      libdrm
      libuuid
      libxkbcommon
      lshw
      ncurses
      nss
      pciutils
      smartmontools
      usbutils
      util-linux
      which
      xauth
      zlib
      zstd
      libice
      libsm
      libx11
      libxscrnsaver
      libxau
      libxcomposite
      libxcursor
      libxdamage
      libxdmcp
      libxext
      libxfixes
      libxi
      libxinerama
      libxrandr
      libxrender
      libxtst
      libxcb
      libxml2
      libxml2_13
    ];

    extraPreBwrapCmds = ''
      mkdir -p /var/cache/dell/dell_dup/suu
    '';

    extraBuildCommands = ''
      mkdir -p "$out/usr/libexec/dell_dup"
      touch "$out/usr/libexec/dell_dup/.keep"
    '';

    extraBwrapArgs = [
      "--bind /var/cache/dell/dell_dup/suu /usr/libexec/dell_dup"
    ];
  };
in
writeShellApplication {
  name = "dell-suu";

  runtimeInputs = [
    coreutils
    curl
    findutils
    rsync
    util-linux
  ];

  text = ''
    set -euo pipefail

    usage() {
      cat <<'USAGE'
    usage: dell-suu [--iso PATH | --source PATH | --download] [--cache-source] [--cache-dir PATH] [--gui | --cli] [--shell] [--launcher PATH] [-- ARGS...]

    Mounts an official Dell Server Update Utility Linux ISO and launches the
    Dell-provided SUU updater inside an FHS runtime. Without --iso or --source it
    first uses a cached source under /var/cache/dell/suu/source, then searches
    for the newest SUU_*-x64-LIN-*.ISO in the current user's Downloads directory.

    examples:
      dell-suu --download
      sudo dell-suu --iso ~/Downloads/SUU_980-x64-LIN-7.ISO
      sudo dell-suu --iso ~/Downloads/SUU_980-x64-LIN-7.ISO -- --help
      sudo dell-suu --iso ~/Downloads/SUU_980-x64-LIN-7.ISO --cache-source
      sudo dell-suu --gui
      sudo dell-suu --iso ~/Downloads/SUU_980-x64-LIN-7.ISO --gui
      sudo dell-suu --source /mnt/suu
      sudo dell-suu --iso ~/Downloads/SUU_980-x64-LIN-7.ISO --shell
    USAGE
    }

    iso=
    source_dir=
    launcher=
    mode=cli
    shell=0
    download=0
    cache_source=0
    explicit_run=0
    cache_root="''${DELL_FIRMWARE_CACHE_DIR:-/var/cache/dell}"
    args=()

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --iso)
          if [ "$#" -lt 2 ]; then
            echo "dell-suu: --iso needs a path" >&2
            exit 64
          fi
          iso=$2
          shift 2
          ;;
        --source|--mount)
          if [ "$#" -lt 2 ]; then
            echo "dell-suu: --source needs a path" >&2
            exit 64
          fi
          source_dir=$2
          shift 2
          ;;
        --download)
          download=1
          shift
          ;;
        --cache-source)
          cache_source=1
          shift
          ;;
        --cache-dir)
          if [ "$#" -lt 2 ]; then
            echo "dell-suu: --cache-dir needs a path" >&2
            exit 64
          fi
          cache_root=$2
          shift 2
          ;;
        --launcher)
          if [ "$#" -lt 2 ]; then
            echo "dell-suu: --launcher needs a path" >&2
            exit 64
          fi
          launcher=$2
          explicit_run=1
          shift 2
          ;;
        --cli)
          mode=cli
          explicit_run=1
          shift
          ;;
        --gui)
          mode=gui
          explicit_run=1
          shift
          ;;
        --shell)
          shell=1
          explicit_run=1
          shift
          ;;
        --help|-h)
          usage
          exit 0
          ;;
        --)
          shift
          args+=("$@")
          if [ "$#" -gt 0 ]; then
            explicit_run=1
          fi
          break
          ;;
        *)
          args+=("$1")
          explicit_run=1
          shift
          ;;
      esac
    done

    download_iso() {
      local target_dir target
      target_dir="''${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
      target="$target_dir/${isoName}"
      mkdir -p "$target_dir"

      curl \
        --location \
        --continue-at - \
        --fail \
        --show-error \
        --progress-bar \
        --user-agent 'Mozilla/5.0' \
        --referer 'https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=2w9tp' \
        --output "$target" \
        '${isoUrl}'

      actual=$(sha256sum "$target" | awk '{print $1}')
      if [ "$actual" != '${isoSha256}' ]; then
        echo "dell-suu: SHA-256 mismatch for $target" >&2
        echo "expected: ${isoSha256}" >&2
        echo "actual:   $actual" >&2
        exit 65
      fi

      printf '%s\n' "$target"
    }

    find_latest_iso() {
      shopt -s nullglob
      local latest=
      local dirs=()

      if [ -n "''${SUDO_USER:-}" ] && [ "''${SUDO_USER:-}" != "root" ]; then
        dirs+=("/home/$SUDO_USER/Downloads")
      fi

      dirs+=("$HOME/Downloads" "$PWD")

      for dir in "''${dirs[@]}"; do
        for candidate in "$dir"/SUU_*-x64-LIN-*.ISO "$dir"/SUU_*.ISO; do
          if [ -z "$latest" ] || [ "$candidate" -nt "$latest" ]; then
            latest=$candidate
          fi
        done
      done

      printf '%s\n' "$latest"
    }

    cached_source_dir() {
      printf '%s\n' "$cache_root/suu/source"
    }

    is_suu_source() {
      local dir=$1
      [ -d "$dir" ] && [ -x "$dir/suulauncher" ] && [ -x "$dir/internalsuu" ]
    }

    cache_suu_source() {
      local src target
      src=$1
      target=$(cached_source_dir)

      if ! is_suu_source "$src"; then
        echo "dell-suu: source does not look like a SUU source: $src" >&2
        exit 66
      fi

      mkdir -p "$target"
      rsync -a --delete "$src"/ "$target"/

      if ! is_suu_source "$target"; then
        echo "dell-suu: cached source is incomplete: $target" >&2
        exit 66
      fi

      echo "dell-suu: cached SUU source in $target"
    }

    if [ "$download" -eq 1 ]; then
      downloaded=$(download_iso)
      if [ -z "$iso" ] && [ -z "$source_dir" ]; then
        echo "dell-suu: downloaded $downloaded"
        exit 0
      fi
      iso=$downloaded
    fi

    if [ -n "$iso" ] && [ -n "$source_dir" ]; then
      echo "dell-suu: use either --iso or --source, not both" >&2
      exit 64
    fi

    if [ -z "$iso" ] && [ -z "$source_dir" ]; then
      cached_source=$(cached_source_dir)
      if is_suu_source "$cached_source"; then
        source_dir=$cached_source
      else
        iso=$(find_latest_iso)
      fi
    fi

    cleanup_mount() {
      if [ -n "''${mounted_dir:-}" ]; then
        umount "$mounted_dir" || true
        rmdir "$mounted_dir" || true
      fi
    }

    if [ -n "$iso" ]; then
      if [ "$(id -u)" -ne 0 ]; then
        echo "dell-suu: mounting the SUU ISO needs root; run with sudo" >&2
        exit 77
      fi

      if [ ! -f "$iso" ]; then
        echo "dell-suu: ISO not found: $iso" >&2
        echo "dell-suu: run 'dell-suu --download' first, or pass --iso PATH" >&2
        exit 66
      fi

      mounted_dir=$(mktemp -d /tmp/dell-suu.XXXXXX)
      trap cleanup_mount EXIT
      mount -o loop,ro "$iso" "$mounted_dir"
      source_dir=$mounted_dir
    fi

    if [ -z "$source_dir" ]; then
      echo "dell-suu: no SUU ISO found; pass --iso PATH or --source PATH" >&2
      exit 66
    fi

    if [ ! -d "$source_dir" ]; then
      echo "dell-suu: source path is not a directory: $source_dir" >&2
      exit 66
    fi

    if [ "$cache_source" -eq 1 ]; then
      cache_suu_source "$source_dir"
      source_dir=$(cached_source_dir)

      if [ "$explicit_run" -eq 0 ]; then
        exit 0
      fi
    fi

    fhs_args=("$source_dir" "--$mode")

    if [ "$shell" -eq 1 ]; then
      fhs_args+=(--shell)
    fi

    if [ -n "$launcher" ]; then
      fhs_args+=(--launcher "$launcher")
    fi

    if [ "''${#args[@]}" -gt 0 ]; then
      fhs_args+=(-- "''${args[@]}")
    fi

    exec ${fhs}/bin/dell-suu-fhs "''${fhs_args[@]}"
  '';

  meta = {
    description = "Run Dell Server Update Utility from an official SUU ISO on NixOS";
    homepage = "https://www.dell.com/support/kbdoc/en-us/000123359/dell-emc-server-update-utility-suu-guide-and-download";
    license = lib.licenses.unfree;
    mainProgram = "dell-suu";
    platforms = [ "x86_64-linux" ];
  };
}
