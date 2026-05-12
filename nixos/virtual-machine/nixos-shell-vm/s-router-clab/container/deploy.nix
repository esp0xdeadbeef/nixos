{ pkgs, ... }:
let
  s-router-clab-deploy = pkgs.writeShellScriptBin "s-router-clab-deploy" ''
        set -euo pipefail

        export NIX_CONFIG="experimental-features = nix-command flakes"

        renderer_repo="''${CLAB_RENDERER_REPO:-/run/s-router-clab/inputs/network-renderer-containerlab-linux-backend}"
        labs_repo="''${CLAB_NETWORK_LABS:-/run/s-router-clab/inputs/network-labs}"
        cpm_repo="''${CLAB_CONTROL_PLANE_MODEL:-/run/s-router-clab/inputs/network-control-plane-model}"
        work_dir="''${1:-/run/s-router-clab/live-$(date +%s)}"
        example_dir="$labs_repo/labs/lab-s-sigma/s-router-test-three-site"

        mkdir -p "$work_dir"
        cat > "$work_dir/resolved-inventory-clab.nix" <<EOF
        import "$example_dir/getResolvedInventory.nix" { renderer = "clab"; }
        EOF

        nix run --show-trace "path:$cpm_repo#compile-and-build-control-plane-model" -- \
          "$example_dir/intent.nix" \
          "$work_dir/resolved-inventory-clab.nix" \
          "$work_dir/cpm.json"

        nix eval --impure --json --expr "import $work_dir/resolved-inventory-clab.nix" \
          > "$work_dir/renderer-inventory.json"

        CLABGEN_RENDERER_INVENTORY_JSON="$work_dir/renderer-inventory.json" \
          nix run --show-trace "path:$renderer_repo#generate-clab-config" -- \
            "$work_dir/cpm.json" \
            "$work_dir/fabric.clab.yml" \
            "$work_dir/vm-bridges-generated.nix"

        python3 - "$work_dir/vm-bridges-generated.nix" "$work_dir/setup-vlan-links.sh" <<'PY'
    import json
    import re
    import sys
    from pathlib import Path

    bridges = Path(sys.argv[1]).read_text()
    script_path = Path(sys.argv[2])
    quote = chr(39) * 2
    pattern = r"bridgeNetworks = builtins\.fromJSON " + quote + r"\n(.*)\n  " + quote + ";"
    match = re.search(pattern, bridges, re.S)
    if not match:
        raise SystemExit("missing bridgeNetworks JSON")

    bridge_networks = json.loads(match.group(1))
    commands = ["set -euo pipefail"]
    for bridge_name, bridge_data in sorted(bridge_networks.items()):
        if not isinstance(bridge_data, dict):
            continue
        if bridge_data.get("mode") != "vlan":
            continue
        parent = bridge_data.get("parent")
        vlan = bridge_data.get("vlan")
        if not isinstance(parent, str) or not isinstance(vlan, int):
            continue
        interface = f"{parent}.{vlan}"
        commands.append(f"ip link show dev {interface} >/dev/null 2>&1 || ip link add link {parent} name {interface} type vlan id {vlan}")
        commands.append(f"ip link set dev {interface} up")

    script_path.write_text("\n".join(commands) + "\n")
    PY
        bash "$work_dir/setup-vlan-links.sh"

        python3 - "$work_dir/fabric.clab.yml" "$work_dir/fabric.no-overlay.clab.yml" <<'PY'
    import sys
    from pathlib import Path

    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    lines = source.read_text().splitlines()
    output = []
    index = 0
    removed = 0

    while index < len(lines):
        line = lines[index]
        if line.startswith("  - endpoints:"):
            block = [line]
            index += 1
            while index < len(lines) and not lines[index].startswith("  - endpoints:"):
                block.append(lines[index])
                index += 1
            if any("clab.link.type: overlay" in item for item in block):
                removed += 1
                continue
            output.extend(block)
            continue
        output.append(line)
        index += 1

    if removed:
        print(f"warning: skipped {removed} overlay link(s) for local no-Hetzner CLAB deploy", file=sys.stderr)

    target.write_text("\n".join(output) + "\n")
    PY

        ln -sfn "$work_dir" /run/s-router-clab/live-current
        containerlab destroy --name fabric -c || true
        containerlab deploy -t "$work_dir/fabric.no-overlay.clab.yml" -d --reconfigure
  '';
in
{
  environment.systemPackages = [ s-router-clab-deploy ];
}
