{ ansible
, fetchurl
, lib
, makeWrapper
, python312Packages
, stdenvNoCC
}:

let
  python3Packages = python312Packages;

  omsdk = python3Packages.buildPythonPackage rec {
    pname = "omsdk";
    version = "1.2.518";
    format = "wheel";

    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/cc/04/4321810d43e37ca07f46680f2622072af1eb15dcf33b33ab5ab09268a0e6/omsdk-1.2.518-py2.py3-none-any.whl";
      hash = "sha256-0K462hGCyisDrN1ayzxz1zC/fiYmK7TtXP+tconRpXE=";
    };

    dependencies = with python3Packages; [
      future
      pysnmp
      pyyaml
      requests
    ];

    pythonRemoveDeps = [
      "enum34"
      "ipaddress"
      "pysnmp-mibs"
    ];

    doCheck = false;

    meta = {
      description = "Dell OpenManage SDK";
      homepage = "https://github.com/dell/omsdk";
      license = lib.licenses.asl20;
    };
  };

  pythonEnv = python3Packages.python.withPackages (ps: [
    omsdk
    ps.ansible-core
    ps.future
    ps.netaddr
    ps.pysnmp
    ps.pyyaml
    ps.requests
    ps.urllib3
  ]);

  collectionsPath = "$out/share/ansible/collections";
  collectionRoot = "${collectionsPath}/ansible_collections";
  pythonPath = "${collectionsPath}:${pythonEnv}/${python3Packages.python.sitePackages}";

  dellemcOpenmanage = fetchurl {
    url = "https://galaxy.ansible.com/download/dellemc-openmanage-10.0.3.tar.gz";
    hash = "sha256-MdetOqDTPrkulmvqhM17jTmO8IsWRiu95pstikuQMq8=";
  };

  ansibleUtils = fetchurl {
    url = "https://galaxy.ansible.com/download/ansible-utils-6.0.3.tar.gz";
    hash = "sha256-UrUzFfJ038woDeL0T0Lzo3a24nuWQVhAfCZSqStQFP8=";
  };

  ansibleWindows = fetchurl {
    url = "https://galaxy.ansible.com/download/ansible-windows-3.6.1.tar.gz";
    hash = "sha256-1pt59YgWcN56v1POV4XppzoKBMr9aw2mgCnNmwA1U68=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "dell-openmanage";
  version = "10.0.3";

  dontUnpack = true;

  nativeBuildInputs = [
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall

    install_collection() {
      namespace=$1
      name=$2
      tarball=$3

      mkdir -p "${collectionRoot}/$namespace/$name"
      tar -xzf "$tarball" -C "${collectionRoot}/$namespace/$name"
    }

    install_collection dellemc openmanage ${dellemcOpenmanage}
    install_collection ansible utils ${ansibleUtils}
    install_collection ansible windows ${ansibleWindows}

    mkdir -p "$out/bin" "$out/share/dell-openmanage/playbooks"

    for tool in ansible ansible-config ansible-doc ansible-galaxy ansible-inventory ansible-playbook; do
      makeWrapper "${ansible}/bin/$tool" "$out/bin/dell-openmanage-$tool" \
        --set ANSIBLE_COLLECTIONS_PATH "${collectionsPath}" \
        --set ANSIBLE_PYTHON_INTERPRETER "${pythonEnv}/bin/python" \
        --prefix PATH : ${lib.makeBinPath [ pythonEnv ]} \
        --prefix PYTHONPATH : "${pythonPath}"
    done

    cat > "$out/share/dell-openmanage/playbooks/idrac-firmware-report.yml" <<'YAML'
    ---
    - name: Dell iDRAC firmware compliance report
      hosts: localhost
      gather_facts: false
      tasks:
        - name: Generate firmware compliance from Dell repository
          dellemc.openmanage.idrac_firmware:
            idrac_ip: "{{ lookup('env', 'IDRAC_HOST') }}"
            idrac_user: "{{ lookup('env', 'IDRAC_USER') }}"
            idrac_password: "{{ lookup('env', 'IDRAC_PASSWORD') }}"
            ca_path: "{{ lookup('env', 'IDRAC_CA_PATH') | default(omit, true) }}"
            validate_certs: "{{ (lookup('env', 'IDRAC_VALIDATE_CERTS') | default('false', true)) | bool }}"
            share_name: "{{ lookup('env', 'DELL_FIRMWARE_REPO') | default('https://downloads.dell.com', true) }}"
            catalog_file_name: "{{ lookup('env', 'DELL_FIRMWARE_CATALOG') | default('Catalog.xml', true) }}"
            apply_update: false
            reboot: false
          register: firmware_report

        - name: Show firmware compliance
          ansible.builtin.debug:
            var: firmware_report
    YAML

    cat > "$out/share/dell-openmanage/playbooks/idrac-firmware-update.yml" <<'YAML'
    ---
    - name: Dell iDRAC firmware update
      hosts: localhost
      gather_facts: false
      tasks:
        - name: Apply firmware updates from Dell repository
          dellemc.openmanage.idrac_firmware:
            idrac_ip: "{{ lookup('env', 'IDRAC_HOST') }}"
            idrac_user: "{{ lookup('env', 'IDRAC_USER') }}"
            idrac_password: "{{ lookup('env', 'IDRAC_PASSWORD') }}"
            ca_path: "{{ lookup('env', 'IDRAC_CA_PATH') | default(omit, true) }}"
            validate_certs: "{{ (lookup('env', 'IDRAC_VALIDATE_CERTS') | default('false', true)) | bool }}"
            share_name: "{{ lookup('env', 'DELL_FIRMWARE_REPO') | default('https://downloads.dell.com', true) }}"
            catalog_file_name: "{{ lookup('env', 'DELL_FIRMWARE_CATALOG') | default('Catalog.xml', true) }}"
            apply_update: true
            reboot: "{{ (lookup('env', 'DELL_FIRMWARE_REBOOT') | default('true', true)) | bool }}"
            job_wait: "{{ (lookup('env', 'DELL_FIRMWARE_JOB_WAIT') | default('true', true)) | bool }}"
          register: firmware_update

        - name: Show firmware update result
          ansible.builtin.debug:
            var: firmware_update
    YAML

    cat > "$out/share/dell-openmanage/playbooks/idrac-nixos-boot-iso.yml" <<'YAML'
    ---
    - name: Boot a NixOS installer ISO through iDRAC virtual media
      hosts: localhost
      gather_facts: false
      tasks:
        - name: Insert NixOS installer ISO as virtual media
          dellemc.openmanage.idrac_virtual_media:
            idrac_ip: "{{ lookup('env', 'IDRAC_HOST') }}"
            idrac_user: "{{ lookup('env', 'IDRAC_USER') }}"
            idrac_password: "{{ lookup('env', 'IDRAC_PASSWORD') }}"
            ca_path: "{{ lookup('env', 'IDRAC_CA_PATH') | default(omit, true) }}"
            validate_certs: "{{ (lookup('env', 'IDRAC_VALIDATE_CERTS') | default('false', true)) | bool }}"
            force: true
            virtual_media:
              - index: "{{ lookup('env', 'IDRAC_VIRTUAL_MEDIA_INDEX') | default(1, true) }}"
                insert: true
                image: "{{ lookup('env', 'NIXOS_ISO_URL') }}"
                media_type: CD

        - name: One-shot boot from virtual CD
          dellemc.openmanage.idrac_boot:
            idrac_ip: "{{ lookup('env', 'IDRAC_HOST') }}"
            idrac_user: "{{ lookup('env', 'IDRAC_USER') }}"
            idrac_password: "{{ lookup('env', 'IDRAC_PASSWORD') }}"
            ca_path: "{{ lookup('env', 'IDRAC_CA_PATH') | default(omit, true) }}"
            validate_certs: "{{ (lookup('env', 'IDRAC_VALIDATE_CERTS') | default('false', true)) | bool }}"
            boot_source_override_mode: uefi
            boot_source_override_target: cd
            boot_source_override_enabled: once
            reset_type: "{{ lookup('env', 'IDRAC_BOOT_RESET_TYPE') | default('force_restart', true) }}"
            job_wait: "{{ (lookup('env', 'IDRAC_BOOT_JOB_WAIT') | default('false', true)) | bool }}"
    YAML

    cat > "$out/share/dell-openmanage/playbooks/idrac-import-https-cert.yml" <<'YAML'
    ---
    - name: Import an iDRAC HTTPS certificate
      hosts: localhost
      gather_facts: false
      tasks:
        - name: Import iDRAC HTTPS certificate
          dellemc.openmanage.idrac_certificates:
            idrac_ip: "{{ lookup('env', 'IDRAC_HOST') }}"
            idrac_user: "{{ lookup('env', 'IDRAC_USER') }}"
            idrac_password: "{{ lookup('env', 'IDRAC_PASSWORD') }}"
            ca_path: "{{ lookup('env', 'IDRAC_CA_PATH') | default(omit, true) }}"
            validate_certs: "{{ (lookup('env', 'IDRAC_VALIDATE_CERTS') | default('false', true)) | bool }}"
            command: import
            certificate_type: HTTPS
            certificate_path: "{{ lookup('env', 'IDRAC_CERT_PATH') }}"
            ssl_key: "{{ lookup('env', 'IDRAC_SSL_KEY_PATH') | default(omit, true) }}"
    YAML

    cat > "$out/bin/dell-idrac-firmware-report" <<'EOF'
    #!@shell@
    set -eu

    load_secret_env() {
      var=$1
      file_var=''${var}_FILE
      eval "value=\''${$var-}"
      eval "file=\''${$file_var-}"

      if [ -z "$value" ] && [ -n "$file" ]; then
        if [ ! -r "$file" ]; then
          echo "cannot read secret file for $var: $file" >&2
          exit 66
        fi
        IFS= read -r value < "$file" || value=
        export "$var=$value"
      fi

      if [ -z "$value" ]; then
        echo "missing required environment variable: $var or $file_var" >&2
        exit 64
      fi
    }

    for var in IDRAC_HOST IDRAC_USER IDRAC_PASSWORD; do
      load_secret_env "$var"
    done

    exec "@ansible_playbook@" -i localhost, -c local "@playbook_dir@/idrac-firmware-report.yml" "$@"
    EOF

    cat > "$out/bin/dell-idrac-firmware-update" <<'EOF'
    #!@shell@
    set -eu

    if [ "''${1:-}" != "--yes" ]; then
      echo "usage: dell-idrac-firmware-update --yes" >&2
      echo "this schedules/applies firmware through iDRAC; run dell-idrac-firmware-report first" >&2
      exit 64
    fi
    shift

    load_secret_env() {
      var=$1
      file_var=''${var}_FILE
      eval "value=\''${$var-}"
      eval "file=\''${$file_var-}"

      if [ -z "$value" ] && [ -n "$file" ]; then
        if [ ! -r "$file" ]; then
          echo "cannot read secret file for $var: $file" >&2
          exit 66
        fi
        IFS= read -r value < "$file" || value=
        export "$var=$value"
      fi

      if [ -z "$value" ]; then
        echo "missing required environment variable: $var or $file_var" >&2
        exit 64
      fi
    }

    for var in IDRAC_HOST IDRAC_USER IDRAC_PASSWORD; do
      load_secret_env "$var"
    done

    exec "@ansible_playbook@" -i localhost, -c local "@playbook_dir@/idrac-firmware-update.yml" "$@"
    EOF

    cat > "$out/bin/dell-idrac-nixos-boot-iso" <<'EOF'
    #!@shell@
    set -eu

    load_secret_env() {
      var=$1
      file_var=''${var}_FILE
      eval "value=\''${$var-}"
      eval "file=\''${$file_var-}"

      if [ -z "$value" ] && [ -n "$file" ]; then
        if [ ! -r "$file" ]; then
          echo "cannot read secret file for $var: $file" >&2
          exit 66
        fi
        IFS= read -r value < "$file" || value=
        export "$var=$value"
      fi

      if [ -z "$value" ]; then
        echo "missing required environment variable: $var or $file_var" >&2
        exit 64
      fi
    }

    for var in IDRAC_HOST IDRAC_USER IDRAC_PASSWORD NIXOS_ISO_URL; do
      load_secret_env "$var"
    done

    exec "@ansible_playbook@" -i localhost, -c local "@playbook_dir@/idrac-nixos-boot-iso.yml" "$@"
    EOF

    cat > "$out/bin/dell-idrac-import-https-cert" <<'EOF'
    #!@shell@
    set -eu

    load_secret_env() {
      var=$1
      file_var=''${var}_FILE
      eval "value=\''${$var-}"
      eval "file=\''${$file_var-}"

      if [ -z "$value" ] && [ -n "$file" ]; then
        if [ ! -r "$file" ]; then
          echo "cannot read secret file for $var: $file" >&2
          exit 66
        fi
        IFS= read -r value < "$file" || value=
        export "$var=$value"
      fi

      if [ -z "$value" ]; then
        echo "missing required environment variable: $var or $file_var" >&2
        exit 64
      fi
    }

    for var in IDRAC_HOST IDRAC_USER IDRAC_PASSWORD IDRAC_CERT_PATH; do
      load_secret_env "$var"
    done

    exec "@ansible_playbook@" -i localhost, -c local "@playbook_dir@/idrac-import-https-cert.yml" "$@"
    EOF

    for script in "$out"/bin/dell-idrac-*; do
      substituteInPlace "$script" \
        --replace-fail @shell@ "${stdenvNoCC.shell}" \
        --replace-fail @ansible_playbook@ "$out/bin/dell-openmanage-ansible-playbook" \
        --replace-fail @playbook_dir@ "$out/share/dell-openmanage/playbooks"
    done

    chmod 0755 "$out"/bin/dell-idrac-*

    runHook postInstall
  '';

  meta = {
    description = "Dell OpenManage Ansible collection and iDRAC automation wrappers for reproducible server operations";
    homepage = "https://galaxy.ansible.com/ui/repo/published/dellemc/openmanage/";
    license = lib.licenses.gpl3Plus;
    mainProgram = "dell-openmanage-ansible-playbook";
    platforms = [ "x86_64-linux" ];
  };
}
