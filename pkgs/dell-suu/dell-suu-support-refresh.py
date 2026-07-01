import argparse
import concurrent.futures
import copy
import csv
import fcntl
import gzip
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

FHS = os.environ.get("DELL_SUU_FHS", "dell-suu-fhs")
BSDTAR = os.environ.get("DELL_SUU_BSDTAR", "bsdtar")
DMIDECODE = os.environ.get("DELL_SUU_DMIDECODE", "dmidecode")
HWINFO = os.environ.get("DELL_SUU_HWINFO", "hwinfo")
IPMITOOL = os.environ.get("DELL_SUU_IPMITOOL", "ipmitool")
LSPCI = os.environ.get("DELL_SUU_LSPCI", "lspci")
LSHW = os.environ.get("DELL_SUU_LSHW", "lshw")

DEFAULT_REPO_BASE = "https://linux.dell.com/repo/hardware/"
DEFAULT_PLATFORM_CSV_BASE = "https://poweredgec.dell.com"
DEFAULT_PLATFORM_GENERATION_SCAN = tuple(range(17, 9, -1))
USER_AGENT = "Mozilla/5.0"
SUPPORT_REPORT = Path("/var/lib/dell/suu/support-upgrades.json")
SUPPORT_STAMP = Path("/var/lib/dell/suu/support-refresh.stamp")
SUPPORT_MANIFEST = Path("/var/lib/dell/suu/support-refresh-manifest.json")
NATIVE_COMPLIANCE_CACHE = Path("/var/lib/dell/suu/native-compliance.json")
SUPPORT_REPORT_SCHEMA_VERSION = 2
DUP_LOCK = threading.Lock()
DUP_LOCK_PATH = Path(os.environ.get("DELL_SUU_DUP_LOCK", "/run/lock/dell-suu-dup.lock"))
FILE_LOCKS = {}
FILE_LOCKS_LOCK = threading.Lock()
HASH_CHUNK_SIZE = 4 * 1024 * 1024

XML_NS = {"m": "http://linux.duke.edu/metadata/common"}
POWEREDGE_MODEL_RE = re.compile(
    r"(?:PowerEdge\s+)?([A-Z]{1,3}\d{3,4}[A-Z]*|XE\d{3,4}|MX\d{4}[A-Z]*)",
    flags=re.I,
)


def env_flag(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in {"1", "yes", "true", "on"}


def env_int(name, default):
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        print(f"dell-suu: ignoring invalid {name}={value!r}", file=sys.stderr)
        return default


def support_cache_settings():
    return {
        "nativeCatalogOnly": env_flag("DELL_SUU_SUPPORT_NATIVE_CATALOG_ONLY", False),
        "includeNonApplicable": env_flag(
            "DELL_SUU_SUPPORT_INCLUDE_NON_APPLICABLE", False
        ),
        "trustPlatformCsv": env_flag("DELL_SUU_SUPPORT_TRUST_PLATFORM_CSV", True),
        "checkPlatformDups": env_flag("DELL_SUU_SUPPORT_CHECK_PLATFORM_DUPS", True),
    }


def hardware_fingerprint(dmidecode_data=None, inventory=None):
    dmidecode_data = dmidecode_data or parse_dmidecode()
    inventory = inventory or parse_inventory()
    relevant = {
        "product": one_line_text(dmidecode_data.get("product")),
        "sku": one_line_text(dmidecode_data.get("sku")),
        "biosVersion": one_line_text(dmidecode_data.get("bios_version")),
        "baseboard": one_line_text(dmidecode_data.get("baseboard")),
        "systemID": one_line_text(inventory.get("system_id")),
        "components": sorted(
            {
                (
                    one_line_text(component.get("component_id")),
                    one_line_text(component.get("display")),
                    one_line_text(component.get("version")),
                    one_line_text(component.get("component_type")),
                    tuple(component.get("pci") or ("", "", "", "")),
                )
                for component in inventory.get("components", [])
            }
        ),
    }
    encoded = json.dumps(relevant, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode()).hexdigest()


def fetch_bytes(url, timeout=45):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def file_lock(path):
    key = str(path)
    with FILE_LOCKS_LOCK:
        lock = FILE_LOCKS.get(key)
        if lock is None:
            lock = threading.RLock()
            FILE_LOCKS[key] = lock
        return lock


def sha512_marker_path(path):
    return Path(str(path) + ".sha512")


def sha512_marker_matches(path, expected):
    marker = sha512_marker_path(path)
    if not marker.exists():
        return False

    path_stat = path.stat()
    if marker.stat().st_mtime < path_stat.st_mtime:
        return False

    text = marker.read_text(errors="replace")
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        parts = text.split()
        return bool(parts) and parts[0].lower() == expected.lower()

    return (
        data.get("sha512", "").lower() == expected.lower()
        and data.get("size") == path_stat.st_size
    )


def write_sha512_marker(path, digest):
    marker = sha512_marker_path(path)
    marker.write_text(
        json.dumps({"sha512": digest, "size": path.stat().st_size}) + "\n"
    )


def cached_sha512_matches(path, expected):
    if not expected:
        return True

    expected = expected.lower()
    if sha512_marker_matches(path, expected):
        return True

    with file_lock(path):
        if sha512_marker_matches(path, expected):
            return True

        actual = sha512_file(path)
        if actual == expected:
            write_sha512_marker(path, actual)
            return True

        sha512_marker_path(path).unlink(missing_ok=True)
        return False


def download_file(url, dest, checksum_type="", checksum=""):
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    checksum = (checksum or "").lower()
    hasher = hashlib.sha512() if checksum_type == "sha512" and checksum else None

    with urllib.request.urlopen(request, timeout=120) as response, part.open(
        "wb"
    ) as out:
        while True:
            chunk = response.read(HASH_CHUNK_SIZE)
            if not chunk:
                break
            out.write(chunk)
            if hasher is not None:
                hasher.update(chunk)

    if hasher is not None:
        actual = hasher.hexdigest()
        if actual != checksum.lower():
            part.unlink(missing_ok=True)
            raise RuntimeError(f"SHA-512 mismatch for {dest.name}")

    part.replace(dest)
    if hasher is not None:
        write_sha512_marker(dest, actual)


def sha512_file(path):
    digest = hashlib.sha512()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalise_text(value):
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def one_line_text(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def natural_key(value):
    parts = re.split(r"(\d+)", value or "")
    return tuple(
        (0, int(part)) if part.isdigit() else (1, part.lower()) for part in parts
    )


def version_tuple(value):
    parts = []
    for part in re.split(r"[^0-9]+", value or ""):
        if part:
            parts.append(int(part))
    return tuple(parts)


def version_desc_key(value, width=8):
    parts = version_tuple(value)
    padded = (parts + (0,) * width)[:width]
    return tuple(-part for part in padded)


def newer_version(candidate, installed):
    c = version_tuple(candidate)
    i = version_tuple(installed)
    return bool(c and i and c > i)


def normalize_system_id(value):
    value = (value or "").strip().upper()
    if value.startswith("0X"):
        value = value[2:]
    value = re.sub(r"[^0-9A-F]", "", value)
    if not value:
        return ""
    return value.zfill(4)


def normalize_pci_id(value):
    value = (value or "").strip().upper()
    if value.startswith("0X"):
        value = value[2:]
    value = re.sub(r"[^0-9A-F]", "", value)
    return value.zfill(4) if value else ""


def pci_tuple(attrs):
    return (
        normalize_pci_id(attrs.get("vendorID", "")),
        normalize_pci_id(attrs.get("deviceID", "")),
        normalize_pci_id(attrs.get("subVendorID", "")),
        normalize_pci_id(attrs.get("subDeviceID", "")),
    )


def pci_tuple_has_data(value):
    return any(value)


def pci_tuple_matches(package_pci, inventory_pci):
    return all(
        not expected or expected == actual
        for expected, actual in zip(package_pci, inventory_pci)
    )


def run(cmd, timeout=300, check=False):
    proc = subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
        env={**os.environ, "TERM": "xterm", "COLUMNS": "120", "LINES": "40"},
    )
    if check and proc.returncode != 0:
        raise RuntimeError(proc.stdout)
    return proc


def run_dup(cmd, timeout=300, check=False, locked=True):
    if not locked:
        return run(cmd, timeout=timeout, check=check)
    with DUP_LOCK:
        DUP_LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        with DUP_LOCK_PATH.open("a+") as lock_file:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            try:
                return run(cmd, timeout=timeout, check=check)
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


def parse_dmidecode():
    data = {"product": "", "sku": "", "bios_version": "", "baseboard": ""}
    try:
        proc = run(
            [DMIDECODE, "-t", "system", "-t", "bios", "-t", "baseboard"], timeout=30
        )
    except Exception:
        return data

    current = None
    for raw in proc.stdout.splitlines():
        line = raw.rstrip()
        if line and not line.startswith("\t"):
            current = line.rstrip(":")
            continue
        if ":" not in line:
            continue
        key, value = [part.strip() for part in line.split(":", 1)]
        if current == "System Information":
            if key == "Product Name":
                data["product"] = value
            elif key == "SKU Number":
                data["sku"] = value
        elif current == "BIOS Information" and key == "Version":
            data["bios_version"] = value
        elif current == "Base Board Information" and key == "Product Name":
            data["baseboard"] = value
    return data


def inventory_relevant_display(value):
    return bool(
        re.search(
            r"\b(3d|backplane|bmc|controller|cntlr|display|ethernet|gfx|graphics|gpu|idrac|infiniband|lifecycle|network|nic|non-volatile|nvme|perc|power supply|raid|sas|storage|vga)\b",
            value or "",
            re.I,
        )
    )


def merge_inventory_component(inventory, component_index, component):
    if not (
        component.get("display")
        or component.get("component_id")
        or pci_tuple_has_data(component.get("pci") or ("", "", "", ""))
    ):
        return

    key = (
        component.get("component_id", ""),
        component.get("display", ""),
        component.get("pci") or ("", "", "", ""),
    )
    existing = component_index.get(key)
    if existing is None:
        component_index[key] = component
        inventory["components"].append(component)
        return

    for field in ("version", "component_type", "source"):
        if not existing.get(field) and component.get(field):
            existing[field] = component[field]


def parse_ipmitool_fru_components():
    try:
        proc = run([IPMITOOL, "fru"], timeout=60)
    except Exception:
        return []
    if proc.returncode != 0:
        return []

    components = []
    current = {}
    description = ""

    def flush():
        if not current and not description:
            return
        display = (
            current.get("Board Product")
            or current.get("Product Name")
            or current.get("Product Part Number")
            or ""
        ).strip()
        combined = " ".join([description, display])
        if display and inventory_relevant_display(combined):
            components.append(
                {
                    "component_id": "",
                    "display": display,
                    "version": "",
                    "component_type": "FRMW",
                    "pci": ("", "", "", ""),
                    "source": "ipmitool-fru",
                }
            )

    for raw in proc.stdout.splitlines():
        line = raw.strip()
        if not line:
            flush()
            current = {}
            description = ""
            continue
        if ":" not in line:
            continue
        key, value = [part.strip() for part in line.split(":", 1)]
        if key == "FRU Device Description":
            flush()
            current = {}
            description = value
            continue
        current[key] = value

    flush()
    return components


def lshw_nodes(node):
    if isinstance(node, list):
        for item in node:
            yield from lshw_nodes(item)
        return
    if not isinstance(node, dict):
        return
    yield node
    for child in node.get("children", []) or []:
        yield from lshw_nodes(child)


def parse_lshw_components():
    try:
        proc = run(
            [
                LSHW,
                "-quiet",
                "-json",
                "-class",
                "storage",
                "-class",
                "network",
                "-class",
                "display",
            ],
            timeout=90,
        )
    except Exception:
        return []
    if proc.returncode != 0 or not proc.stdout.strip():
        return []

    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return []

    components = []
    for node in lshw_nodes(data):
        node_class = node.get("class", "")
        if node_class not in {"storage", "network", "display"}:
            continue

        config = node.get("configuration") or {}
        display = " ".join(
            str(part)
            for part in (
                node.get("product", ""),
                node.get("vendor", ""),
                node.get("description", ""),
                config.get("driver", ""),
                config.get("firmware", ""),
            )
            if part
        ).strip()
        if not display or not inventory_relevant_display(display):
            continue

        components.append(
            {
                "component_id": "",
                "display": display,
                "version": config.get("firmware", "") or node.get("version", ""),
                "component_type": "FRMW",
                "pci": ("", "", "", ""),
                "source": "lshw",
            }
        )
    return components


def parse_hwinfo_components():
    try:
        proc = run(
            [HWINFO, "--storage", "--network", "--gfxcard", "--short"], timeout=90
        )
    except Exception:
        return []
    if proc.returncode != 0:
        return []

    components = []
    for raw in proc.stdout.splitlines():
        line = raw.strip()
        line_lower = line.lower()
        if not line or line.endswith(":") or not inventory_relevant_display(line):
            continue
        if (
            " network interface" in line_lower
            or "loopback network interface" in line_lower
        ):
            continue
        components.append(
            {
                "component_id": "",
                "display": line,
                "version": "",
                "component_type": "FRMW",
                "pci": ("", "", "", ""),
                "source": "hwinfo",
            }
        )
    return components


def parse_lspci_record(lines):
    record = {}
    for line in lines:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        record[key.strip()] = value.strip().strip('"')
    return record


def pci_id_from_lspci_value(value):
    match = re.search(r"\[([0-9a-fA-F]{4})\]\s*$", value or "")
    return normalize_pci_id(match.group(1)) if match else ""


def parse_lspci_components():
    try:
        proc = run([LSPCI, "-Dnnmm"], timeout=60)
    except Exception:
        return []
    if proc.returncode != 0:
        return []

    components = []
    current = []
    relevant_classes = (
        "3d controller",
        "display controller",
        "ethernet controller",
        "fibre channel",
        "infiniband controller",
        "network controller",
        "non-volatile memory controller",
        "raid bus controller",
        "sata controller",
        "scsi storage controller",
        "serial attached scsi controller",
        "vga compatible controller",
    )

    def flush():
        if not current:
            return
        record = parse_lspci_record(current)
        class_name = record.get("Class", "")
        if not any(term in class_name.lower() for term in relevant_classes):
            return

        vendor = record.get("Vendor", "")
        device = record.get("Device", "")
        sub_vendor = record.get("SVendor", "")
        sub_device = record.get("SDevice", "")
        display = " ".join(part for part in (class_name, vendor, device) if part)
        if not display:
            return

        components.append(
            {
                "component_id": "",
                "display": display,
                "version": "",
                "component_type": "FRMW",
                "pci": (
                    pci_id_from_lspci_value(vendor),
                    pci_id_from_lspci_value(device),
                    pci_id_from_lspci_value(sub_vendor),
                    pci_id_from_lspci_value(sub_device),
                ),
                "source": "lspci",
            }
        )

    for raw in proc.stdout.splitlines():
        if raw.strip():
            current.append(raw)
            continue
        flush()
        current = []

    flush()
    return components


def parse_inventory():
    paths = [
        Path("/var/cache/dell/dell_dup/suu/inv.xml"),
        Path("/var/cache/dell/dell_dup/dsu/inv.xml"),
        Path("/var/lib/dell/dsu/inventory.xml"),
    ]
    inventory = {"system_id": "", "components": []}
    component_index = {}

    for path in paths:
        if not path.exists() or path.stat().st_size == 0:
            continue
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError:
            continue

        for elem in root.iter():
            if (
                not inventory["system_id"]
                and elem.tag.rsplit("}", 1)[-1] == "System"
                and elem.get("systemID")
            ):
                inventory["system_id"] = elem.get("systemID", "").upper()
                break

        for device in root.iter():
            if device.tag.rsplit("}", 1)[-1] != "Device":
                continue
            app = None
            for child in device:
                if child.tag.rsplit("}", 1)[-1] == "Application":
                    app = child
                    break
            component = {
                "component_id": device.get("componentID", ""),
                "display": device.get("display", ""),
                "version": app.get("version", "") if app is not None else "",
                "component_type": (
                    app.get("componentType", "") if app is not None else ""
                ),
                "pci": pci_tuple(device.attrib),
                "source": str(path),
            }
            merge_inventory_component(inventory, component_index, component)

    for component in (
        parse_ipmitool_fru_components()
        + parse_lshw_components()
        + parse_hwinfo_components()
        + parse_lspci_components()
    ):
        merge_inventory_component(inventory, component_index, component)

    return inventory


def model_tokens(dmidecode_data):
    raw_values = [
        dmidecode_data.get("product", ""),
        dmidecode_data.get("sku", ""),
        os.environ.get("DELL_SUU_SUPPORT_MODEL", ""),
    ]
    tokens = set()
    for raw in raw_values:
        for value in model_tokens_from_text(raw):
            tokens.add(value.upper())
        model_match = re.search(r"ModelName=([^;]+)", raw)
        if model_match:
            tokens.update(model_tokens({"product": model_match.group(1), "sku": ""}))
    return sorted(tokens, key=len, reverse=True)


def model_tokens_from_text(value):
    return [match.upper() for match in POWEREDGE_MODEL_RE.findall(value or "")]


def poweredge_generation_from_token(token):
    token = (token or "").upper()
    match = re.match(r"^[A-Z]+(\d+)", token)
    if not match:
        return None

    digits = match.group(1)
    if token.startswith("C") and len(digits) >= 2:
        first_two = int(digits[:2])
        if 62 <= first_two <= 63:
            return 12 if first_two == 62 else 13
        if first_two >= 64:
            return first_two - 50

    if len(digits) < 2:
        return None

    generation_digit = int(digits[1])
    return generation_digit + 10


def poweredge_generations(tokens):
    generations = []
    for token in tokens:
        generation = poweredge_generation_from_token(token)
        if generation and generation not in generations:
            generations.append(generation)
    return generations


def component_terms(inventory):
    ignored = {
        "adapter",
        "access",
        "application",
        "a00",
        "a37",
        "autonegotiation",
        "avocent",
        "bios",
        "bit",
        "blade",
        "broadcom",
        "bus",
        "cap",
        "cntlr",
        "collector",
        "controller",
        "cruzer",
        "cruzerblade",
        "dell",
        "diagnostics",
        "device",
        "disk",
        "drive",
        "driver",
        "drivers",
        "dual",
        "emulated",
        "eno1",
        "eno2",
        "eno3",
        "eno4",
        "ethernet",
        "expander",
        "ffv16",
        "fibre",
        "firmware",
        "floppy",
        "function",
        "gigabit",
        "host",
        "gigabit",
        "inc",
        "interface",
        "internal",
        "intel",
        "integrated",
        "lifecycle",
        "list",
        "loopback",
        "mass",
        "mini",
        "module",
        "msi",
        "msix",
        "network",
        "pack",
        "pciexpress",
        "perc",
        "physical",
        "power",
        "poweredge",
        "raid",
        "remote",
        "rev",
        "rom",
        "sandisk",
        "sas",
        "scsi",
        "server",
        "service",
        "storage",
        "supply",
        "system",
        "uefi",
        "usb",
        "version",
        "vpd",
    }
    allowed_identifiers = {
        "backplane",
        "bnx2x",
        "connectx",
        "cpld",
        "geforce",
        "idrac",
        "idsdm",
        "ixgbe",
        "megaraid",
        "quadro",
        "rtx",
        "tesla",
    }
    allowed_vendor_terms = {
        "amd",
        "emulex",
        "marvell",
        "mellanox",
        "nvidia",
        "qlogic",
    }
    terms = set()
    inventory_text = normalise_text(
        " ".join(c.get("display", "") for c in inventory["components"])
    )
    for component in inventory["components"]:
        text = component.get("display", "")
        component_text = normalise_text(text)
        component_allows_vendor = any(
            term in component_text
            for term in (
                "3d controller",
                "display controller",
                "ethernet",
                "fibre channel",
                "graphics",
                "gpu",
                "infiniband",
                "network controller",
                "non volatile",
                "nvme",
                "raid",
                "sata",
                "scsi",
                "storage",
                "vga",
            )
        )
        for word in re.findall(r"[A-Za-z][A-Za-z0-9]{2,}", text):
            lower = word.lower()
            if lower in allowed_vendor_terms and component_allows_vendor:
                terms.add(lower)
                continue
            if lower in ignored:
                continue
            is_model_like = bool(re.search(r"[a-z].*\d|\d.*[a-z]", lower))
            is_interface_name = bool(
                re.match(r"^(eno|enp|tap|vlan|vmbr|lxcbr|lo)\d*", lower)
            )
            is_hex_noise = bool(re.match(r"^x?[0-9a-f]{6,}$", lower))
            if lower in allowed_identifiers or (
                is_model_like and not is_interface_name and not is_hex_noise
            ):
                terms.add(lower)
    for preferred in ("idrac", "cpld", "idsdm"):
        if re.search(rf"\b{re.escape(preferred)}\b", inventory_text):
            terms.add(preferred)
    if "integrated dell remote access controller" in inventory_text:
        terms.add("idrac")
    if "power supply" in inventory_text:
        terms.add("power supply")
    return terms


def inventory_major_versions(inventory):
    versions = {}
    for component in inventory["components"]:
        text = normalise_text(component.get("display", ""))
        major = version_tuple(component.get("version", ""))[:1]
        if not major:
            continue

        term_aliases = {
            "idrac": ("idrac", "integrated dell remote access controller"),
        }
        for term, aliases in term_aliases.items():
            if any(re.search(rf"\b{re.escape(alias)}\b", text) for alias in aliases):
                versions.setdefault(term, set()).add(major)
    return versions


def list_releases(repo_base):
    html = fetch_bytes(repo_base).decode("latin1", errors="replace")
    seen = set()
    releases = []
    for release in re.findall(r'href=["\'](DSU_\d{2}\.\d{2}\.\d{2})/["\']', html):
        if release not in seen:
            releases.append(release)
            seen.add(release)

    def release_key(release):
        match = re.search(r"DSU_(\d{2})\.(\d{2})\.(\d{2})", release)
        if not match:
            return (0, 0, 0)
        year, month, day = (int(part) for part in match.groups())
        return (2000 + year, month, day)

    return sorted(releases, key=release_key, reverse=True)


def metadata_for_release(repo_base, cache_dir, release):
    metadata_dir = cache_dir / "metadata"
    metadata_dir.mkdir(parents=True, exist_ok=True)
    path = metadata_dir / f"{release}-primary.xml.gz"
    if (
        not path.exists()
        or path.stat().st_size == 0
        or env_flag("DELL_SUU_FORCE_REFRESH")
    ):
        url = (
            f"{repo_base.rstrip('/')}/{release}/os_independent/repodata/primary.xml.gz"
        )
        print(f"dell-suu: fetching Dell yum metadata {release}", file=sys.stderr)
        download_file(url, path)
    return gzip.decompress(path.read_bytes())


def platform_csv_url(generation):
    base = os.environ.get(
        "DELL_SUU_SUPPORT_PLATFORM_CSV_BASE", DEFAULT_PLATFORM_CSV_BASE
    ).rstrip("/")
    return f"{base}/latest_poweredge-{generation}g.csv"


def platform_csv_urls(tokens):
    configured = os.environ.get("DELL_SUU_SUPPORT_PLATFORM_CSV_URLS")
    if configured:
        return [url.strip() for url in configured.split(",") if url.strip()]

    generation_scan = []
    generation_scan.extend(poweredge_generations(tokens))
    generation_scan.extend(DEFAULT_PLATFORM_GENERATION_SCAN)

    urls = []
    seen = set()
    for generation in generation_scan:
        if generation in seen:
            continue
        seen.add(generation)
        urls.append(platform_csv_url(generation))
    return urls


def cache_path_for_url(cache_dir, url):
    digest = hashlib.sha256(url.encode()).hexdigest()[:16]
    name = re.sub(r"[^A-Za-z0-9_.-]+", "_", Path(url).name or "platform.csv")
    return cache_dir / "platform-csv" / f"{digest}-{name}"


def cached_fetch_text(cache_dir, url, max_age):
    path = cache_path_for_url(cache_dir, url)
    path.parent.mkdir(parents=True, exist_ok=True)
    if (
        path.exists()
        and path.stat().st_size > 0
        and not env_flag("DELL_SUU_FORCE_REFRESH")
        and (max_age <= 0 or time.time() - path.stat().st_mtime <= max_age)
    ):
        return path.read_text(errors="replace")

    data = fetch_bytes(url, timeout=60)
    path.write_bytes(data)
    return data.decode("utf-8", errors="replace")


def normalise_platform_filename(value):
    name = Path(value or "").name.strip()
    lowered = name.lower()
    for suffix in (".sign", ".rpm"):
        if lowered.endswith(suffix):
            name = name[: -len(suffix)]
            lowered = name.lower()
    return name


def platform_filename_candidates(value):
    name = normalise_platform_filename(value)
    if not name:
        return set()

    candidates = {name}
    if not name.lower().endswith((".bin", ".exe", ".efi")):
        candidates.update({f"{name}.BIN", f"{name}.EXE", f"{name}.efi"})
    return {normalise_platform_filename(candidate) for candidate in candidates}


def load_platform_filter(cache_dir, tokens):
    token_set = {token.upper() for token in tokens if token}
    result = {
        "enabled": False,
        "filenames": set(),
        "models": set(),
        "records": [],
        "source": "",
    }
    if not token_set or env_flag("DELL_SUU_SUPPORT_IGNORE_PLATFORM_CSV"):
        return result

    max_age = env_int("DELL_SUU_SUPPORT_PLATFORM_CSV_MAX_AGE_SECONDS", 21600)
    for url in platform_csv_urls(token_set):
        try:
            text = cached_fetch_text(cache_dir, url, max_age)
        except Exception as exc:
            print(
                f"dell-suu: warning: failed to fetch Dell platform CSV {url}: {exc}",
                file=sys.stderr,
            )
            continue

        filenames = set()
        models = set()
        records_by_name = {}
        sign_urls_by_name = {}
        for row in csv.reader(text.splitlines()):
            if len(row) < 13:
                continue
            row_tokens = {token.upper() for token in model_tokens_from_text(row[0])}
            if not (row_tokens & token_set):
                continue
            filename = normalise_platform_filename(row[12])
            if not filename:
                continue
            filenames.add(filename)
            models.update(row_tokens & token_set)

            if row[12].strip().lower().endswith(".sign") and len(row) > 13:
                sign_urls_by_name[filename] = row[13].strip()
                continue

            record = platform_csv_record_from_row(row, url)
            if record:
                records_by_name.setdefault(record["name"], record)

        if filenames:
            for record in records_by_name.values():
                sign_url = sign_urls_by_name.get(record["name"])
                if sign_url:
                    record["sign_url"] = sign_url
            result.update(
                {
                    "enabled": True,
                    "filenames": filenames,
                    "models": models,
                    "records": list(records_by_name.values()),
                    "source": url,
                }
            )
            return result

    return result


def platform_filter_allows_name(platform_filter, value):
    if not platform_filter.get("enabled"):
        return True
    filenames = platform_filter.get("filenames") or set()
    return any(
        candidate in filenames for candidate in platform_filename_candidates(value)
    )


def platform_filter_allows_record(platform_filter, record):
    if not platform_filter.get("enabled"):
        return True
    values = {
        record.get("name", ""),
        record.get("location", ""),
        Path(record.get("location", "")).name,
    }
    return any(platform_filter_allows_name(platform_filter, value) for value in values)


def platform_source_release(source):
    match = re.search(r"latest_poweredge-([0-9]+g)", source or "", flags=re.I)
    return f"poweredgec-{match.group(1).lower()}" if match else "poweredgec"


def platform_csv_record_from_row(row, source):
    if len(row) < 14:
        return None

    package_format = row[5].strip().lower()
    filename = Path(row[12]).name.strip()
    filename_lower = filename.lower()
    url = row[13].strip()
    if (
        package_format != "linux dup"
        or not filename_lower.endswith(".bin")
        or filename_lower.endswith(".bin.sign")
        or not url
    ):
        return None

    record = {
        "name": filename,
        "summary": row[8].strip() if len(row) > 8 else filename,
        "description": " ".join(
            part.strip() for part in row[14:16] if part and part.strip()
        ),
        "location": url,
        "url": url,
        "checksum": "",
        "checksum_type": "",
        "version": row[10].strip() if len(row) > 10 else "",
        "criticality": row[9].strip() if len(row) > 9 and row[9].strip() else "",
        "category": row[3].strip() if len(row) > 3 else "",
        "release_date": row[7].strip() if len(row) > 7 else "",
        "release": platform_source_release(source),
        "source": "platform-csv",
        "platform_source": source,
    }
    if not record_is_update_payload(record):
        return None
    return record


def suu_iso_record_from_row(row, source, tokens):
    if len(row) < 14:
        return None

    filename = Path(row[12]).name.strip()
    filename_lower = filename.lower()
    url = row[13].strip()
    title = row[8].strip() if len(row) > 8 else ""
    title_lower = title.lower()
    details = " ".join(part.strip() for part in row[14:16] if part and part.strip())
    details_lower = details.lower()

    if not url or not filename_lower.endswith(".iso"):
        return None
    if "windows" in title_lower or "win64" in filename_lower:
        return None
    if not (
        "server update utility" in title_lower
        or filename_lower.startswith(("suu-lin64", "suu_"))
    ):
        return None
    if not (
        "lin64" in filename_lower
        or "x64-lin" in filename_lower
        or "linux 64" in title_lower
        or "64 bit linux" in title_lower
        or "64 bit linux" in details_lower
    ):
        return None

    token_set = {token.upper() for token in tokens if token}
    row_tokens = set(model_tokens_from_text(row[0] if row else ""))
    model_match = bool(token_set and row_tokens and row_tokens & token_set)

    return {
        "name": filename,
        "url": url,
        "date": row[7].strip() if len(row) > 7 else "",
        "version": row[10].strip() if len(row) > 10 else "",
        "revision": row[11].strip() if len(row) > 11 else "",
        "summary": title,
        "source": source,
        "model": row[0].strip() if row else "",
        "modelMatch": model_match,
    }


def suu_iso_sort_key(record):
    return (
        1 if record.get("modelMatch") else 0,
        record.get("date") or "",
        version_tuple(record.get("version") or ""),
        natural_key(record.get("name") or ""),
    )


def resolve_suu_iso(args):
    dmidecode_data = parse_dmidecode()
    tokens = set(model_tokens(dmidecode_data))
    tokens.update(model_tokens({"product": args.model or "", "sku": ""}))

    cache_dir = Path(args.cache_root) / "suu" / "support-yum"
    max_age = env_int("DELL_SUU_SUPPORT_PLATFORM_CSV_MAX_AGE_SECONDS", 21600)
    records = []

    for url in platform_csv_urls(tokens):
        try:
            text = cached_fetch_text(cache_dir, url, max_age)
        except Exception as exc:
            print(
                f"dell-suu: warning: failed to fetch Dell platform CSV {url}: {exc}",
                file=sys.stderr,
            )
            continue

        for row in csv.reader(text.splitlines()):
            record = suu_iso_record_from_row(row, url, tokens)
            if record:
                records.append(record)

        if records and any(record.get("modelMatch") for record in records):
            break

    if not records:
        print(
            "dell-suu: no Linux 64-bit SUU ISO found in Dell platform CSVs",
            file=sys.stderr,
        )
        return 66

    selected = sorted(records, key=suu_iso_sort_key, reverse=True)[0]
    print(json.dumps(selected, separators=(",", ":")))
    return 0


def package_records(metadata):
    root = ET.fromstring(metadata)
    for package in root.findall("m:package", XML_NS):

        def text(name):
            elem = package.find(f"m:{name}", XML_NS)
            return elem.text if elem is not None and elem.text else ""

        location = package.find("m:location", XML_NS)
        checksum = package.find("m:checksum", XML_NS)
        version = package.find("m:version", XML_NS)
        yield {
            "name": text("name"),
            "summary": text("summary"),
            "description": text("description"),
            "location": location.get("href", "") if location is not None else "",
            "checksum": (
                checksum.text.strip() if checksum is not None and checksum.text else ""
            ),
            "checksum_type": checksum.get("type", "") if checksum is not None else "",
            "version": version.get("ver", "") if version is not None else "",
        }


def record_haystack(record):
    return normalise_text(
        " ".join([record["name"], record["summary"], record["description"]])
    )


def record_is_update_payload(record):
    haystack = record_haystack(record)
    skip_phrases = (
        "diagnostics application",
        "drivers for os deployment",
        "operating system collector",
        "os collector",
        "systems management application",
    )
    if any(phrase in haystack for phrase in skip_phrases):
        return False

    update_terms = (
        "backplane",
        "bios",
        "bmc",
        "cpld",
        "drive firmware",
        "ethernet",
        "express flash",
        "firmware",
        "idrac",
        "idsdm",
        "lifecycle",
        "network",
        "nvme",
        "perc",
        "power supply",
        "sas non raid",
        "sas raid",
        "serial ata",
        "ssd",
    )
    return any(term in haystack for term in update_terms)


def record_is_platform_payload(record):
    haystack = record_haystack(record)
    platform_terms = (
        "backplane",
        "bios",
        "bmc",
        "cpld",
        "idrac",
        "idsdm",
        "lifecycle",
        "power supply",
    )
    return any(term in haystack for term in platform_terms)


def candidate_priority(record):
    haystack = record_haystack(record)
    priorities = (
        (0, ("idrac", "lifecycle")),
        (1, ("bios",)),
        (2, ("cpld", "idsdm")),
        (3, ("perc", "sas raid", "sas non raid")),
        (4, ("network", "ethernet", "intel", "broadcom")),
        (5, ("power supply", "backplane", "drive firmware", "nvme", "ssd")),
        (6, ("firmware",)),
    )
    for priority, terms in priorities:
        if any(term in haystack for term in terms):
            return priority
    return 9


def package_match_kind(record, tokens, terms, term_major_versions, download_all):
    name = record["name"]
    location = record["location"]
    if "_LN" not in name and "_LN" not in location:
        return ""
    if download_all:
        return "all"
    if not record_is_update_payload(record):
        return ""

    haystack = record_haystack(record)
    if record_is_platform_payload(record):
        for token in tokens:
            if re.search(rf"\b{re.escape(token.lower())}\b", haystack):
                return "model"

    # This widens discovery for device firmware such as RAID and NIC updates
    # without hardcoding a specific server model.
    strong_terms = [term for term in terms if len(term) >= 4]
    record_major = version_tuple(record.get("version", ""))[:1]
    for term in strong_terms:
        if not re.search(rf"\b{re.escape(term)}\b", haystack):
            continue

        allowed_majors = term_major_versions.get(term)
        if allowed_majors:
            if not record_major or record_major not in allowed_majors:
                continue

        return "component"
    return ""


def record_release_name(record):
    return Path(record.get("location") or record.get("name") or "").name


def record_version_key(record):
    return record.get("version") or record.get("name") or record.get("location") or ""


def term_is_specific_chain_key(term):
    if not term:
        return False
    term = term.lower()
    if term in {"idrac", "cpld", "idsdm", "backplane"}:
        return True
    if re.search(r"[a-z].*\d|\d.*[a-z]", term):
        return True
    return False


def record_chain_keys(record, tokens, terms, term_major_versions, download_all):
    if download_all:
        return set()

    keys = set()
    haystack = record_haystack(record)
    priority = candidate_priority(record)

    if record_is_platform_payload(record):
        for token in tokens:
            token_lower = token.lower()
            if re.search(rf"\b{re.escape(token_lower)}\b", haystack):
                keys.add(("model", priority, token_lower))

    record_major = version_tuple(record.get("version", ""))[:1]
    for term in terms:
        term = term.lower()
        if not term_is_specific_chain_key(term):
            continue
        if not re.search(rf"\b{re.escape(term)}\b", haystack):
            continue

        allowed_majors = term_major_versions.get(term)
        if allowed_majors and (not record_major or record_major not in allowed_majors):
            continue

        keys.add(("component", priority, term))
    return keys


def record_family_key(record):
    priority = candidate_priority(record)
    if priority <= 2 and record_is_platform_payload(record):
        return ("platform", priority)
    return None


def package_target_keys(package_info, matched_components, record):
    keys = set()
    component_type = package_info.get("component_type") or ""
    component_id = package_info.get("component_id") or ""
    if component_id:
        keys.add(("component-id", component_type, str(component_id)))

    for component_id in package_info.get("supported_component_ids") or set():
        if component_id:
            keys.add(("supported-component-id", component_type, str(component_id)))

    for pci in package_info.get("supported_pci_ids") or set():
        if pci_tuple_has_data(pci):
            keys.add(("pci", tuple(pci)))

    for component in matched_components or []:
        component_id = component.get("component_id") or ""
        if component_id:
            keys.add(("inventory-component-id", str(component_id)))
        component_pci = component.get("pci") or ("", "", "", "")
        if pci_tuple_has_data(component_pci):
            keys.add(("inventory-pci", tuple(component_pci)))

    if not keys and package_info.get("supported_system_ids"):
        keys.add(
            (
                "system",
                component_type or candidate_priority(record),
                tuple(sorted(package_info["supported_system_ids"])),
            )
        )

    if not keys:
        key_name = package_info.get("name") or package_info.get("device_display") or ""
        if key_name:
            keys.add(("name", component_type, normalise_text(key_name)))

    return keys


def candidate_sort_key(candidate, release_rank):
    release, record = candidate
    return (
        candidate_priority(record),
        version_desc_key(record_version_key(record)),
        release_rank.get(release, 999999),
        natural_key(record_release_name(record)),
    )


def compliance_html_state(component):
    message = component.get("complianceMessage") or ""
    if message:
        return message
    current = component.get("version") or component.get("currentVersion") or ""
    baseline = component.get("baseLineVersion") or ""
    if newer_version(baseline, current):
        return "Upgrade"
    if newer_version(current, baseline):
        return "Downgrade"
    return "Equal"


def compliance_message_for_versions(package_version, installed_version, applicable):
    if applicable:
        return "Upgrade"
    if (
        package_version
        and installed_version
        and version_tuple(package_version)
        and version_tuple(installed_version)
    ):
        if version_tuple(package_version) == version_tuple(installed_version):
            return "Equal"
        if version_tuple(package_version) < version_tuple(installed_version):
            return "Downgrade"
    return "Matched"


def write_compliance_html(path, report):
    root = report.get("SystemUpdateCompliance", [{}])[0]
    system = root.get("System", {})
    baseline = root.get("BaseLineInformation", {})
    components = root.get("UpdateableComponent", [])
    dmidecode_data = parse_dmidecode()
    host_name = os.uname().nodename if hasattr(os, "uname") else "LocalHost"

    def esc(value):
        return html.escape(str(value or ""), quote=True)

    rows = []
    for component in components:
        rows.append(
            "<tr>"
            f'<td class="data-area-canvas">{esc(component.get("packageFilePath"))}</td>'
            f'<td class="data-area-canvas">{esc(component.get("name"))}</td>'
            f'<td class="data-area-canvas">{esc(component.get("criticality"))}</td>'
            f'<td class="data-area-canvas">{esc(component.get("componentType"))}</td>'
            f'<td class="data-area-canvas">{esc(component.get("version") or component.get("currentVersion"))}</td>'
            f'<td class="data-area-canvas">{esc(component.get("baseLineVersion"))}</td>'
            '<td class="data-area-canvas">No Dependency</td>'
            '<td class="data-area-canvas">No Dependency</td>'
            f'<td class="data-area-canvas">{esc(compliance_html_state(component))}</td>'
            "</tr>"
        )

    content = """<head><META http-equiv="Content-Type" content="text/html; charset=UTF-8">
<style>
body {{background-color: #ADBEE7}}
TD.data-area-header {{font-weight:bold}}
TD.data-area-canvas {{background-color:#ADBEE7}}
TH.data-area-header {{font-weight:bold}}
TABLE.data-area {{background-color:#ADBEE7}}
</style>
<center>
<h1>Dell Server Update Utility : Compliance Report </h1>
</center>
</head><body>
<br>
<table width="100%" border="0" cellpadding="2" cellspacing="2" class="data-area">
<tr><td nowrap align="left" class="data-area-header">Model : {model}</td></tr>
<tr><td nowrap align="left" class="data-area-header">Host Name : {host}</td></tr>
<tr><td nowrap align="left" class="data-area-header">SUU Version : {version}</td></tr>
</table>
<br>
<table width="100%" border="1" cellpadding="0" cellspacing="1" class="data-area">
<th class="data-area-header">Package Name</th><th class="data-area-header">Component</th><th class="data-area-header">Criticality</th><th class="data-area-header">Type</th><th class="data-area-header">Current Version</th><th class="data-area-header">Latest Version</th><th class="data-area-header">Pre-Requisites</th><th class="data-area-header">Co-Requisites</th><th class="data-area-header">State</th>
{rows}
</table>
<br>
<br>
</body>
""".format(
        model=esc(
            system.get("model")
            or dmidecode_data.get("product")
            or os.environ.get("DELL_SUU_SUPPORT_MODEL", "")
        ),
        host=esc(system.get("hostName") or host_name),
        version=esc(baseline.get("version") or ""),
        rows="\n".join(rows),
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def write_suu_status(path):
    status = {
        "SystemUpdateStatus": [
            {
                "System": {
                    "id": "0600",
                    "idType": "BIOS",
                    "hostAddress": "LocalHost",
                },
                "InvokerInfo": {
                    "name": "DSU",
                    "version": "1.9.3.0",
                    "command": "--compliance , --output",
                    "exitStatus": 0,
                    "statusMessage": "Command has run successfully",
                },
            }
        ]
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(status, separators=(",", ":")) + "\n")


def native_compliance_base_is_useful(report):
    root = (report.get("SystemUpdateCompliance") or [{}])[0]
    baseline = root.get("BaseLineInformation") or {}
    return bool(
        baseline.get("identifier")
        or baseline.get("catalogName")
        or baseline.get("version")
        or root.get("System", {}).get("id")
    )


def strip_support_components(report):
    report = copy.deepcopy(report)
    root = report.setdefault("SystemUpdateCompliance", [{}])[0]
    components = root.setdefault("UpdateableComponent", [])
    root["UpdateableComponent"] = [
        component
        for component in components
        if not str(component.get("packageFilePath", "")).startswith("support-yum/")
    ]
    root.setdefault("BaseLineInformation", {})
    root["BaseLineInformation"]["complianceStatus"] = not bool(
        root["UpdateableComponent"]
    )
    return report


def save_native_compliance_base(report):
    if not native_compliance_base_is_useful(report):
        return
    native = strip_support_components(report)
    NATIVE_COMPLIANCE_CACHE.parent.mkdir(parents=True, exist_ok=True)
    NATIVE_COMPLIANCE_CACHE.write_text(json.dumps(native, separators=(",", ":")) + "\n")


def compliance_component_for_gui(component):
    component = dict(component)
    for field in (
        "packageID",
        "packageFilePath",
        "name",
        "componentType",
        "componentTypeDisplay",
        "categoryType",
        "criticality",
        "complianceMessage",
        "version",
        "baseLineVersion",
    ):
        component[field] = one_line_text(component.get(field))

    if not component["name"]:
        component["name"] = (
            component["packageID"] or Path(component["packageFilePath"]).name
        )
    if not component["categoryType"]:
        component["categoryType"] = component["name"]
    if not component["componentTypeDisplay"]:
        component["componentTypeDisplay"] = component_type_display(
            component.get("componentType")
        )
    if not component["criticality"]:
        component["criticality"] = "Recommended"
    if not component["complianceMessage"]:
        component["complianceMessage"] = "Upgrade"

    try:
        component["componentID"] = int(component.get("componentID") or 0)
    except (TypeError, ValueError):
        component["componentID"] = 0

    component["index"] = int(component.get("index") or 0)
    component["complianceStatus"] = bool(component.get("complianceStatus"))
    component["rebootRequired"] = bool(component.get("rebootRequired"))
    return component


def download_rpm(repo_base, cache_dir, release, record):
    rpm = cache_dir / "rpms" / release / Path(record["location"]).name
    with file_lock(rpm):
        if rpm.exists() and rpm.stat().st_size > 0:
            if record["checksum_type"] != "sha512" or cached_sha512_matches(
                rpm, record["checksum"]
            ):
                return rpm
            rpm.unlink()
            sha512_marker_path(rpm).unlink(missing_ok=True)

        url = f"{repo_base.rstrip('/')}/{release}/os_independent/{record['location']}"
        print(
            f"dell-suu: downloading Dell yum package {release}/{Path(record['location']).name}",
            file=sys.stderr,
        )
        download_file(url, rpm, record["checksum_type"], record["checksum"])
        return rpm


def download_platform_bin(cache_dir, release, record):
    filename = Path(record["name"] or record["location"]).name
    bin_path = cache_dir / "platform-bins" / release / filename
    url = record.get("url") or record.get("location")
    if not url:
        raise RuntimeError(f"platform CSV record has no download URL: {filename}")

    with file_lock(bin_path):
        if not bin_path.exists() or bin_path.stat().st_size == 0:
            print(
                f"dell-suu: downloading Dell platform package {filename}",
                file=sys.stderr,
            )
            download_file(url, bin_path)
        else:
            print(
                f"dell-suu: using cached Dell platform package {filename}",
                file=sys.stderr,
            )
        bin_path.chmod(0o755)

        sign_url = record.get("sign_url")
        sign_path = Path(str(bin_path) + ".sign")
        if sign_url and (not sign_path.exists() or sign_path.stat().st_size == 0):
            try:
                download_file(sign_url, sign_path)
            except Exception as exc:
                print(
                    f"dell-suu: warning: failed to download signature for {filename}: {exc}",
                    file=sys.stderr,
                )

    return bin_path


def extract_rpm(cache_dir, release, rpm):
    extract_dir = cache_dir / "extracted" / release / rpm.stem
    marker = extract_dir / ".complete"
    if marker.exists():
        return extract_dir

    if extract_dir.exists():
        shutil.rmtree(extract_dir)
    extract_dir.mkdir(parents=True, exist_ok=True)
    run([BSDTAR, "-xf", str(rpm), "-C", str(extract_dir)], timeout=180, check=True)
    marker.write_text("ok\n")
    return extract_dir


def find_bins(extract_dir):
    return sorted(
        (path for path in extract_dir.rglob("*.BIN") if path.is_file()),
        key=lambda path: natural_key(path.name),
    )


def package_xml_cache_path(cache_dir, bin_path):
    digest = hashlib.sha256(str(bin_path).encode()).hexdigest()[:24]
    safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", bin_path.name)
    return cache_dir / "manifests" / f"{safe_name}-{digest}" / "package.xml"


def extract_package_xml(cache_dir, source_dir, bin_path):
    xml_path = package_xml_cache_path(cache_dir, bin_path)
    if xml_path.exists() and xml_path.stat().st_size > 0:
        return xml_path

    final_dir = xml_path.parent
    tmp_dir = final_dir.with_name(
        f"{final_dir.name}.tmp.{os.getpid()}.{time.monotonic_ns()}"
    )
    if tmp_dir.exists():
        shutil.rmtree(tmp_dir, ignore_errors=True)
    tmp_dir.parent.mkdir(parents=True, exist_ok=True)

    try:
        proc = run_dup(
            [
                FHS,
                source_dir,
                "--launcher",
                str(bin_path),
                "--",
                "--extract",
                str(tmp_dir),
            ],
            timeout=240,
            locked=False,
        )
        if proc.returncode != 0:
            raise RuntimeError(proc.stdout)

        extracted_xml = tmp_dir / "package.xml"
        if not extracted_xml.exists() or extracted_xml.stat().st_size == 0:
            raise RuntimeError(f"{bin_path.name} did not extract package.xml")

        final_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(extracted_xml, xml_path)
        extracted_sign = tmp_dir / "package.xml.sign"
        if extracted_sign.exists():
            shutil.copy2(extracted_sign, final_dir / "package.xml.sign")
        (final_dir / "source").write_text(str(bin_path) + "\n")
        return xml_path
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def check_dup(source_dir, bin_path, locked=True):
    proc = run_dup(
        [FHS, source_dir, "--launcher", str(bin_path), "--", "-q", "-c"],
        timeout=360,
        locked=locked,
    )
    output = proc.stdout
    lower = output.lower()
    package_version = ""
    installed_version = ""
    display = ""

    for line in output.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        lower_stripped = stripped.lower()
        if lower_stripped.startswith("package version:"):
            package_version = stripped.split(":", 1)[1].strip()
        elif lower_stripped.startswith("new version:") and not package_version:
            package_version = stripped.split(":", 1)[1].strip()
        elif lower_stripped.startswith("installed version:"):
            installed_version = stripped.split(":", 1)[1].strip()
        elif lower_stripped.startswith("previous version:") and not installed_version:
            installed_version = stripped.split(":", 1)[1].strip()
        elif lower_stripped.startswith("software application name:"):
            display = stripped.split(":", 1)[1].strip()
        elif (
            not display
            and not stripped.startswith("DELL ")
            and "warning:" not in lower_stripped
            and lower_stripped
            not in {
                ".",
                "collecting inventory...",
                "running validation...",
            }
            and not lower_stripped.startswith("collecting inventory")
            and not lower_stripped.startswith("running validation")
        ):
            display = stripped

    applicable = "newer than the currently installed version" in lower
    if (
        package_version
        and installed_version
        and not newer_version(package_version, installed_version)
    ):
        applicable = False

    return applicable, {
        "output": output,
        "display": display,
        "package_version": package_version,
        "installed_version": installed_version,
    }


def parse_package_xml_path(path):
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return {}

    def local_name(elem):
        return elem.tag.rsplit("}", 1)[-1]

    def display_text(elem):
        for child in elem:
            if local_name(child) == "Display":
                return "".join(child.itertext()).strip()
        return elem.get("Display", "") or ""

    info = {
        "package_id": root.get("packageID", ""),
        "release_id": root.get("releaseID", ""),
        "version": root.get("vendorVersion", "") or root.get("dellVersion", ""),
        "reboot_required": root.get("rebootRequired", "").lower() == "true",
        "component_type": "",
        "component_id": "",
        "criticality": "Recommended",
        "name": "",
        "package_xml_path": str(path),
        "supported_component_ids": set(),
        "supported_pci_ids": set(),
        "supported_system_ids": set(),
    }

    for elem in root.iter():
        name = local_name(elem)
        for attr, value in elem.attrib.items():
            attr_lower = attr.lower()
            if attr_lower == "systemid":
                system_id = normalize_system_id(value)
                if system_id:
                    info["supported_system_ids"].add(system_id)
            elif attr_lower == "componentid" and value:
                info["supported_component_ids"].add(value)

        current_pci = pci_tuple(elem.attrib)
        if pci_tuple_has_data(current_pci):
            info["supported_pci_ids"].add(current_pci)

        if name == "Name" and not info["name"]:
            info["name"] = display_text(elem)
        elif name == "ComponentType" and elem.get("value"):
            info["component_type"] = elem.get("value", "")
        elif name == "Device" and elem.get("componentID") and not info["component_id"]:
            info["component_id"] = elem.get("componentID", "")
            device_display = display_text(elem)
            if device_display:
                info["device_display"] = device_display
        elif name == "Criticality":
            criticality = display_text(elem)
            if criticality:
                info["criticality"] = criticality
    return info


def parse_package_xml(bin_path):
    opt_root = Path("/var/cache/dell/suu/opt/dell/updatepackage")
    candidates = sorted(
        opt_root.glob(f"{bin_path.name}-*/package.xml"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        return {}
    return parse_package_xml_path(candidates[0])


def matching_inventory_components(package_info, inventory):
    supported_component_ids = {
        str(component_id)
        for component_id in (package_info.get("supported_component_ids") or set())
        if component_id
    }
    supported_pci_ids = {
        pci
        for pci in (package_info.get("supported_pci_ids") or set())
        if pci_tuple_has_data(pci)
    }

    matches = []
    for component in inventory["components"]:
        component_id = str(component.get("component_id", ""))
        component_pci = component.get("pci") or ("", "", "", "")
        component_matches = (
            supported_component_ids and component_id in supported_component_ids
        )
        pci_matches = supported_pci_ids and any(
            pci_tuple_matches(package_pci, component_pci)
            for package_pci in supported_pci_ids
        )
        if component_matches or pci_matches:
            matches.append(component)
    return matches


def package_supports_inventory(package_info, inventory):
    inventory_system_id = normalize_system_id(inventory.get("system_id", ""))
    supported_system_ids = package_info.get("supported_system_ids") or set()
    if (
        supported_system_ids
        and inventory_system_id
        and inventory_system_id not in supported_system_ids
    ):
        return False

    has_device_constraints = bool(
        package_info.get("supported_component_ids")
        or package_info.get("supported_pci_ids")
    )
    if has_device_constraints and not matching_inventory_components(
        package_info, inventory
    ):
        return False

    return True


def component_display_by_id(inventory, component_id):
    for component in inventory["components"]:
        if component.get("component_id") == str(component_id):
            return component.get("display", "")
    return ""


def component_type_display(component_type):
    return {
        "BIOS": "BIOS",
        "FRMW": "FIRMWARE",
        "APAC": "APPLICATION",
        "APP": "APPLICATION",
        "DRVR": "DRIVER",
    }.get(component_type, component_type or "FIRMWARE")


def support_component_text(component):
    return normalise_text(
        " ".join(
            str(component.get(name, ""))
            for name in (
                "name",
                "categoryType",
                "componentType",
                "componentTypeDisplay",
                "packageFilePath",
            )
        )
    )


def inventory_component_text(component):
    return normalise_text(
        " ".join(
            str(component.get(name, ""))
            for name in ("display", "component_id", "component_type")
        )
    )


def text_component_matches(support_text, inventory_text):
    if not support_text or not inventory_text:
        return False

    alias_groups = (
        ("idrac", "integrated dell remote access controller", "lifecycle controller"),
        ("bios",),
        ("backplane",),
    )
    for aliases in alias_groups:
        support_has_alias = any(alias in support_text for alias in aliases)
        inventory_has_alias = any(alias in inventory_text for alias in aliases)
        if support_has_alias and inventory_has_alias:
            return True

    support_terms = {
        term
        for term in support_text.split()
        if len(term) >= 4
        and term
        not in {
            "dell",
            "firmware",
            "controller",
            "integrated",
            "adapter",
            "update",
            "package",
            "mini",
            "network",
            "ethernet",
            "intel",
            "broadcom",
        }
    }
    inventory_terms = set(inventory_text.split())
    shared_terms = support_terms & inventory_terms
    if len(shared_terms) >= 2:
        return True

    return any(re.search(r"[a-z].*\d|\d.*[a-z]", term) for term in shared_terms)


def support_component_is_current_in_inventory(component, inventory):
    baseline = component.get("baseLineVersion", "")
    if not version_tuple(baseline):
        return False

    component_id = str(component.get("componentID") or "")
    support_text = support_component_text(component)
    for inventory_component in inventory.get("components", []):
        inventory_version = inventory_component.get("version", "")
        if not version_tuple(inventory_version):
            continue

        inventory_component_id = str(inventory_component.get("component_id") or "")
        id_matches = (
            component_id
            and component_id != "0"
            and inventory_component_id
            and component_id == inventory_component_id
        )
        text_matches = text_component_matches(
            support_text, inventory_component_text(inventory_component)
        )
        if not (id_matches or text_matches):
            continue

        if version_tuple(inventory_version) >= version_tuple(baseline):
            return True

    return False


def install_bin(repo_dir, release, bin_path):
    rel_path = Path("support-yum") / release / bin_path.name
    dest = repo_dir / rel_path
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists() or dest.stat().st_size != bin_path.stat().st_size:
        shutil.copy2(bin_path, dest)
        dest.chmod(0o755)

    sign_path = Path(str(bin_path) + ".sign")
    if sign_path.exists():
        sign_dest = Path(str(dest) + ".sign")
        if (
            not sign_dest.exists()
            or sign_dest.stat().st_size != sign_path.stat().st_size
        ):
            shutil.copy2(sign_path, sign_dest)
    return str(rel_path)


def support_report_paths(report_path):
    report = load_json(report_path)
    paths = set()
    for component in report.get("SystemUpdateCompliance", [{}])[0].get(
        "UpdateableComponent", []
    ):
        rel_path = str(component.get("packageFilePath") or "")
        if rel_path.startswith("support-yum/") and rel_path.endswith(".BIN"):
            paths.add(rel_path)
    return paths


def support_report_has_current_versions(report_path):
    report = load_json(report_path)
    for component in report.get("SystemUpdateCompliance", [{}])[0].get(
        "UpdateableComponent", []
    ):
        rel_path = str(component.get("packageFilePath") or "")
        if not rel_path.startswith("support-yum/"):
            continue
        version = one_line_text(component.get("version"))
        if not version or version.lower() == "unknown":
            return False
    return True


def support_report_payloads_exist(repo_dir, report_path):
    for rel_path in support_report_paths(report_path):
        path = repo_dir / rel_path
        if not path.exists() or path.stat().st_size == 0:
            return False
    return True


def support_cache_manifest_valid(repo_dir, report_path, manifest_path):
    if not manifest_path.exists() or manifest_path.stat().st_size == 0:
        return False
    if not report_path.exists() or report_path.stat().st_size == 0:
        return False

    try:
        manifest = json.loads(manifest_path.read_text())
    except json.JSONDecodeError:
        return False

    settings = support_cache_settings()
    if manifest.get("schema") != SUPPORT_REPORT_SCHEMA_VERSION:
        return False
    if manifest.get("repo") != str(repo_dir):
        return False
    if manifest.get("settings") != settings:
        return False
    expected_fingerprint = (
        hardware_fingerprint(parse_dmidecode(), {"system_id": "", "components": []})
        if settings["nativeCatalogOnly"]
        else hardware_fingerprint()
    )
    if manifest.get("hardwareFingerprint") != expected_fingerprint:
        return False
    if not support_report_payloads_exist(repo_dir, report_path):
        return False
    if not settings["includeNonApplicable"]:
        if not support_report_has_current_versions(report_path):
            return False

    report_paths = support_report_paths(report_path)
    if manifest.get("supportPackageCount") != len(report_paths):
        return False
    return True


def catalog_support_paths(catalog_path):
    if not catalog_path.exists() or catalog_path.stat().st_size == 0:
        return set()

    try:
        root = ET.parse(catalog_path).getroot()
    except ET.ParseError:
        return set()

    paths = set()
    for element in root:
        if element.tag.rsplit("}", 1)[-1] != "SoftwareComponent":
            continue
        rel_path = element.get("path", "")
        if rel_path.startswith("support-yum/"):
            paths.add(rel_path)
    return paths


def find_package_xml_for_bin(cache_dir, bin_name):
    candidates = sorted(
        (cache_dir / "manifests").glob(f"{bin_name}-*/package.xml"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return candidates[0] if candidates else None


def catalog_entry_from_package_xml(xml_path, rel_path, bin_path):
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError as exc:
        print(
            f"dell-suu: warning: failed to parse catalog metadata {xml_path}: {exc}",
            file=sys.stderr,
        )
        return None

    if root.tag.rsplit("}", 1)[-1] != "SoftwareComponent":
        return None

    entry = copy.deepcopy(root)
    entry.set("path", rel_path)
    entry.set("size", str(bin_path.stat().st_size))
    if not entry.get("packageType"):
        entry.set("packageType", "LLXP")
    if not entry.get("hash") or entry.get("hashAlgorithm") != "SHA256":
        entry.set("hash", sha256_file(bin_path))
        entry.set("hashAlgorithm", "SHA256")
    return entry


def inject_support_catalog_entries(catalog_path, entries):
    if not entries:
        return 0
    if not catalog_path.exists() or catalog_path.stat().st_size == 0:
        print(
            f"dell-suu: warning: cannot inject support packages; missing {catalog_path}",
            file=sys.stderr,
        )
        return 0

    tree = ET.parse(catalog_path)
    root = tree.getroot()
    existing_paths = set()
    removed = 0

    for element in list(root):
        if element.tag.rsplit("}", 1)[-1] != "SoftwareComponent":
            continue
        rel_path = element.get("path", "")
        if rel_path.startswith("support-yum/"):
            root.remove(element)
            removed += 1
            continue
        existing_paths.add(rel_path)

    added = 0
    for entry in entries:
        rel_path = entry.get("path", "")
        if not rel_path or rel_path in existing_paths:
            continue
        root.append(entry)
        existing_paths.add(rel_path)
        added += 1

    if added or removed:
        tmp = catalog_path.with_name(f"{catalog_path.name}.tmp.{os.getpid()}")
        tree.write(tmp, encoding="utf-16", xml_declaration=True)
        tmp.replace(catalog_path)
        print(
            f"dell-suu: injected {added} Dell support package(s) into {catalog_path.name}"
            + (f" and removed {removed} stale injected package(s)" if removed else ""),
            file=sys.stderr,
        )

    return added


def ensure_support_catalog_from_report(repo_dir, cache_dir, report_path):
    report_paths = support_report_paths(report_path)
    if not report_paths:
        return True

    catalog_path = repo_dir / "Catalog.xml"
    if report_paths <= catalog_support_paths(catalog_path):
        return True

    entries = []
    for rel_path in sorted(report_paths, key=natural_key):
        bin_path = repo_dir / rel_path
        if not bin_path.exists() or bin_path.stat().st_size == 0:
            print(
                f"dell-suu: warning: cached support report references missing package {rel_path}",
                file=sys.stderr,
            )
            continue

        xml_path = find_package_xml_for_bin(cache_dir, bin_path.name)
        if not xml_path:
            print(
                f"dell-suu: warning: no package.xml cache for {bin_path.name}",
                file=sys.stderr,
            )
            continue

        entry = catalog_entry_from_package_xml(xml_path, rel_path, bin_path)
        if entry is not None:
            entries.append(entry)

    if not entries:
        return False

    inject_support_catalog_entries(catalog_path, entries)
    return report_paths <= catalog_support_paths(catalog_path)


def write_support_cache_manifest(
    repo_dir, components, candidates, catalog_entry_count, dmidecode_data, inventory
):
    SUPPORT_MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    SUPPORT_MANIFEST.write_text(
        json.dumps(
            {
                "schema": SUPPORT_REPORT_SCHEMA_VERSION,
                "repo": str(repo_dir),
                "settings": support_cache_settings(),
                "hardwareFingerprint": hardware_fingerprint(dmidecode_data, inventory),
                "supportPackageCount": len(components),
                "candidateCount": len(candidates),
                "catalogEntryCount": catalog_entry_count,
                "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            },
            indent=2,
        )
        + "\n"
    )


def refresh(args):
    max_age = env_int(
        "DELL_SUU_SUPPORT_REFRESH_MAX_AGE_SECONDS",
        env_int("DELL_SUU_REFRESH_MAX_AGE_SECONDS", 21600),
    )
    if (
        max_age > 0
        and not env_flag("DELL_SUU_FORCE_REFRESH")
        and SUPPORT_REPORT.exists()
        and SUPPORT_STAMP.exists()
        and time.time() - SUPPORT_STAMP.stat().st_mtime <= max_age
    ):
        repo_dir = Path(args.repo)
        cache_dir = Path(args.cache_root) / "suu" / "support-yum"
        if support_cache_manifest_valid(
            repo_dir, SUPPORT_REPORT, SUPPORT_MANIFEST
        ) and ensure_support_catalog_from_report(repo_dir, cache_dir, SUPPORT_REPORT):
            print(
                "dell-suu: using cached Dell platform support package report",
                file=sys.stderr,
            )
            return 0
        print(
            "dell-suu: cached Dell support report is stale or incomplete for the GUI; refreshing",
            file=sys.stderr,
        )

    repo_base = (
        os.environ.get("DELL_SUU_SUPPORT_REPO_BASE", DEFAULT_REPO_BASE).rstrip("/")
        + "/"
    )
    cache_dir = Path(args.cache_root) / "suu" / "support-yum"
    repo_dir = Path(args.repo)
    source_dir = args.source

    SUPPORT_STAMP.unlink(missing_ok=True)
    SUPPORT_MANIFEST.unlink(missing_ok=True)

    max_releases = env_int("DELL_SUU_SUPPORT_MAX_RELEASES", 0)
    max_candidates = env_int("DELL_SUU_SUPPORT_MAX_CANDIDATES", 0)
    metadata_workers = max(1, env_int("DELL_SUU_SUPPORT_METADATA_WORKERS", 6))
    download_workers = max(1, env_int("DELL_SUU_SUPPORT_DOWNLOAD_WORKERS", 6))
    check_workers = max(1, env_int("DELL_SUU_SUPPORT_CHECK_WORKERS", 1))
    download_all = env_flag("DELL_SUU_SUPPORT_DOWNLOAD_ALL", False)
    require_metadata_match = env_flag("DELL_SUU_SUPPORT_REQUIRE_METADATA_MATCH", True)
    include_non_applicable = env_flag("DELL_SUU_SUPPORT_INCLUDE_NON_APPLICABLE", False)
    trust_platform_csv = env_flag("DELL_SUU_SUPPORT_TRUST_PLATFORM_CSV", True)
    check_platform_dups = env_flag("DELL_SUU_SUPPORT_CHECK_PLATFORM_DUPS", True)

    dmidecode_data = parse_dmidecode()
    native_catalog_only = env_flag("DELL_SUU_SUPPORT_NATIVE_CATALOG_ONLY", False)
    inventory = (
        {"system_id": "", "components": []}
        if native_catalog_only
        else parse_inventory()
    )
    tokens = model_tokens(dmidecode_data)
    terms = component_terms(inventory)
    term_major_versions = inventory_major_versions(inventory)
    platform_filter = load_platform_filter(cache_dir, tokens)

    print(
        "dell-suu: Dell support discovery "
        f"model={dmidecode_data.get('product') or 'unknown'} "
        f"systemID={inventory.get('system_id') or 'native-suu'} "
        f"inventoryComponents={len(inventory['components']) if not native_catalog_only else 'native-suu'} "
        f"tokens={','.join(tokens) or 'none'}",
        file=sys.stderr,
    )
    if native_catalog_only:
        print(
            "dell-suu: native catalog mode is enabled; host inventory/compliance is left to Dell SUU",
            file=sys.stderr,
        )
    if platform_filter.get("enabled"):
        print(
            "dell-suu: using Dell platform latest CSV "
            f"{platform_filter['source']} for "
            f"{','.join(sorted(platform_filter['models'])) or ','.join(tokens)} "
            f"({len(platform_filter['filenames'])} published files)",
            file=sys.stderr,
        )
    else:
        print(
            "dell-suu: no Dell platform latest CSV match found; falling back to metadata/package checks",
            file=sys.stderr,
        )

    seen_names = set()
    seen_filenames = set()
    model_candidates = []
    component_candidates = []
    platform_candidates = []
    metadata_by_release = {}

    for record in platform_filter.get("records") or []:
        record = dict(record)
        record["match_kind"] = "all"
        record["chain_keys"] = tuple()
        platform_candidates.append((record.get("release") or "poweredgec", record))
        seen_names.add(record["name"])
        seen_filenames.update(platform_filename_candidates(record["name"]))

    if platform_candidates:
        print(
            f"dell-suu: queued {len(platform_candidates)} Dell platform latest Linux DUP candidates",
            file=sys.stderr,
        )

    scan_yum_metadata = env_flag(
        "DELL_SUU_SUPPORT_SCAN_YUM_METADATA", not bool(platform_candidates)
    )
    if scan_yum_metadata:
        releases = list_releases(repo_base)
        selected_releases = releases[:max_releases] if max_releases > 0 else releases
        metadata_workers = min(metadata_workers, max(1, len(selected_releases)))
        print(
            f"dell-suu: fetching/scanning metadata for {len(selected_releases)} releases with {metadata_workers} workers",
            file=sys.stderr,
        )

        with concurrent.futures.ThreadPoolExecutor(
            max_workers=metadata_workers
        ) as executor:
            future_to_release = {
                executor.submit(
                    metadata_for_release, repo_base, cache_dir, release
                ): release
                for release in selected_releases
            }
            for future in concurrent.futures.as_completed(future_to_release):
                release = future_to_release[future]
                try:
                    metadata_by_release[release] = future.result()
                except (
                    urllib.error.URLError,
                    TimeoutError,
                    RuntimeError,
                    ET.ParseError,
                    OSError,
                ) as exc:
                    print(
                        f"dell-suu: warning: failed to read {release} metadata: {exc}",
                        file=sys.stderr,
                    )
    else:
        selected_releases = []
        print(
            "dell-suu: skipping Dell yum metadata scan because platform latest CSV matched this model",
            file=sys.stderr,
        )

    for release in selected_releases:
        metadata = metadata_by_release.get(release)
        if not metadata:
            continue

        for record in package_records(metadata):
            if record["name"] in seen_names:
                continue
            record_filenames = set()
            for value in (record.get("name", ""), record.get("location", "")):
                record_filenames.update(platform_filename_candidates(value))
            if record_filenames & seen_filenames:
                continue
            kind = package_match_kind(
                record, tokens, terms, term_major_versions, download_all
            )
            if not kind:
                continue
            if not platform_filter_allows_record(platform_filter, record):
                continue
            seen_names.add(record["name"])
            record = dict(record)
            record["match_kind"] = kind
            record["chain_keys"] = tuple(
                sorted(
                    record_chain_keys(
                        record, tokens, terms, term_major_versions, download_all
                    )
                )
            )
            seen_filenames.update(record_filenames)
            if kind in {"model", "all"}:
                model_candidates.append((release, record))
            else:
                component_candidates.append((release, record))

    release_rank = {release: index for index, release in enumerate(selected_releases)}
    candidates = platform_candidates + model_candidates + component_candidates
    candidates.sort(key=lambda candidate: candidate_sort_key(candidate, release_rank))
    if max_candidates > 0:
        candidates = candidates[:max_candidates]

    print(
        "dell-suu: checking "
        f"{len(candidates)} Dell support candidates "
        f"(download_all={'yes' if download_all else 'no'}, max_candidates={max_candidates or 'unlimited'}, "
        f"download_workers={download_workers}, check_workers={check_workers})",
        file=sys.stderr,
    )

    def materialize_candidate(candidate):
        release, record = candidate
        if record.get("source") == "platform-csv":
            bin_paths = [download_platform_bin(cache_dir, release, record)]
        else:
            rpm = download_rpm(repo_base, cache_dir, release, record)
            extract_dir = extract_rpm(cache_dir, release, rpm)
            bin_paths = find_bins(extract_dir)

        bin_infos = []
        for bin_path in bin_paths:
            if not platform_filter_allows_name(platform_filter, bin_path.name):
                print(
                    f"dell-suu: skipping {bin_path.name}: not listed for this Dell platform in latest CSV",
                    file=sys.stderr,
                )
                continue

            package_info = {}
            try:
                package_info = parse_package_xml_path(
                    extract_package_xml(cache_dir, source_dir, bin_path)
                )
            except Exception as exc:
                print(
                    f"dell-suu: warning: failed to extract package metadata from {bin_path.name}: {exc}",
                    file=sys.stderr,
                )

            trusted_platform_record = (
                trust_platform_csv and record.get("source") == "platform-csv"
            )
            if (
                package_info
                and not package_supports_inventory(package_info, inventory)
                and not trusted_platform_record
            ):
                print(
                    f"dell-suu: skipping {bin_path.name}: package metadata does not match this system inventory",
                    file=sys.stderr,
                )
                continue
            if (
                package_info
                and trusted_platform_record
                and not package_supports_inventory(package_info, inventory)
            ):
                print(
                    "dell-suu: accepting "
                    f"{bin_path.name}: Dell platform CSV lists it for this model",
                    file=sys.stderr,
                )

            if (
                not package_info
                and require_metadata_match
                and record.get("match_kind") == "all"
                and not trusted_platform_record
            ):
                print(
                    f"dell-suu: skipping {bin_path.name}: no package metadata for all-package discovery",
                    file=sys.stderr,
                )
                continue

            bin_infos.append((bin_path, package_info))
        return release, record, bin_infos

    best_components = {}
    closed_chain_keys = set()
    closed_family_keys = set()
    closed_target_keys = set()
    materialized = 0
    skipped_closed = 0
    download_workers = min(download_workers, max(1, len(candidates)))
    check_workers = min(check_workers, max(1, len(candidates)))
    batch_size = max(download_workers, check_workers)

    def exact_target_keys(target_keys):
        exact_types = {
            "inventory-component-id",
            "inventory-pci",
        }
        exact = set()
        for key in target_keys or set():
            if not key or key[0] not in exact_types:
                continue
            if key[0].endswith("component-id") and str(key[-1]) in {"", "0"}:
                continue
            exact.add(key)
        return exact

    def should_serial_retry_missing_version(record, package_info, matched_components):
        if not env_flag("DELL_SUU_SUPPORT_SERIAL_RETRY_MISSING", True):
            return False
        if matched_components:
            return True
        haystack = normalise_text(
            " ".join(
                [
                    record.get("name", ""),
                    record.get("summary", ""),
                    package_info.get("name", ""),
                    package_info.get("device_display", ""),
                ]
            )
        )
        return bool(re.search(r"\b(bios|idrac|lifecycle)\b", haystack))

    def close_candidate(record, target_keys, reason):
        target_keys = exact_target_keys(target_keys)
        chain_keys = set(record.get("chain_keys") or ())
        if chain_keys:
            closed_chain_keys.update(chain_keys)
        family_key = record_family_key(record)
        if family_key and (chain_keys or target_keys):
            closed_family_keys.add(family_key)
        if target_keys:
            closed_target_keys.update(target_keys)
        if chain_keys or target_keys or family_key:
            print(
                "dell-suu: closing older update chain "
                f"for {record['name']} ({reason})",
                file=sys.stderr,
            )

    def checked_component_from_result(result):
        record = result["record"]
        bin_path = result["bin_path"]
        package_info = result["package_info"]
        matched_components = result["matched_components"]
        target_keys = result["target_keys"]
        trusted_platform_record = result["trusted_platform_record"]
        applicable = result.get("applicable")
        check = result.get("check") or {}
        error = result.get("error")

        if target_keys and target_keys & closed_target_keys:
            close_candidate(record, target_keys, "target already handled")
            return

        if error is not None:
            if trusted_platform_record and not check_platform_dups:
                print(
                    "dell-suu: skipping "
                    f"{bin_path.name}: platform CSV lists it for this model, "
                    "but DUP validation is disabled and no current version can be proven",
                    file=sys.stderr,
                )
            else:
                print(
                    f"dell-suu: warning: failed to check {bin_path.name}: {error}",
                    file=sys.stderr,
                )
            return

        if not package_info:
            package_info = parse_package_xml(bin_path)
            if not package_info:
                print(
                    f"dell-suu: warning: no package.xml found after checking {bin_path.name}; using DUP output only",
                    file=sys.stderr,
                )
            matched_components = matching_inventory_components(package_info, inventory)
            target_keys = package_target_keys(package_info, matched_components, record)

        matched_component = matched_components[0] if matched_components else {}
        component_id = (
            package_info.get("component_id")
            or matched_component.get("component_id")
            or ""
        )
        component_type = package_info.get("component_type") or "FRMW"
        package_version = (
            package_info.get("version")
            or check.get("package_version")
            or record.get("version")
        )
        installed_version = (
            check.get("installed_version") or matched_component.get("version") or ""
        )

        if not installed_version and not include_non_applicable:
            if should_serial_retry_missing_version(
                record, package_info, matched_components
            ):
                try:
                    retry_applicable, retry_check = check_dup(
                        source_dir, bin_path, locked=True
                    )
                    retry_installed_version = (
                        retry_check.get("installed_version")
                        or matched_component.get("version")
                        or ""
                    )
                    if retry_installed_version:
                        print(
                            "dell-suu: serial retry recovered installed version "
                            f"for {bin_path.name}",
                            file=sys.stderr,
                        )
                        applicable = retry_applicable
                        check = retry_check
                        installed_version = retry_installed_version
                        package_version = (
                            package_info.get("version")
                            or check.get("package_version")
                            or record.get("version")
                        )
                except Exception as exc:
                    print(
                        f"dell-suu: warning: serial retry failed for {bin_path.name}: {exc}",
                        file=sys.stderr,
                    )

        if not installed_version and not include_non_applicable:
            print(
                "dell-suu: skipping "
                f"{bin_path.name}: Dell DUP check did not report an installed version",
                file=sys.stderr,
            )
            close_candidate(record, target_keys, "missing installed version")
            return

        if not applicable and not include_non_applicable:
            if (
                package_version
                and installed_version
                and version_tuple(package_version)
                and version_tuple(installed_version)
                and version_tuple(package_version) <= version_tuple(installed_version)
            ):
                close_candidate(record, target_keys, "current or older")
            return

        display = one_line_text(
            component_display_by_id(inventory, component_id)
            or matched_component.get("display")
            or check.get("display")
            or package_info.get("device_display")
            or package_info.get("name")
            or record["summary"]
            or record["name"]
        )
        record_name_parts = record["name"].split("_", 2)
        package_id = (
            package_info.get("package_id")
            or package_info.get("release_id")
            or (
                record_name_parts[1]
                if len(record_name_parts) > 1
                else Path(record["name"]).stem
            )
        )
        rel_path = install_bin(repo_dir, result["release"], bin_path)
        compliance_message = compliance_message_for_versions(
            package_version, installed_version, applicable
        )

        component = {
            "packageID": package_id,
            "packageFilePath": rel_path,
            "name": display,
            "index": 0,
            "complianceStatus": not applicable,
            "componentType": component_type,
            "componentTypeDisplay": component_type_display(component_type),
            "categoryType": one_line_text(
                package_info.get("device_display") or display
            ),
            "criticality": one_line_text(
                package_info.get("criticality") or "Recommended"
            ),
            "componentID": int(component_id) if str(component_id).isdigit() else 0,
            "complianceMessage": compliance_message,
            "version": one_line_text(installed_version),
            "baseLineVersion": one_line_text(package_version),
            "rebootRequired": bool(package_info.get("reboot_required")),
            "_catalogBinPath": str(repo_dir / rel_path),
            "_catalogPackageXmlPath": package_info.get("package_xml_path", ""),
        }
        key = (
            component.get("componentType") or "",
            str(
                component.get("componentID")
                or component.get("packageID")
                or component.get("packageFilePath")
            ),
        )
        previous = best_components.get(key)
        if previous and version_tuple(previous.get("baseLineVersion")) >= version_tuple(
            component.get("baseLineVersion")
        ):
            close_candidate(record, target_keys, "older than best match")
            return
        best_components[key] = component
        close_candidate(record, target_keys, "applicable" if applicable else "matched")
        print(
            "dell-suu: support package "
            f"{'applicable' if applicable else 'matched'}: "
            f"{display} {installed_version} -> {package_version}",
            file=sys.stderr,
        )

    def check_item(item):
        try:
            applicable, check = check_dup(source_dir, item["bin_path"], locked=True)
            item["applicable"] = applicable
            item["check"] = check
            item["error"] = None
        except Exception as exc:
            item["applicable"] = None
            item["check"] = None
            item["error"] = exc
        return item

    next_candidate = 0
    while next_candidate < len(candidates):
        batch = []
        while next_candidate < len(candidates) and len(batch) < batch_size:
            candidate = candidates[next_candidate]
            next_candidate += 1
            record = candidate[1]
            if set(record.get("chain_keys") or ()) & closed_chain_keys:
                skipped_closed += 1
                continue
            if record_family_key(record) in closed_family_keys:
                skipped_closed += 1
                continue
            batch.append(candidate)

        if not batch:
            continue

        check_items = []
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=min(download_workers, len(batch))
        ) as executor:
            future_to_candidate = {
                executor.submit(materialize_candidate, candidate): candidate
                for candidate in batch
            }

            for future in concurrent.futures.as_completed(future_to_candidate):
                release, record = future_to_candidate[future]
                try:
                    release, record, bin_infos = future.result()
                except Exception as exc:
                    print(
                        f"dell-suu: warning: failed to materialize {record['name']}: {exc}",
                        file=sys.stderr,
                    )
                    continue

                materialized += 1
                print(
                    f"dell-suu: materialized {materialized}/{len(candidates)}: {record['name']}",
                    file=sys.stderr,
                )

                for bin_path, package_info in bin_infos:
                    matched_components = matching_inventory_components(
                        package_info, inventory
                    )
                    target_keys = package_target_keys(
                        package_info, matched_components, record
                    )
                    if target_keys and target_keys & closed_target_keys:
                        close_candidate(record, target_keys, "target already handled")
                        continue

                    trusted_platform_record = (
                        trust_platform_csv and record.get("source") == "platform-csv"
                    )
                    check_items.append(
                        {
                            "release": release,
                            "record": record,
                            "bin_path": bin_path,
                            "package_info": package_info,
                            "matched_components": matched_components,
                            "target_keys": target_keys,
                            "trusted_platform_record": trusted_platform_record,
                        }
                    )

        if not check_items:
            continue

        print(
            f"dell-suu: checking {len(check_items)} DUP candidate(s) with {min(check_workers, len(check_items))} worker(s); Dell DUP validation is serialized",
            file=sys.stderr,
        )
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=min(check_workers, len(check_items))
        ) as executor:
            future_to_item = {
                executor.submit(check_item, item): item for item in check_items
            }
            for future in concurrent.futures.as_completed(future_to_item):
                checked_component_from_result(future.result())

    if skipped_closed:
        print(
            f"dell-suu: skipped {skipped_closed} older support candidates after newer chain matches",
            file=sys.stderr,
        )

    components = list(best_components.values())
    catalog_entries = []
    for component in components:
        catalog_bin_path = component.pop("_catalogBinPath", "")
        catalog_xml_path = component.pop("_catalogPackageXmlPath", "")
        if not catalog_bin_path or not catalog_xml_path:
            continue
        entry = catalog_entry_from_package_xml(
            Path(catalog_xml_path),
            component["packageFilePath"],
            Path(catalog_bin_path),
        )
        if entry is not None:
            catalog_entries.append(entry)

    catalog_entry_count = inject_support_catalog_entries(
        repo_dir / "Catalog.xml", catalog_entries
    )
    support_paths = {
        component["packageFilePath"]
        for component in components
        if str(component.get("packageFilePath", "")).startswith("support-yum/")
    }
    catalog_paths = catalog_support_paths(repo_dir / "Catalog.xml")
    missing_catalog_paths = sorted(support_paths - catalog_paths, key=natural_key)
    if missing_catalog_paths:
        print(
            "dell-suu: warning: support cache is not fully present in Catalog.xml; GUI compliance will use checked DUP report",
            file=sys.stderr,
        )
        for rel_path in missing_catalog_paths[:20]:
            print(f"dell-suu: missing catalog entry: {rel_path}", file=sys.stderr)
        if len(missing_catalog_paths) > 20:
            print(
                f"dell-suu: ... and {len(missing_catalog_paths) - 20} more missing catalog entries",
                file=sys.stderr,
            )

    for index, component in enumerate(components, start=1):
        component["index"] = index

    report = {
        "SystemUpdateCompliance": [
            {
                "System": {
                    "id": inventory.get("system_id") or "",
                    "idType": "BIOS",
                    "hostAddress": "LocalHost",
                },
                "InvokerInfo": {
                    "name": "dell-suu-support-refresh",
                    "version": "1",
                    "command": "Dell platform support discovery",
                    "exitStatus": 0 if components else 34,
                    "statusMessage": (
                        "Compliance Success"
                        if components
                        else "No Applicable Update(s) Available"
                    ),
                },
                "BaseLineInformation": {
                    "identifier": "dell-platform-support",
                    "catalogName": "Dell platform support packages",
                    "version": time.strftime("%Y.%m.%d"),
                    "baseLocationAccessProtocols": ["HTTPS"],
                    "baseLocation": repo_base,
                    "dateTime": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "complianceStatus": not bool(components),
                },
                "UpdateableComponent": components,
            }
        ]
    }

    SUPPORT_REPORT.parent.mkdir(parents=True, exist_ok=True)
    SUPPORT_REPORT.write_text(json.dumps(report, indent=2) + "\n")
    write_support_cache_manifest(
        repo_dir,
        components,
        candidates,
        catalog_entry_count,
        dmidecode_data,
        inventory,
    )
    SUPPORT_STAMP.write_text(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()) + "\n")
    return 0


def load_json(path):
    if path.exists() and path.stat().st_size > 0:
        with path.open() as handle:
            return json.load(handle)
    return {
        "SystemUpdateCompliance": [
            {
                "System": {"id": "", "idType": "BIOS", "hostAddress": "LocalHost"},
                "InvokerInfo": {
                    "name": "DSU",
                    "version": "",
                    "command": "",
                    "exitStatus": 34,
                    "statusMessage": "No Applicable Update(s) Available",
                },
                "BaseLineInformation": {"complianceStatus": True},
                "UpdateableComponent": [],
            }
        ]
    }


def merge(args):
    compliance_path = Path(args.compliance)
    html_path = None
    if compliance_path.suffix.lower() in {".html", ".htm"}:
        html_path = compliance_path
        compliance_path = Path("/usr/libexec/dell_dup/Compliance.json")
    else:
        html_path = compliance_path.with_suffix(".html")
    support = load_json(SUPPORT_REPORT)
    support_components = support.get("SystemUpdateCompliance", [{}])[0].get(
        "UpdateableComponent", []
    )
    inventory = parse_inventory()

    base = load_json(compliance_path)
    if native_compliance_base_is_useful(base):
        save_native_compliance_base(base)
    elif NATIVE_COMPLIANCE_CACHE.exists():
        cached_base = load_json(NATIVE_COMPLIANCE_CACHE)
        if native_compliance_base_is_useful(cached_base):
            base = cached_base

    if not base.get("SystemUpdateCompliance"):
        base["SystemUpdateCompliance"] = load_json(Path("/nonexistent"))[
            "SystemUpdateCompliance"
        ]

    target = base["SystemUpdateCompliance"][0]
    target.setdefault("UpdateableComponent", [])
    original_components = target["UpdateableComponent"]
    removed_support_components = [
        component
        for component in original_components
        if str(component.get("packageFilePath", "")).startswith("support-yum/")
    ]
    target["UpdateableComponent"] = [
        component
        for component in original_components
        if not str(component.get("packageFilePath", "")).startswith("support-yum/")
    ]
    removed_support = len(removed_support_components)
    existing = {
        (
            component.get("packageFilePath", ""),
            str(component.get("componentID", "")),
            component.get("baseLineVersion", ""),
        )
        for component in target["UpdateableComponent"]
    }

    added = 0
    skipped_current = 0
    for component in support_components:
        component = compliance_component_for_gui(component)
        if support_component_is_current_in_inventory(component, inventory):
            skipped_current += 1
            continue

        key = (
            component.get("packageFilePath", ""),
            str(component.get("componentID", "")),
            component.get("baseLineVersion", ""),
        )
        if key in existing:
            continue
        target["UpdateableComponent"].append(component)
        existing.add(key)
        added += 1

    if added:
        for index, component in enumerate(target["UpdateableComponent"], start=1):
            component["index"] = index
        target.setdefault("InvokerInfo", {})
        target["InvokerInfo"]["exitStatus"] = 0
        target["InvokerInfo"]["statusMessage"] = "Compliance Success"
        target.setdefault("BaseLineInformation", {})
        target["BaseLineInformation"]["complianceStatus"] = False
    elif removed_support:
        for index, component in enumerate(target["UpdateableComponent"], start=1):
            component["index"] = index
        target.setdefault("InvokerInfo", {})
        target["InvokerInfo"]["exitStatus"] = 0 if target["UpdateableComponent"] else 34
        target["InvokerInfo"]["statusMessage"] = (
            "Compliance Success"
            if target["UpdateableComponent"]
            else "No Applicable Update(s) Available"
        )
        target.setdefault("BaseLineInformation", {})
        target["BaseLineInformation"]["complianceStatus"] = not bool(
            target["UpdateableComponent"]
        )

    compliance_path.parent.mkdir(parents=True, exist_ok=True)
    compliance_path.write_text(json.dumps(base, separators=(",", ":")) + "\n")
    report_path = compliance_path.parent / "ComplianceReport.json"
    report_path.write_text(json.dumps(base, separators=(",", ":")) + "\n")
    write_suu_status(compliance_path.parent / "SUU_STATUS.json")
    runtime_compliance = Path("/usr/libexec/dell_dup/Compliance.json")
    if runtime_compliance.parent.exists() and runtime_compliance != compliance_path:
        runtime_compliance.write_text(json.dumps(base, separators=(",", ":")) + "\n")
        runtime_report = runtime_compliance.parent / "ComplianceReport.json"
        runtime_report.write_text(json.dumps(base, separators=(",", ":")) + "\n")
        write_suu_status(runtime_compliance.parent / "SUU_STATUS.json")
    if html_path is not None:
        write_compliance_html(html_path, base)
        runtime_html = Path("/usr/libexec/dell_dup/Compliance.html")
        if runtime_html.parent.exists() and runtime_html != html_path:
            write_compliance_html(runtime_html, base)
    print(
        f"dell-suu: support updates merged: {added}, skipped current: {skipped_current}, removed stale: {removed_support}",
        file=sys.stderr,
    )
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--merge", action="store_true")
    parser.add_argument("--resolve-suu-iso", action="store_true")
    parser.add_argument("--source", default="/var/cache/dell/suu/online-source")
    parser.add_argument(
        "--repo", default="/var/cache/dell/suu/online-source/repository"
    )
    parser.add_argument("--cache-root", default="/var/cache/dell")
    parser.add_argument("--compliance", default="/usr/libexec/dell_dup/Compliance.json")
    parser.add_argument("--model", default="")
    args = parser.parse_args()

    if args.refresh:
        return refresh(args)
    if args.merge:
        return merge(args)
    if args.resolve_suu_iso:
        return resolve_suu_iso(args)
    parser.error("use --refresh, --merge, or --resolve-suu-iso")


if __name__ == "__main__":
    raise SystemExit(main())
