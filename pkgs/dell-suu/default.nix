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
, jq
, lib
, libGL
, libdrm
, libuuid
, libxkbcommon
, lshw
, makeDesktopItem
, ncurses
, nss
, pciutils
, rsync
, smartmontools
, symlinkJoin
, usbutils
, util-linux
, which
, writeShellApplication
, writeTextFile
, xauth
, zenity
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
  dellBanner = "DELL FIRMWARE TOOLING IS PAINFUL";

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
      printf '%s\n' '${dellBanner}' >&2

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

      export TERM=xterm

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

        lock_user=$(${coreutils}/bin/id -un 2>/dev/null || printf root)
        lock_file="''${HOME:-/root}/suulauncher-$lock_user"

        if [ ! -e "$lock_file" ]; then
          return 0
        fi

        lock_pid=$(${coreutils}/bin/tr -cd '0-9' < "$lock_file" || true)
        if [ -n "$lock_pid" ] && [ -d "/proc/$lock_pid" ]; then
          return 0
        fi

        ${coreutils}/bin/rm -f "$lock_file"
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

      found=$(${findutils}/bin/find . -maxdepth 3 -type f \( -name suu -o -name internalsuu -o -name suulauncher \) -perm -0100 -print -quit)
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

    targetPkgs = pkgs: [
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
      pkgs.xterm
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
      ${coreutils}/bin/mkdir -p /var/cache/dell/dell_dup/suu
    '';

    extraBuildCommands = ''
      mkdir -p "$out/opt"
      mkdir -p "$out/usr/libexec/dell_dup"
      touch "$out/usr/libexec/dell_dup/.keep"
    '';

    extraBwrapArgs = [
      "--bind /var/cache/dell/dell_dup/suu /usr/libexec/dell_dup"
    ];
  };

  suu = writeShellApplication {
    name = "dell-suu";

    runtimeInputs = [
      coreutils
      curl
      findutils
      gawk
      jq
      libxml2
      rsync
      util-linux
    ];

    text = ''
      set -euo pipefail
      printf '%s\n' '${dellBanner}' >&2

      usage() {
        cat <<'USAGE'
      usage: dell-suu [--iso PATH | --source PATH | --download] [--cache-source] [--refresh-catalog] [--cache-dir PATH] [--gui | --cli] [--shell] [--launcher PATH] [-- ARGS...]

      Mounts an official Dell Server Update Utility Linux ISO and launches the
      Dell-provided SUU updater inside an FHS runtime. Without --iso or --source it
      first uses a cached source under /var/cache/dell/suu/source, then searches
      for the newest SUU_*-x64-LIN-*.ISO in the current user's Downloads directory.
      With --refresh-catalog in GUI mode, DSU refreshes Dell's online catalog,
      downloads host-relevant upgrade payloads into a local online SUU repository
      cache, and SUU is launched only after that local repository is complete.

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
      refresh_catalog=0
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
          --refresh-catalog)
            refresh_catalog=1
            shift
            ;;
          --no-refresh-catalog)
            refresh_catalog=0
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
        ${coreutils}/bin/mkdir -p "$target_dir"

        ${curl}/bin/curl \
          --location \
          --continue-at - \
          --fail \
          --show-error \
          --progress-bar \
          --user-agent 'Mozilla/5.0' \
          --referer 'https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=2w9tp' \
          --output "$target" \
          '${isoUrl}'

        actual=$(${coreutils}/bin/sha256sum "$target" | ${gawk}/bin/awk '{print $1}')
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

      cached_online_source_dir() {
        printf '%s\n' "$cache_root/suu/online-source"
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

        ${coreutils}/bin/mkdir -p "$target"
        ${rsync}/bin/rsync -a --delete "$src"/ "$target"/

        if ! is_suu_source "$target"; then
          echo "dell-suu: cached source is incomplete: $target" >&2
          exit 66
        fi

        echo "dell-suu: cached SUU source in $target"
      }

      source_is_writable() {
        local dir probe
        dir=$1
        probe="$dir/.dell-suu-write-test.$$"

        if (: > "$probe") 2>/dev/null; then
          ${coreutils}/bin/rm -f "$probe"
          return 0
        fi

        return 1
      }

      find_dsu() {
        local candidate

        for candidate in "''${DELL_DSU_BIN:-}" /run/current-system/sw/bin/dsu dsu; do
          [ -n "$candidate" ] || continue

          if [ "$candidate" = dsu ]; then
            if command -v dsu >/dev/null 2>&1; then
              command -v dsu
              return 0
            fi
          elif [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done

        return 1
      }

      refresh_online_catalog() {
        local dsu_bin status dsu_cache catalog stamp

        dsu_cache=/var/cache/dell/dell_dup/dsu
        catalog="$dsu_cache/Catalog.xml"

        if [ "$(${coreutils}/bin/id -u)" -ne 0 ]; then
          echo "dell-suu: refreshing the Dell catalog needs root" >&2
          return 77
        fi

        if ! dsu_bin=$(find_dsu); then
          echo "dell-suu: dsu is unavailable; install dell-system-update to refresh the online catalog" >&2
          return 69
        fi

        ${coreutils}/bin/mkdir -p "$dsu_cache" /var/lib/dell/dsu

        if [ -s "$catalog" ]; then
          stamp=$(${coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)
          ${coreutils}/bin/cp "$catalog" "$dsu_cache/Catalog-$stamp.xml"
        fi

        echo "dell-suu: refreshing Dell online DSU catalog and compliance report" >&2

        set +e
        TERM=xterm "$dsu_bin" \
          --compliance \
          --apply-upgrades \
          --non-interactive \
          --output=/var/lib/dell/dsu/compliance-upgrades.json \
          --output-format=json \
          --output-log-file=/var/lib/dell/dsu/compliance.log \
          --log-level=4
        status=$?
        set -e

        if [ "$status" -ne 0 ] && [ "$status" -ne 34 ]; then
          echo "dell-suu: dsu catalog refresh failed with exit code $status" >&2
          return "$status"
        fi

        if [ ! -s "$catalog" ]; then
          echo "dell-suu: dsu did not produce $catalog" >&2
          return 66
        fi

        echo "dell-suu: refreshed Dell online DSU catalog/upgrade report" >&2
      }

      catalog_attribute_for_path() {
        local catalog rel_path attr
        catalog=$1
        rel_path=$2
        attr=$3

        ${libxml2}/bin/xmllint --nocatalogs --xpath "string((//*[@path='$rel_path']/@$attr)[1])" "$catalog" 2>/dev/null || true
      }

      verify_catalog_file() {
        local catalog rel_path file expected_hash expected_hash_lower expected_algorithm expected_size actual actual_size
        catalog=$1
        rel_path=$2
        file=$3

        expected_size=$(catalog_attribute_for_path "$catalog" "$rel_path" size)
        if [ -n "$expected_size" ]; then
          actual_size=$(${coreutils}/bin/stat -c %s "$file")
          if [ "$actual_size" != "$expected_size" ]; then
            echo "dell-suu: size mismatch for $rel_path: expected $expected_size, got $actual_size" >&2
            return 1
          fi
        fi

        expected_algorithm=$(catalog_attribute_for_path "$catalog" "$rel_path" hashAlgorithm)
        expected_hash=$(catalog_attribute_for_path "$catalog" "$rel_path" hash)

        if [ -n "$expected_hash" ] && [ "$expected_algorithm" = SHA256 ]; then
          expected_hash_lower=$(printf '%s' "$expected_hash" | ${coreutils}/bin/tr 'A-F' 'a-f')
          actual=$(${coreutils}/bin/sha256sum "$file" | ${gawk}/bin/awk '{print tolower($1)}')
          if [ "$actual" != "$expected_hash_lower" ]; then
            echo "dell-suu: SHA-256 mismatch for $rel_path" >&2
            echo "expected: $expected_hash_lower" >&2
            echo "actual:   $actual" >&2
            return 1
          fi
        fi

        return 0
      }

      download_dell_file() {
        local rel_path dest tmp url
        rel_path=$1
        dest=$2

        url="''${DELL_DOWNLOAD_BASE_URL:-https://downloads.dell.com}/$rel_path"
        ${coreutils}/bin/mkdir -p "$(${coreutils}/bin/dirname "$dest")"
        tmp="$dest.part"

        echo "dell-suu: downloading $rel_path" >&2
        if ! ${curl}/bin/curl \
          --location \
          --continue-at - \
          --fail \
          --show-error \
          --progress-bar \
          --retry 3 \
          --retry-delay 2 \
          --user-agent 'Mozilla/5.0' \
          --output "$tmp" \
          "$url"; then
          ${coreutils}/bin/rm -f "$tmp"
          return 1
        fi

        ${coreutils}/bin/mv "$tmp" "$dest"
      }

      copy_dsu_catalog_for_suu() {
        local dsu_cache repo stamp file name
        dsu_cache=$1
        repo=$2

        ${coreutils}/bin/mkdir -p "$repo"
        if [ -s "$repo/Catalog.xml" ]; then
          stamp=$(${coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)
          ${coreutils}/bin/cp "$repo/Catalog.xml" "$repo/Catalog-$stamp.xml"
        fi

        ${coreutils}/bin/install -m 0644 "$dsu_cache/Catalog.xml" "$repo/Catalog.xml"

        for file in "$dsu_cache"/Catalog*; do
          [ -s "$file" ] || continue
          name=$(${coreutils}/bin/basename "$file")
          case "$name" in
            Catalog-[0-9]*.xml)
              continue
              ;;
          esac

          ${coreutils}/bin/install -m 0644 "$file" "$repo/$name"

          case "$name" in
            Catalog.gz)
              ${coreutils}/bin/install -m 0644 "$file" "$repo/Catalog.xml.gz"
              ;;
            Catalog.gz.sign)
              ${coreutils}/bin/install -m 0644 "$file" "$repo/Catalog.xml.gz.sign"
              ;;
            Catalog.gz.sha512.sign)
              ${coreutils}/bin/install -m 0644 "$file" "$repo/Catalog.xml.gz.sha512.sign"
              ;;
          esac
        done
      }

      copy_dsu_keys_for_suu() {
        local dsu_cache key
        dsu_cache=$1

        ${coreutils}/bin/mkdir -p /var/cache/dell/dell_dup/suu
        for key in "$dsu_cache"/*.asc; do
          [ -e "$key" ] || continue
          ${coreutils}/bin/install -m 0644 "$key" "/var/cache/dell/dell_dup/suu/$(${coreutils}/bin/basename "$key")"
        done
      }

      clear_suu_runtime_state() {
        ${coreutils}/bin/rm -f \
          /var/cache/dell/dell_dup/suu/Compliance.json \
          /var/cache/dell/dell_dup/suu/Compliance.html \
          /var/cache/dell/dell_dup/suu/ComplianceReport.json \
          /var/cache/dell/dell_dup/suu/DSUINACTION.txt \
          /var/cache/dell/dell_dup/suu/Log.txt \
          /var/cache/dell/dell_dup/suu/ProgressLog.txt \
          /var/cache/dell/dell_dup/suu/SUU_STATUS.json \
          /var/cache/dell/dell_dup/suu/TempShareLog.txt \
          /var/cache/dell/dell_dup/suu/hostProgressExit.json \
          /var/cache/dell/dell_dup/suu/inter_progress.json \
          /var/cache/dell/dell_dup/suu/inv.xml \
          /var/cache/dell/dell_dup/suu/inventory_log.txt \
          /var/cache/dell/dell_dup/suu/progress.json \
          /var/cache/dell/dell_dup/suu/status.json \
          /var/cache/dell/dell_dup/suu/suu_support.log \
          /var/cache/dell/dell_dup/suu/suu_ui.log \
          /var/cache/dell/dell_dup/suu/*_compliance.json \
          /var/cache/dell/dell_dup/suu/*_inv.json \
          /var/cache/dell/dell_dup/suu/*_output.json
        ${findutils}/bin/find /var/cache/dell/dell_dup/suu -maxdepth 1 -type f -name 'z*.' -exec ${coreutils}/bin/rm -f '{}' +
      }

      prefer_upgrade_compliance_for_suu_gui() {
        local source_dir
        source_dir=$1

        if [ ! -x "$source_dir/internalsuu" ]; then
          return 0
        fi

        ${coreutils}/bin/mv "$source_dir/internalsuu" "$source_dir/internalsuu.real"

        ${coreutils}/bin/cat > "$source_dir/internalsuu" <<'EOF'
      #!${bashInteractive}/bin/bash
      set -eu

      export TERM=xterm

      if [ -n "''${DELL_SUU_CATALOG_LOCATION:-}" ]; then
        rewritten_args=()
        for arg in "$@"; do
          case "$arg" in
            --catalog-location=*)
              rewritten_args+=("--catalog-location=$DELL_SUU_CATALOG_LOCATION")
              ;;
            *)
              rewritten_args+=("$arg")
              ;;
          esac
        done
        set -- "''${rewritten_args[@]}"
      fi

      mode=''${DELL_SUU_COMPLIANCE_MODE:-upgrades}

      if [ "$mode" = upgrades ]; then
        has_compliance=0
        has_apply_mode=0

        for arg in "$@"; do
          case "$arg" in
            --compliance)
              has_compliance=1
              ;;
            --apply-upgrades|--apply-downgrades|--update)
              has_apply_mode=1
              ;;
          esac
        done

        if [ "$has_compliance" -eq 1 ] && [ "$has_apply_mode" -eq 0 ]; then
          exec "$(dirname "$0")/internalsuu.real" "$@" --apply-upgrades
        fi
      fi

      exec "$(dirname "$0")/internalsuu.real" "$@"
      EOF

        ${coreutils}/bin/chmod 0755 "$source_dir/internalsuu"
      }

      materialize_payload_for_suu() {
        local dsu_cache repo catalog rel_path dest cached sign_rel sign_dest sign_cached
        dsu_cache=$1
        repo=$2
        catalog=$3
        rel_path=$4

        [ -n "$rel_path" ] || return 0

        dest="$repo/$rel_path"
        cached="$dsu_cache/$(${coreutils}/bin/basename "$rel_path")"

        if [ -s "$dest" ] && verify_catalog_file "$catalog" "$rel_path" "$dest"; then
          :
        elif [ -s "$cached" ]; then
          ${coreutils}/bin/mkdir -p "$(${coreutils}/bin/dirname "$dest")"
          ${coreutils}/bin/install -m 0644 "$cached" "$dest"
          if ! verify_catalog_file "$catalog" "$rel_path" "$dest"; then
            ${coreutils}/bin/rm -f "$dest"
            download_dell_file "$rel_path" "$dest"
            verify_catalog_file "$catalog" "$rel_path" "$dest"
          fi
        else
          download_dell_file "$rel_path" "$dest"
          verify_catalog_file "$catalog" "$rel_path" "$dest"
        fi

        sign_rel="$rel_path.sign"
        sign_dest="$dest.sign"
        sign_cached="$cached.sign"

        if [ -s "$sign_dest" ]; then
          return 0
        fi

        if [ -s "$sign_cached" ]; then
          ${coreutils}/bin/install -m 0644 "$sign_cached" "$sign_dest"
        elif ! download_dell_file "$sign_rel" "$sign_dest"; then
          echo "dell-suu: warning: failed to download signature for $rel_path" >&2
        fi
      }

      prepare_online_suu_source() {
        local base_source online_source repo dsu_cache catalog compliance payloads_file inventory_path rel_path
        base_source=$1
        online_source=$(cached_online_source_dir)
        repo="$online_source/repository"
        dsu_cache=/var/cache/dell/dell_dup/dsu
        catalog="$dsu_cache/Catalog.xml"
        compliance=/var/lib/dell/dsu/compliance-upgrades.json

        if [ "$(${coreutils}/bin/id -u)" -ne 0 ]; then
          echo "dell-suu: preparing the online SUU repository needs root" >&2
          return 77
        fi

        if ! is_suu_source "$base_source"; then
          echo "dell-suu: base source does not look like a SUU source: $base_source" >&2
          return 66
        fi

        if [ ! -s "$catalog" ]; then
          echo "dell-suu: DSU catalog is missing: $catalog" >&2
          return 66
        fi

        ${coreutils}/bin/mkdir -p "$online_source" "$repo"
        ${rsync}/bin/rsync -a --delete --exclude '/repository/***' "$base_source"/ "$online_source"/
        prefer_upgrade_compliance_for_suu_gui "$online_source"

        copy_dsu_catalog_for_suu "$dsu_cache" "$repo"
        copy_dsu_keys_for_suu "$dsu_cache"
        clear_suu_runtime_state

        payloads_file=$(${coreutils}/bin/mktemp /tmp/dell-suu-payloads.XXXXXX)
        trap '${coreutils}/bin/rm -f "$payloads_file"; cleanup_mount' EXIT

        inventory_path=$(${libxml2}/bin/xmllint --nocatalogs --xpath "string((//InventoryComponent[@osCode='LIN64']/@path)[1])" "$catalog" 2>/dev/null || true)
        if [ -n "$inventory_path" ]; then
          printf '%s\n' "$inventory_path" >> "$payloads_file"
        fi

        if [ -s "$compliance" ]; then
          ${jq}/bin/jq -r '.. | objects | .packageFilePath? // empty' "$compliance" >> "$payloads_file"
        fi

        ${coreutils}/bin/sort -u "$payloads_file" | while IFS= read -r rel_path; do
          [ -n "$rel_path" ] || continue
          materialize_payload_for_suu "$dsu_cache" "$repo" "$catalog" "$rel_path"
        done

        ${coreutils}/bin/rm -f "$payloads_file"
        trap cleanup_mount EXIT

        echo "dell-suu: prepared online SUU source in $online_source" >&2
        printf '%s\n' "$online_source"
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
          ${util-linux}/bin/umount "$mounted_dir" || true
          ${coreutils}/bin/rmdir "$mounted_dir" || true
        fi
      }

      if [ -n "$iso" ]; then
        if [ "$(${coreutils}/bin/id -u)" -ne 0 ]; then
          echo "dell-suu: mounting the SUU ISO needs root; run with sudo" >&2
          exit 77
        fi

        if [ ! -f "$iso" ]; then
          echo "dell-suu: ISO not found: $iso" >&2
          echo "dell-suu: run 'dell-suu --download' first, or pass --iso PATH" >&2
          exit 66
        fi

        mounted_dir=$(${coreutils}/bin/mktemp -d /tmp/dell-suu.XXXXXX)
        trap cleanup_mount EXIT
        ${util-linux}/bin/mount -o loop,ro "$iso" "$mounted_dir"
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

      if [ "$mode" = gui ] && ! source_is_writable "$source_dir"; then
        cached_source=$(cached_source_dir)
        if is_suu_source "$cached_source"; then
          source_dir=$cached_source
        else
          echo "dell-suu: GUI needs a writable SUU source; caching ISO source first" >&2
          cache_suu_source "$source_dir"
          source_dir=$cached_source
        fi
      fi

      if [ "$mode" = gui ] && [ "$refresh_catalog" -eq 1 ]; then
        if ! refresh_online_catalog; then
          echo "dell-suu: refusing to launch stale SUU source after refresh failure" >&2
          exit 1
        fi

        if ! online_source=$(prepare_online_suu_source "$source_dir"); then
          echo "dell-suu: refusing to launch stale SUU source after online repository preparation failure" >&2
          exit 1
        fi

        source_dir=$online_source
        export DELL_SUU_CATALOG_LOCATION="$online_source/repository"
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
      description = "Run Dell Server Update Utility from an official SUU ISO on NixOS; Dell firmware tooling is painful";
      homepage = "https://www.dell.com/support/kbdoc/en-us/000123359/dell-emc-server-update-utility-suu-guide-and-download";
      license = lib.licenses.unfree;
      mainProgram = "dell-suu";
      platforms = [ "x86_64-linux" ];
    };
  };

  guiLauncher = writeShellApplication {
    name = "dell-suu-gui";

    runtimeInputs = [
      coreutils
    ];

    text = ''
      set -euo pipefail
      printf '%s\n' '${dellBanner}' >&2

      user_id=$(${coreutils}/bin/id -u)
      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$user_id}"
      display="''${DISPLAY:-}"
      xauthority="''${XAUTHORITY:-}"
      dbus_session_bus_address="''${DBUS_SESSION_BUS_ADDRESS:-}"

      if [ -z "$display" ] && [ -S /tmp/.X11-unix/X0 ]; then
        display=:0
      fi

      if [ -z "$xauthority" ]; then
        for candidate in "$runtime_dir/gdm/Xauthority" "''${HOME:-}/.Xauthority"; do
          if [ -e "$candidate" ]; then
            xauthority="$candidate"
            break
          fi
        done
      fi

      if [ -z "$dbus_session_bus_address" ] && [ -S "$runtime_dir/bus" ]; then
        dbus_session_bus_address="unix:path=$runtime_dir/bus"
      fi

      if [ -n "$display" ]; then
        export DISPLAY="$display"
      fi

      if [ -n "$xauthority" ]; then
        export XAUTHORITY="$xauthority"
      fi

      if [ -d "$runtime_dir" ]; then
        export XDG_RUNTIME_DIR="$runtime_dir"
      fi

      if [ -n "$dbus_session_bus_address" ]; then
        export DBUS_SESSION_BUS_ADDRESS="$dbus_session_bus_address"
      fi

      refresh_catalog=0
      case "''${DELL_SUU_REFRESH_CATALOG:-ask}" in
        1|yes|true)
          refresh_catalog=1
          ;;
        0|no|false)
          refresh_catalog=0
          ;;
        *)
          if [ -n "$display" ]; then
            if ${zenity}/bin/zenity \
              --question \
              --title "Dell Server Update Utility" \
              --text "Refresh Dell online catalog and download matching packages before opening SUU?" \
              --ok-label "Refresh" \
              --cancel-label "Skip"; then
              refresh_catalog=1
            fi
          fi
          ;;
      esac

      suu_args=(${suu}/bin/dell-suu --gui)
      if [ "$refresh_catalog" -eq 1 ]; then
        suu_args+=(--refresh-catalog)
      fi

      if [ "$(${coreutils}/bin/id -u)" -eq 0 ]; then
        exec "''${suu_args[@]}" "$@"
      fi

      pkexec=/run/wrappers/bin/pkexec
      if [ ! -x "$pkexec" ]; then
        echo "dell-suu-gui: /run/wrappers/bin/pkexec is unavailable; enable polkit or run as root" >&2
        exit 69
      fi

      env_args=()
      if [ -n "$display" ]; then
        env_args+=("DISPLAY=$display")
      fi

      if [ -n "$xauthority" ]; then
        env_args+=("XAUTHORITY=$xauthority")
      fi

      if [ -d "$runtime_dir" ]; then
        env_args+=("XDG_RUNTIME_DIR=$runtime_dir")
      fi

      if [ -n "$dbus_session_bus_address" ]; then
        env_args+=("DBUS_SESSION_BUS_ADDRESS=$dbus_session_bus_address")
      fi

      exec "$pkexec" ${coreutils}/bin/env "''${env_args[@]}" "''${suu_args[@]}" "$@"
    '';
  };

  desktopItem = makeDesktopItem {
    name = "dell-suu";
    desktopName = "Dell Server Update Utility";
    genericName = "Firmware updater";
    comment = "Launch the Dell SUU firmware update GUI; Dell firmware tooling is painful";
    exec = "dell-suu-gui";
    icon = "dell-suu";
    categories = [
      "System"
      "Settings"
    ];
  };

  desktopIcon = writeTextFile {
    name = "dell-suu-icon";
    destination = "/share/icons/hicolor/scalable/apps/dell-suu.svg";
    text = ''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
        <rect width="64" height="64" rx="12" fill="#263238"/>
        <rect x="13" y="14" width="38" height="11" rx="2" fill="#90caf9"/>
        <rect x="13" y="28" width="38" height="11" rx="2" fill="#eceff1"/>
        <rect x="13" y="42" width="38" height="8" rx="2" fill="#546e7a"/>
        <circle cx="20" cy="19.5" r="2" fill="#102027"/>
        <circle cx="20" cy="33.5" r="2" fill="#102027"/>
        <path d="M40 36v8h-8v5h8v8h5v-8h8v-5h-8v-8z" fill="#69f0ae"/>
      </svg>
    '';
  };
in
symlinkJoin {
  name = "dell-suu";
  paths = [
    suu
    guiLauncher
    desktopItem
    desktopIcon
  ];

  meta = suu.meta;
}
