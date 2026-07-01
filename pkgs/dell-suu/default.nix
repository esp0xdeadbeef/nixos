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
, gnugrep
, gnutar
, gpgme
, gtk3
, gzip
, hwinfo
, ipmitool
, jq
, lib
, libarchive
, libGL
, libdrm
, libuuid
, libxkbcommon
, lshw
, makeDesktopItem
, ncurses
, nss
, pciutils
, python3
, rsync
, rpm
, smartmontools
, symlinkJoin
, tmux
, usbutils
, util-linux
, wget
, which
, writeShellApplication
, writeTextFile
, xauth
, xterm
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
, libxxf86vm
, libxcb
, libxml2
, libxml2_13
,
}:
let
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
      export COLUMNS="''${COLUMNS:-120}"
      export LINES="''${LINES:-40}"

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
      gnugrep
      gnutar
      gpgmeCompat
      gtk3
      gzip
      ipmitool
      libGL
      libdrm
      libuuid
      libxkbcommon
      lshw
      ncurses
      nss
      pciutils
      rpm
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
      libxxf86vm
      libxcb
      libxml2
      libxml2_13
    ];

    extraPreBwrapCmds = ''
      ${coreutils}/bin/mkdir -p /var/cache/dell/dell_dup/suu
      ${coreutils}/bin/mkdir -p /var/cache/dell/suu/opt
      ${coreutils}/bin/touch /var/cache/dell/suu/usr-libexecsuu_temp_modelname_tempfile.txt
      ${coreutils}/bin/chmod 0666 /var/cache/dell/suu/usr-libexecsuu_temp_modelname_tempfile.txt
    '';

    extraBuildCommands = ''
      mkdir -p "$out/opt"
      mkdir -p "$out/usr/libexec/dell_dup"
      touch "$out/usr/libexec/dell_dup/.keep"
      ln -s /var/cache/dell/suu/usr-libexecsuu_temp_modelname_tempfile.txt "$out/usr/libexecsuu_temp_modelname_tempfile.txt"
    '';

    extraBwrapArgs = [
      "--bind /var/cache/dell/dell_dup/suu /usr/libexec/dell_dup"
      "--bind /var/cache/dell/suu/opt /opt"
    ];
  };

  supportRefresh = writeShellApplication {
    name = "dell-suu-support-refresh";

    runtimeInputs = [
      coreutils
      findutils
      gnugrep
      gnutar
      gzip
      hwinfo.bin
      ipmitool
      libarchive
      lshw
      pciutils
      python3
      rpm
    ];

    text = ''
      set -euo pipefail

      export DELL_SUU_FHS="${fhs}/bin/dell-suu-fhs"
      export DELL_SUU_BSDTAR="${libarchive}/bin/bsdtar"
      export DELL_SUU_DMIDECODE="${dmidecode}/bin/dmidecode"
      export DELL_SUU_HWINFO="${hwinfo.bin}/bin/hwinfo"
      export DELL_SUU_IPMITOOL="${ipmitool}/bin/ipmitool"
      export DELL_SUU_LSPCI="${pciutils}/bin/lspci"
      export DELL_SUU_LSHW="${lshw}/bin/lshw"

      exec ${python3}/bin/python3 ${./dell-suu-support-refresh.py} "$@"
    '';
  };

  suu = writeShellApplication {
    name = "dell-suu";

    runtimeInputs = [
      coreutils
      curl
      findutils
      gawk
      gzip
      jq
      libxml2
      rsync
      util-linux
      wget
    ];

    text = ''
      set -euo pipefail
      printf '%s\n' '${dellBanner}' >&2

      usage() {
        cat <<'USAGE'
      usage: dell-suu [--iso PATH | --source PATH | --download] [--cache-source] [--online-cache] [--refresh-catalog] [--cache-dir PATH] [--gui | --cli] [--shell] [--launcher PATH] [-- ARGS...]

      Mounts an official Dell Server Update Utility Linux ISO and launches the
      Dell-provided SUU updater inside an FHS runtime. Without --iso or --source it
      first uses a cached source under /var/cache/dell/suu/source, then searches
      for the newest SUU Linux ISO in the invoking user's Documents/Downloads directory.
      GUI mode automatically downloads the SUU ISO when no cached source or local
      ISO exists by resolving Dell's poweredgec platform CSV at runtime; set
      DELL_SUU_AUTO_DOWNLOAD_ISO=0 to require an explicit ISO.
      With --refresh-catalog in GUI mode, DSU refreshes Dell's online catalog,
      downloads host-relevant upgrade payloads into a local online SUU repository
      cache, and SUU is launched only after that local repository is complete.

      examples:
        dell-suu --download
        sudo dell-suu --iso ~/Documents/SUU-LIN64_*.ISO
        sudo dell-suu --iso ~/Documents/SUU-LIN64_*.ISO -- --help
        sudo dell-suu --iso ~/Documents/SUU-LIN64_*.ISO --cache-source
        sudo dell-suu --gui
        sudo dell-suu --iso ~/Documents/SUU-LIN64_*.ISO --gui
        sudo dell-suu --source /mnt/suu
        sudo dell-suu --iso ~/Documents/SUU-LIN64_*.ISO --shell
      USAGE
      }

      iso=
      source_dir=
      launcher=
      mode=cli
      shell=0
      download=0
      cache_source=0
      online_cache=0
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
          --online-cache|--use-online-cache)
            online_cache=1
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

      original_user() {
        if [ -n "''${SUDO_USER:-}" ] && [ "''${SUDO_USER:-}" != root ]; then
          printf '%s\n' "$SUDO_USER"
        else
          ${coreutils}/bin/id -un
        fi
      }

      original_home() {
        local user
        user=$(original_user)

        if [ "$user" != root ] && [ -d "/home/$user" ]; then
          printf '/home/%s\n' "$user"
        else
          printf '%s\n' "''${HOME:-/root}"
        fi
      }

      default_iso_download_dir() {
        local home

        if [ -n "''${DELL_SUU_DOWNLOAD_DIR:-}" ]; then
          printf '%s\n' "$DELL_SUU_DOWNLOAD_DIR"
          return 0
        fi

        home=$(original_home)
        printf '%s/Documents\n' "$home"
      }

      resolve_suu_iso_json() {
        local resolver_cache_root

        resolver_cache_root=$cache_root
        if [ "$(${coreutils}/bin/id -u)" -ne 0 ] \
          && { [ ! -d "$resolver_cache_root" ] || [ ! -w "$resolver_cache_root" ]; }; then
          resolver_cache_root="''${XDG_CACHE_HOME:-''${HOME:-/tmp}/.cache}/dell"
        fi

        ${supportRefresh}/bin/dell-suu-support-refresh \
          --resolve-suu-iso \
          --cache-root "$resolver_cache_root"
      }

      iso_content_length() {
        local url
        url=$1

        ${curl}/bin/curl \
          --location \
          --head \
          --fail \
          --silent \
          --show-error \
          --user-agent 'Mozilla/5.0' \
          "$url" \
          | ${gawk}/bin/awk 'BEGIN { IGNORECASE = 1 } /^content-length:/ { gsub("\r", "", $2); size = $2 } END { print size }'
      }

      iso_tmp_dir() {
        local iso_url target_dir remote_size available_kb required_kb

        iso_url=$1
        target_dir=$2

        if [ -d /dev/shm ] && [ -w /dev/shm ]; then
          remote_size=$(iso_content_length "$iso_url" 2>/dev/null || true)
          if [[ "$remote_size" =~ ^[0-9]+$ ]]; then
            available_kb=$(${coreutils}/bin/df -Pk /dev/shm | ${gawk}/bin/awk 'NR == 2 { print $4 }')
            required_kb=$(((remote_size + 1023) / 1024 + 1048576))
            if [ "$available_kb" -gt "$required_kb" ]; then
              printf '%s\n' /dev/shm
              return 0
            fi
          else
            printf '%s\n' /dev/shm
            return 0
          fi
        fi

        printf '%s\n' "$target_dir"
      }

      download_iso() {
        local iso_json iso_name iso_source iso_url iso_version target_dir target target_group target_owner tmp tmp_dir

        iso_json=$(resolve_suu_iso_json)
        iso_name=$(printf '%s\n' "$iso_json" | ${jq}/bin/jq -r '.name // empty')
        iso_url=$(printf '%s\n' "$iso_json" | ${jq}/bin/jq -r '.url // empty')
        iso_source=$(printf '%s\n' "$iso_json" | ${jq}/bin/jq -r '.source // empty')
        iso_version=$(printf '%s\n' "$iso_json" | ${jq}/bin/jq -r '.version // empty')

        if [ -z "$iso_name" ] || [ -z "$iso_url" ]; then
          echo "dell-suu: Dell platform CSV did not resolve a SUU ISO" >&2
          exit 66
        fi

        target_dir=$(default_iso_download_dir)
        target="$target_dir/$iso_name"

        if [ "$(${coreutils}/bin/id -u)" -eq 0 ] \
          && target_owner=$(original_user) \
          && [ "$target_owner" != root ] \
          && target_group=$(${coreutils}/bin/id -gn "$target_owner" 2>/dev/null); then
          ${coreutils}/bin/install -d -m 0755 -o "$target_owner" -g "$target_group" "$target_dir"
        else
          target_owner=
          target_group=
          ${coreutils}/bin/mkdir -p "$target_dir"
        fi

        if [ -s "$target" ]; then
          echo "dell-suu: using cached SUU ISO $target" >&2
          printf '%s\n' "$target"
          return 0
        fi

        tmp_dir=$(iso_tmp_dir "$iso_url" "$target_dir")
        if [ "$tmp_dir" = "$target_dir" ]; then
          tmp="$target.part"
        else
          tmp="$tmp_dir/$iso_name"
        fi

        echo "dell-suu: downloading Dell SUU ISO $iso_name''${iso_version:+ version $iso_version}" >&2
        echo "dell-suu: source $iso_source" >&2
        echo "dell-suu: target $target" >&2

        ${wget}/bin/wget \
          --continue \
          --progress=bar:force:noscroll \
          --user-agent='Mozilla/5.0' \
          --output-document="$tmp" \
          "$iso_url"

        if [ ! -s "$tmp" ]; then
          echo "dell-suu: downloaded ISO is empty: $tmp" >&2
          exit 65
        fi

        if [ "$tmp" = "$target.part" ]; then
          ${coreutils}/bin/mv "$tmp" "$target"
        else
          ${coreutils}/bin/install -m 0644 "$tmp" "$target"
          ${coreutils}/bin/rm -f "$tmp"
        fi

        if [ -n "$target_owner" ]; then
          ${coreutils}/bin/chown "$target_owner:$target_group" "$target"
        fi

        printf '%s\n' "$target"
      }

      find_latest_iso() {
        shopt -s nullglob
        local latest=
        local dirs=()

        if [ -n "''${SUDO_USER:-}" ] && [ "''${SUDO_USER:-}" != "root" ]; then
          dirs+=("/home/$SUDO_USER/Documents" "/home/$SUDO_USER/Downloads")
        fi

        dirs+=("''${HOME:-/root}/Documents" "''${HOME:-/root}/Downloads" "$PWD")

        for dir in "''${dirs[@]}"; do
          for candidate in \
            "$dir"/SUU-LIN64_*.ISO \
            "$dir"/SUU-LIN64_*.iso \
            "$dir"/SUU_*-x64-LIN-*.ISO \
            "$dir"/SUU_*-x64-LIN-*.iso \
            "$dir"/SUU_*.ISO \
            "$dir"/SUU_*.iso \
            "$dir"/SUU-*.ISO \
            "$dir"/SUU-*.iso; do
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

      preserve_catalog_cache_entry() {
        local dsu_cache stamp name current archive
        dsu_cache=$1
        stamp=$2
        name=$3
        current="$dsu_cache/$name"
        archive="$dsu_cache/archive/$stamp-$name"

        if [ -L "$current" ]; then
          ${coreutils}/bin/rm -f "$current"
          return 0
        fi

        if [ -e "$current" ]; then
          ${coreutils}/bin/mkdir -p "$dsu_cache/archive"
          if [ -e "$archive" ]; then
            archive="$dsu_cache/archive/$stamp-$$-$name"
          fi
          ${coreutils}/bin/mv "$current" "$archive"
        fi
      }

      refresh_online_catalog() {
        local dsu_cache catalog stamp base_url key rel_path staging final current target name

        dsu_cache=/var/cache/dell/dell_dup/dsu
        catalog="$dsu_cache/Catalog.xml"
        base_url="''${DELL_CATALOG_BASE_URL:-https://downloads.dell.com/catalog}"

        if [ "$(${coreutils}/bin/id -u)" -ne 0 ]; then
          echo "dell-suu: refreshing the Dell catalog needs root" >&2
          return 77
        fi

        stamp="$(${coreutils}/bin/date +%Y-%m-%d_%H-%M-%S)-$$"
        staging="$dsu_cache/catalogs/$stamp.tmp"
        final="$dsu_cache/catalogs/$stamp"
        current="$dsu_cache/current"

        ${coreutils}/bin/mkdir -p "$staging" /var/lib/dell/dsu

        echo "dell-suu: refreshing Dell online catalog metadata into $staging" >&2

        for rel_path in \
          CatalogIndex.gz \
          CatalogIndex.gz.sha512.sign \
          Catalog.gz \
          Catalog.gz.sign \
          Catalog.gz.sha512.sign; do
          target="$staging/$rel_path"
          echo "dell-suu: downloading $rel_path" >&2
          ${curl}/bin/curl \
            --location \
            --fail \
            --show-error \
            --progress-bar \
            --retry 3 \
            --retry-delay 2 \
            --user-agent 'Mozilla/5.0' \
            --output "$target.part" \
            "$base_url/$rel_path"
          ${coreutils}/bin/mv "$target.part" "$target"
        done

        ${gzip}/bin/gzip -dc "$staging/CatalogIndex.gz" > "$staging/CatalogIndex.xml"
        ${gzip}/bin/gzip -dc "$staging/Catalog.gz" > "$staging/Catalog.xml"

        if [ ! -s "$staging/Catalog.xml" ]; then
          echo "dell-suu: catalog refresh did not produce $staging/Catalog.xml" >&2
          ${coreutils}/bin/rm -rf "$staging"
          return 66
        fi

        ${coreutils}/bin/mv "$staging" "$final"
        ${coreutils}/bin/ln -sfnT "$final" "$current"

        for name in \
          CatalogIndex.gz \
          CatalogIndex.gz.sha512.sign \
          CatalogIndex.xml \
          Catalog.gz \
          Catalog.gz.sign \
          Catalog.gz.sha512.sign \
          Catalog.xml; do
          preserve_catalog_cache_entry "$dsu_cache" "$stamp" "$name"
          ${coreutils}/bin/ln -sfnT "current/$name" "$dsu_cache/$name"
        done

        for key in \
          0x756ba70b1019ced6.asc \
          0x1285491434D8786F.asc \
          0xca77951d23b66a9d.asc \
          0x3CA66B4946770C59.asc \
          0x274E9C32857A9594.asc \
          0x076B95DB2FFC7F4A.asc; do
          if [ ! -s "$dsu_cache/$key" ]; then
            ${curl}/bin/curl \
              --location \
              --fail \
              --show-error \
              --progress-bar \
              --retry 3 \
              --retry-delay 2 \
              --user-agent 'Mozilla/5.0' \
              --output "$dsu_cache/$key.part" \
              "https://linux.dell.com/repo/pgp_pubkeys/$key"
            ${coreutils}/bin/mv "$dsu_cache/$key.part" "$dsu_cache/$key"
          fi
        done

        if [ ! -s "$catalog" ]; then
          echo "dell-suu: catalog refresh did not produce $catalog" >&2
          return 66
        fi

        echo "dell-suu: refreshed Dell online catalog metadata in $final" >&2
      }

      cached_online_source_if_fresh() {
        local online_source repo source_catalog support_report support_manifest max_age now source_mtime support_mtime oldest_mtime age

        online_source=$(cached_online_source_dir)
        repo="$online_source/repository"
        source_catalog="$repo/Catalog.xml"
        support_report=/var/lib/dell/suu/support-upgrades.json
        support_manifest=/var/lib/dell/suu/support-refresh-manifest.json

        case "''${DELL_SUU_FORCE_REFRESH:-0}" in
          1|yes|true)
            return 1
            ;;
        esac

        max_age="''${DELL_SUU_REFRESH_MAX_AGE_SECONDS:-21600}"
        if [[ ! "$max_age" =~ ^[0-9]+$ ]]; then
          echo "dell-suu: invalid DELL_SUU_REFRESH_MAX_AGE_SECONDS=$max_age" >&2
          return 1
        fi

        if [ "$max_age" -eq 0 ]; then
          return 1
        fi

        is_suu_source "$online_source" || return 1
        [ -s "$source_catalog" ] || return 1
        [ -s "$support_report" ] || return 1
        [ -s "$support_manifest" ] || return 1

        source_mtime=$(${coreutils}/bin/stat -c %Y "$source_catalog")
        support_mtime=$(${coreutils}/bin/stat -c %Y "$support_report")
        oldest_mtime=$source_mtime
        if [ "$support_mtime" -lt "$oldest_mtime" ]; then
          oldest_mtime=$support_mtime
        fi

        now=$(${coreutils}/bin/date +%s)
        age=$((now - oldest_mtime))

        if [ "$age" -gt "$max_age" ]; then
          return 1
        fi

        echo "dell-suu: using cached Dell online catalog/compliance from $online_source ($age seconds old)" >&2
        echo "dell-suu: set DELL_SUU_FORCE_REFRESH=1 to force a fresh Dell online refresh" >&2
        printf '%s\n' "$online_source"
      }

      cached_online_source_if_present() {
        local online_source repo source_catalog support_report

        online_source=$(cached_online_source_dir)
        repo="$online_source/repository"
        source_catalog="$repo/Catalog.xml"
        support_report=/var/lib/dell/suu/support-upgrades.json

        is_suu_source "$online_source" || return 1
        [ -s "$source_catalog" ] || return 1
        [ -s "$support_report" ] || return 1

        echo "dell-suu: using cached Dell online catalog/compliance from $online_source" >&2
        printf '%s\n' "$online_source"
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
        local rel_path dest catalog tmp url
        rel_path=$1
        dest=$2
        catalog=''${3:-}

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

        if [ -n "$catalog" ] && ! verify_catalog_file "$catalog" "$rel_path" "$tmp"; then
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

        if [ ! -x "$source_dir/internalsuu.real" ]; then
          ${coreutils}/bin/mv "$source_dir/internalsuu" "$source_dir/internalsuu.real"
        fi

        ${coreutils}/bin/cat > "$source_dir/internalsuu" <<'EOF'
      #!${bashInteractive}/bin/bash
      set -eu

      export TERM=xterm

      merge_support_compliance() {
        local output_file previous arg
        output_file=
        previous=

        for arg in "$@"; do
          if [ "$previous" = output ]; then
            output_file=$arg
            previous=
            continue
          fi

          case "$arg" in
            --output=*)
              output_file=''${arg#--output=}
              ;;
            --output)
              previous=output
              ;;
          esac
        done

        if [ -z "$output_file" ]; then
          output_file=/usr/libexec/dell_dup/Compliance.json
        fi

        ${supportRefresh}/bin/dell-suu-support-refresh --merge --compliance "$output_file" || true
      }

      support_catalog_dir_from_args() {
        local previous arg value
        previous=
        value=

        for arg in "$@"; do
          if [ "$previous" = catalog ]; then
            value=$arg
            previous=
            continue
          fi

          case "$arg" in
            --catalog-location=*)
              value=''${arg#--catalog-location=}
              ;;
            --catalog-location)
              previous=catalog
              ;;
          esac
        done

        if [ -n "''${DELL_SUU_CATALOG_LOCATION:-}" ]; then
          value=$DELL_SUU_CATALOG_LOCATION
        fi

        case "$value" in
          */Catalog.xml)
            dirname "$value"
            ;;
          "")
            printf '%s\n' "$(pwd)/repository"
            ;;
          *)
            printf '%s\n' "$value"
            ;;
        esac
      }

      support_update_list_from_args() {
        local previous arg
        previous=

        for arg in "$@"; do
          if [ "$previous" = update ]; then
            printf '%s\n' "$arg"
            return 0
          fi

          case "$arg" in
            --update-list=*)
              printf '%s\n' "''${arg#--update-list=}"
              return 0
              ;;
            --update-list)
              previous=update
              ;;
          esac
        done

        return 1
      }

      write_support_status() {
        local status_message exit_status status_file
        status_message=$1
        exit_status=''${2:-}
        status_file=/usr/libexec/dell_dup/SUU_STATUS.json
        ${coreutils}/bin/mkdir -p "$(${coreutils}/bin/dirname "$status_file")"

        if [ -n "$exit_status" ]; then
          ${jq}/bin/jq -cn \
            --arg message "$status_message" \
            --argjson exitStatus "$exit_status" \
            '{SystemUpdateStatus:[{System:{id:"0600",idType:"BIOS",hostAddress:"LocalHost"},InvokerInfo:{name:"dell-suu-support-apply",version:"1",command:"support DUP apply",exitStatus:$exitStatus,statusMessage:$message}}]}' \
            > "$status_file"
          ${coreutils}/bin/rm -f /usr/libexec/dell_dup/inter_progress.json
        else
          ${jq}/bin/jq -cn \
            --arg message "$status_message" \
            '{SystemUpdateStatus:[{System:{id:"0600",idType:"BIOS",hostAddress:"LocalHost"},InvokerInfo:{name:"dell-suu-support-apply",version:"1",command:"support DUP apply",statusMessage:$message}}]}' \
            > /usr/libexec/dell_dup/inter_progress.json
        fi
      }

      apply_support_updates() {
        local update_list support_report catalog_dir item basename rel_path full_path launch_path launch_link status failures reboot_required selected support_count remaining_count dup_args_raw
        local -a selected_support_paths remaining_items dup_args pass_args
        declare -A support_path_by_name

        update_list=$(support_update_list_from_args "$@") || return 1
        support_report=/var/lib/dell/suu/support-upgrades.json
        [ -s "$support_report" ] || return 1

        while IFS=$'\t' read -r basename rel_path; do
          [ -n "$basename" ] || continue
          support_path_by_name["$basename"]=$rel_path
        done < <(${jq}/bin/jq -r '
          .SystemUpdateCompliance[0].UpdateableComponent[]?
          | [(.packageFilePath | split("/")[-1]), .packageFilePath]
          | @tsv
        ' "$support_report")

        IFS=, read -r -a selected <<< "$update_list"
        selected_support_paths=()
        remaining_items=()

        for item in "''${selected[@]}"; do
          item="''${item#"''${item%%[![:space:]]*}"}"
          item="''${item%"''${item##*[![:space:]]}"}"
          [ -n "$item" ] || continue
          basename=''${item##*/}

          if [ -n "''${support_path_by_name[$basename]:-}" ]; then
            selected_support_paths+=("''${support_path_by_name[$basename]}")
          else
            remaining_items+=("$item")
          fi
        done

        support_count=''${#selected_support_paths[@]}
        remaining_count=''${#remaining_items[@]}
        if [ "$support_count" -eq 0 ]; then
          return 1
        fi

        catalog_dir=$(support_catalog_dir_from_args "$@")
        dup_args_raw="''${DELL_SUU_SUPPORT_DUP_ARGS:--q}"
        read -r -a dup_args <<< "$dup_args_raw"

        echo "dell-suu: applying $support_count Dell support DUP update(s)" >&2
        write_support_status "Applying Dell support update(s)"

        failures=0
        reboot_required=0
        for rel_path in "''${selected_support_paths[@]}"; do
          full_path="$catalog_dir/$rel_path"
          if [ ! -x "$full_path" ]; then
            echo "dell-suu: missing executable support DUP: $full_path" >&2
            failures=$((failures + 1))
            continue
          fi

          basename=$(${coreutils}/bin/basename "$full_path")
          launch_path="$full_path"
          launch_link="$(pwd)/$basename"
          if [ "$launch_link" != "$full_path" ]; then
            ${coreutils}/bin/ln -sfn "$full_path" "$launch_link"
            launch_path="./$basename"
          fi

          echo "dell-suu: running $basename ''${dup_args[*]}" >&2
          write_support_status "Applying $basename"
          set +e
          "$launch_path" "''${dup_args[@]}"
          status=$?
          set -e
          case "$status" in
            0)
              ;;
            2)
              echo "dell-suu: support DUP completed and requires reboot: $rel_path" >&2
              reboot_required=1
              ;;
            *)
              echo "dell-suu: support DUP failed with exit $status: $rel_path" >&2
              failures=$((failures + 1))
              ;;
          esac
        done

        if [ "$remaining_count" -gt 0 ]; then
          pass_args=()
          for arg in "$@"; do
            case "$arg" in
              --update-list=*)
                pass_args+=("--update-list=$(IFS=,; printf '%s' "''${remaining_items[*]}")")
                ;;
              *)
                pass_args+=("$arg")
                ;;
            esac
          done

          set +e
          "$(dirname "$0")/internalsuu.real" "''${pass_args[@]}"
          status=$?
          set -e
          case "$status" in
            0)
              ;;
            2)
              reboot_required=1
              ;;
            *)
              failures=$((failures + 1))
              ;;
          esac
        fi

        if [ "$failures" -eq 0 ]; then
          if [ "$reboot_required" -eq 1 ]; then
            write_support_status "Dell support update(s) completed; reboot required" 0
            echo "dell-suu: Dell support DUP update(s) completed; reboot required" >&2
          else
            write_support_status "Dell support update(s) completed" 0
            echo "dell-suu: Dell support DUP update(s) completed" >&2
          fi
          exit 0
        fi

        write_support_status "Dell support update(s) completed with failures" 1
        exit 1
      }

      if [ -n "''${DELL_SUU_CATALOG_LOCATION:-}" ]; then
        rewritten_args=()
        skip_next=0
        for arg in "$@"; do
          if [ "$skip_next" -eq 1 ]; then
            skip_next=0
            continue
          fi

          case "$arg" in
            --catalog-location=*)
              ;;
            --catalog-location)
              skip_next=1
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
            --apply-upgrades|--apply-downgrades|--update|--update-list|--update-list=*)
              has_apply_mode=1
              ;;
          esac
        done

        if [ "$has_apply_mode" -eq 1 ]; then
          apply_support_updates "$@" || true
        fi

        if [ "$has_compliance" -eq 1 ] \
          && [ "$has_apply_mode" -eq 0 ] \
          && [ "''${DELL_SUU_ENABLE_SYNTHETIC_COMPLIANCE:-0}" = 1 ] \
          && [ "''${DELL_SUU_USE_MERGED_COMPLIANCE_CACHE:-0}" = 1 ]; then
          merge_support_compliance "$@"
          echo "Compliance report is generated successfully"
          echo "Progress report is available at:/usr/libexec/dell_dup/SUU_STATUS.json"
          echo "Exiting DSU!"
          exit 0
        fi

        if [ "$has_compliance" -eq 1 ]; then
          set +e
          "$(dirname "$0")/internalsuu.real" "$@"
          status=$?
          set -e
          if [ "''${DELL_SUU_ENABLE_SYNTHETIC_COMPLIANCE:-0}" = 1 ]; then
            merge_support_compliance "$@"
          fi
          exit "$status"
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
            download_dell_file "$rel_path" "$dest" "$catalog"
            verify_catalog_file "$catalog" "$rel_path" "$dest"
          fi
        else
          download_dell_file "$rel_path" "$dest" "$catalog"
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

      refresh_support_yum_for_suu() {
        local online_source repo
        online_source=$1
        repo="$online_source/repository"

        if [ "$(${coreutils}/bin/id -u)" -ne 0 ]; then
          echo "dell-suu: Dell platform support refresh needs root" >&2
          return 77
        fi

        if ! DELL_SUU_SUPPORT_NATIVE_CATALOG_ONLY="''${DELL_SUU_SUPPORT_NATIVE_CATALOG_ONLY:-0}" \
          DELL_SUU_SUPPORT_INCLUDE_NON_APPLICABLE="''${DELL_SUU_SUPPORT_INCLUDE_NON_APPLICABLE:-0}" \
          DELL_SUU_SUPPORT_CHECK_PLATFORM_DUPS="''${DELL_SUU_SUPPORT_CHECK_PLATFORM_DUPS:-1}" \
          DELL_SUU_SUPPORT_CHECK_WORKERS="''${DELL_SUU_SUPPORT_CHECK_WORKERS:-20}" \
          ${supportRefresh}/bin/dell-suu-support-refresh \
          --refresh \
          --source "$online_source" \
          --repo "$repo" \
          --cache-root "$cache_root"; then
          echo "dell-suu: Dell platform support package refresh failed" >&2
          return 1
        fi

        if [ ! -s /var/lib/dell/suu/support-upgrades.json ]; then
          echo "dell-suu: Dell platform support refresh did not produce a report" >&2
          return 1
        fi

        support_count=$(${jq}/bin/jq '[.SystemUpdateCompliance[0].UpdateableComponent[]?] | length' /var/lib/dell/suu/support-upgrades.json)
        echo "dell-suu: Dell platform support refresh prepared $support_count checked DUP update(s) for the GUI" >&2
      }

      prime_support_compliance_for_suu_gui() {
        local catalog_dir compliance_path host_compliance_path merged_count status
        catalog_dir=$1
        compliance_path=/usr/libexec/dell_dup/Compliance.json
        host_compliance_path=/var/cache/dell/dell_dup/suu/Compliance.json

        if [ ! -s /var/lib/dell/suu/support-upgrades.json ]; then
          echo "dell-suu: refusing to launch GUI without Dell support catalog data" >&2
          return 1
        fi

        if [ "''${DELL_SUU_GUI_NATIVE_PREFLIGHT_COMPLIANCE:-1}" != 0 ]; then
          echo "dell-suu: generating native Dell GUI compliance cache" >&2
          set +e
          DELL_SUU_USE_MERGED_COMPLIANCE_CACHE=0 \
            DELL_SUU_CATALOG_LOCATION="$catalog_dir" \
            ${fhs}/bin/dell-suu-fhs "$source_dir" --cli -- \
              --compliance \
              --catalog-location "$catalog_dir" \
              --output="$compliance_path"
          status=$?
          set -e
          case "$status" in
            0|34)
              ;;
            *)
              echo "dell-suu: native Dell compliance preflight failed with exit $status; continuing with checked poweredgec DUP compliance" >&2
              ;;
          esac
        fi

        if [ "''${DELL_SUU_GUI_MERGE_SUPPORT_COMPLIANCE:-1}" != 0 ]; then
          echo "dell-suu: merging checked Dell poweredgec DUP compliance for the GUI" >&2
          ${supportRefresh}/bin/dell-suu-support-refresh \
            --merge \
            --compliance "$host_compliance_path"
        fi

        if [ ! -s "$host_compliance_path" ]; then
          echo "dell-suu: refusing to launch GUI without $host_compliance_path" >&2
          return 1
        fi

        if [ ! -s /var/cache/dell/dell_dup/suu/SUU_STATUS.json ]; then
          echo "dell-suu: refusing to launch GUI without Dell SUU_STATUS.json" >&2
          return 1
        fi

        merged_count=$(${jq}/bin/jq '[.SystemUpdateCompliance[0].UpdateableComponent[]?] | length' "$host_compliance_path")
        echo "dell-suu: primed Dell GUI compliance cache with $merged_count component(s)" >&2
      }

      prepare_online_suu_source() {
        local base_source online_source repo dsu_cache catalog payloads_file inventory_path rel_path
        base_source=$1
        online_source=$(cached_online_source_dir)
        repo="$online_source/repository"
        dsu_cache=/var/cache/dell/dell_dup/dsu
        catalog="$dsu_cache/Catalog.xml"

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

        ${coreutils}/bin/sort -u "$payloads_file" | while IFS= read -r rel_path; do
          [ -n "$rel_path" ] || continue
          materialize_payload_for_suu "$dsu_cache" "$repo" "$catalog" "$rel_path"
        done

        ${coreutils}/bin/rm -f "$payloads_file"
        trap cleanup_mount EXIT

        if ! refresh_support_yum_for_suu "$online_source"; then
          return 1
        fi

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
          auto_download_iso="''${DELL_SUU_AUTO_DOWNLOAD_ISO:-}"
          if [ -z "$auto_download_iso" ]; then
            if [ "$mode" = gui ]; then
              auto_download_iso=1
            else
              auto_download_iso=0
            fi
          fi

          if [ -z "$iso" ] && [ "$auto_download_iso" = 1 ]; then
            echo "dell-suu: no cached SUU source or local ISO found; downloading SUU ISO first" >&2
            iso=$(download_iso)
          fi
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

      if [ "$mode" = gui ] && { [ "$refresh_catalog" -eq 1 ] || [ "$online_cache" -eq 1 ]; }; then
        prepared_online_source=0
        if [ "$online_cache" -eq 1 ] && [ "$refresh_catalog" -eq 0 ]; then
          if ! online_source=$(cached_online_source_if_present); then
            echo "dell-suu: cached online SUU source is missing; refusing to launch old ISO source" >&2
            echo "dell-suu: refresh through the GUI prompt or run with --refresh-catalog" >&2
            exit 1
          fi
        else
          if ! refresh_online_catalog; then
            echo "dell-suu: refusing to launch stale SUU source after refresh failure" >&2
            exit 1
          fi

          if ! online_source=$(prepare_online_suu_source "$source_dir"); then
            echo "dell-suu: refusing to launch stale SUU source after online repository preparation failure" >&2
            exit 1
          fi
          prepared_online_source=1
        fi

        prefer_upgrade_compliance_for_suu_gui "$online_source"
        clear_suu_runtime_state

        if [ "$prepared_online_source" -eq 0 ]; then
          if ! refresh_support_yum_for_suu "$online_source"; then
            echo "dell-suu: refusing to launch stale SUU source after online support repository repair failure" >&2
            exit 1
          fi
        fi

        source_dir=$online_source
        export DELL_SUU_CATALOG_LOCATION="$online_source/repository"
        export DELL_SUU_ENABLE_SYNTHETIC_COMPLIANCE="''${DELL_SUU_ENABLE_SYNTHETIC_COMPLIANCE:-1}"
        export DELL_SUU_USE_MERGED_COMPLIANCE_CACHE="''${DELL_SUU_USE_MERGED_COMPLIANCE_CACHE:-1}"
        if ! prime_support_compliance_for_suu_gui "$online_source/repository"; then
          echo "dell-suu: refusing to launch stale SUU GUI before compliance cache is ready" >&2
          exit 1
        fi
        echo "dell-suu: support cache is complete; launching Dell SUU GUI" >&2
      fi

      if [ "$mode" = gui ] && ! source_is_writable "$source_dir"; then
        echo "dell-suu: GUI source is read-only; refresh Dell cache first so SUU opens a writable online source" >&2
        exit 66
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

      ${fhs}/bin/dell-suu-fhs "''${fhs_args[@]}"
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
      env_args=()
      sudo_bin=/run/wrappers/bin/sudo
      tmux_socket="''${DELL_SUU_TMUX_SOCKET:-}"
      tmux_session="''${DELL_SUU_TMUX_SESSION:-dell-suu}"
      tmux_command=

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

      if [ -z "$tmux_socket" ]; then
        if [ -d "$runtime_dir" ]; then
          tmux_socket="$runtime_dir/dell-suu.tmux"
        else
          tmux_socket="/tmp/dell-suu-$user_id.tmux"
        fi
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

      cache_is_fresh=0
      cache_exists=0
      use_online_cache=0
      cache_max_age="''${DELL_SUU_REFRESH_MAX_AGE_SECONDS:-21600}"
      if [[ "$cache_max_age" =~ ^[0-9]+$ ]] && [ "$cache_max_age" -gt 0 ]; then
        online_source=/var/cache/dell/suu/online-source
        source_catalog="$online_source/repository/Catalog.xml"
        support_report=/var/lib/dell/suu/support-upgrades.json
        support_manifest=/var/lib/dell/suu/support-refresh-manifest.json
        cache_as_root=()
        if [ "$user_id" -ne 0 ]; then
          cache_as_root=("$sudo_bin" -n)
        fi

        if "''${cache_as_root[@]}" ${coreutils}/bin/test -x "$online_source/suulauncher" 2>/dev/null \
          && "''${cache_as_root[@]}" ${coreutils}/bin/test -x "$online_source/internalsuu" 2>/dev/null \
          && "''${cache_as_root[@]}" ${coreutils}/bin/test -s "$source_catalog" 2>/dev/null \
          && "''${cache_as_root[@]}" ${coreutils}/bin/test -s "$support_report" 2>/dev/null \
          && "''${cache_as_root[@]}" ${coreutils}/bin/test -s "$support_manifest" 2>/dev/null; then
          cache_exists=1
          source_mtime=$("''${cache_as_root[@]}" ${coreutils}/bin/stat -c %Y "$source_catalog")
          support_mtime=$("''${cache_as_root[@]}" ${coreutils}/bin/stat -c %Y "$support_report")
          oldest_mtime=$source_mtime
          if [ "$support_mtime" -lt "$oldest_mtime" ]; then
            oldest_mtime=$support_mtime
          fi

          now=$(${coreutils}/bin/date +%s)
          if [ "$((now - oldest_mtime))" -le "$cache_max_age" ]; then
            cache_is_fresh=1
          fi
        fi
      fi

      refresh_catalog=0
      case "''${DELL_SUU_REFRESH_CATALOG:-ask}" in
        1|yes|true|refresh|fresh|update)
          refresh_catalog=1
          ;;
        0|no|false)
          refresh_catalog=0
          ;;
        cache|cached|online|online-cache|use-cache)
          use_online_cache=1
          refresh_catalog=0
          ;;
        *)
          if [ "$cache_is_fresh" -eq 1 ]; then
            if [ -n "$display" ]; then
              choice=$(${zenity}/bin/zenity \
                --list \
                --title "Dell Server Update Utility" \
                --text "The refreshed Dell cache is less than 6 hours old. Choose what SUU should open." \
                --width 760 \
                --height 260 \
                --column "Mode" \
                --column "Details" \
                "Use refreshed Dell cache" "Open the cached Dell online catalog and downloaded matching packages." \
                "Use ISO-only inventory" "Open the bundled SUU ISO repository without Dell online support updates.") || exit 0
              case "$choice" in
                "Use refreshed Dell cache")
                  use_online_cache=1
                  ;;
                "Use ISO-only inventory")
                  refresh_catalog=0
                  ;;
                *)
                  exit 0
                  ;;
              esac
            else
              use_online_cache=1
              refresh_catalog=0
            fi
          elif [ -n "$display" ]; then
            if [ "$cache_exists" -eq 1 ]; then
              choice=$(${zenity}/bin/zenity \
                --list \
                --title "Dell Server Update Utility" \
                --text "The refreshed Dell cache is older than 6 hours. Choose what SUU should open." \
                --width 820 \
                --height 300 \
                --column "Mode" \
                --column "Details" \
                "Refresh Dell cache first" "Fetch Dell's current online catalog and matching packages, then open SUU." \
                "Use refreshed Dell cache" "Open the existing cached Dell online catalog without downloading again." \
                "Use ISO-only inventory" "Open the bundled SUU ISO repository without Dell online support updates.") || exit 0
            else
              choice=$(${zenity}/bin/zenity \
                --list \
                --title "Dell Server Update Utility" \
                --text "No refreshed Dell cache is available. Choose what SUU should open." \
                --width 820 \
                --height 260 \
                --column "Mode" \
                --column "Details" \
                "Refresh Dell cache first" "Fetch Dell's current online catalog and matching packages, then open SUU." \
                "Use ISO-only inventory" "Open the bundled SUU ISO repository without Dell online support updates.") || exit 0
            fi

            case "$choice" in
              "Refresh Dell cache first")
                refresh_catalog=1
                ;;
              "Use refreshed Dell cache")
                use_online_cache=1
                ;;
              "Use ISO-only inventory")
                refresh_catalog=0
                ;;
              *)
                exit 0
                ;;
            esac
          fi
          ;;
      esac

      suu_args=(${suu}/bin/dell-suu --gui)
      if [ "$refresh_catalog" -eq 1 ]; then
        suu_args+=(--refresh-catalog)
      elif [ "$use_online_cache" -eq 1 ]; then
        suu_args+=(--online-cache)
      fi

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

      for name in "''${!DELL_SUU_@}"; do
        env_args+=("$name=''${!name}")
      done

      if [ "$(${coreutils}/bin/id -u)" -ne 0 ] && [ ! -x "$sudo_bin" ]; then
        echo "dell-suu-gui: $sudo_bin is unavailable; enable sudo or run as root" >&2
        exit 69
      fi

      append_tmux_arg() {
        local quoted
        printf -v quoted '%q' "$1"
        if [ -z "$tmux_command" ]; then
          tmux_command=$quoted
        else
          tmux_command="$tmux_command $quoted"
        fi
      }

      append_tmux_arg ${guiTmuxRunner}/bin/dell-suu-gui-tmux-runner

      if [ "$(${coreutils}/bin/id -u)" -ne 0 ]; then
        append_tmux_arg "$sudo_bin"
      fi

      append_tmux_arg ${coreutils}/bin/env
      for arg in "''${env_args[@]}" "''${suu_args[@]}" "$@"; do
        append_tmux_arg "$arg"
      done

      if [ -z "$display" ]; then
        echo "dell-suu-gui: no X display found; refusing to start Dell GUI without a visible Xorg terminal" >&2
        echo "dell-suu-gui: set DISPLAY/XAUTHORITY or run from the active i3/Xorg session" >&2
        exit 69
      fi

      if ! ${tmux}/bin/tmux -S "$tmux_socket" list-sessions >/dev/null 2>&1; then
        ${coreutils}/bin/rm -f "$tmux_socket"
      fi

      echo "dell-suu-gui: opening visible Xorg terminal attached to tmux socket $tmux_socket session $tmux_session" >&2
      exec ${xterm}/bin/xterm \
        -hold \
        -T "Dell Server Update Utility" \
        -geometry 140x42 \
        -e ${tmux}/bin/tmux -S "$tmux_socket" new-session -A -s "$tmux_session" "$tmux_command"
    '';
  };

  guiTmuxRunner = writeShellApplication {
    name = "dell-suu-gui-tmux-runner";

    runtimeInputs = [
      bashInteractive
    ];

    text = ''
      set +e

      "$@"
      status=$?

      printf '\nDell Server Update Utility exited with status %s\n' "$status" >&2
      printf 'Leaving this tmux pane open for inspection. Exit the shell to close it.\n' >&2
      exec ${bashInteractive}/bin/bash -i
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
