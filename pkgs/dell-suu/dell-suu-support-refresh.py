import argparse
import concurrent.futures
import gzip
import hashlib
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

DEFAULT_REPO_BASE = "https://linux.dell.com/repo/hardware/"
USER_AGENT = "Mozilla/5.0"
SUPPORT_REPORT = Path("/var/lib/dell/suu/support-upgrades.json")
SUPPORT_STAMP = Path("/var/lib/dell/suu/support-refresh.stamp")
DUP_LOCK = threading.Lock()
FILE_LOCKS = {}
FILE_LOCKS_LOCK = threading.Lock()
HASH_CHUNK_SIZE = 4 * 1024 * 1024

XML_NS = {"m": "http://linux.duke.edu/metadata/common"}


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


def normalise_text(value):
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def version_tuple(value):
    parts = []
    for part in re.split(r"[^0-9]+", value or ""):
        if part:
            parts.append(int(part))
    return tuple(parts)


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


def run_dup(cmd, timeout=300, check=False):
    with DUP_LOCK:
        return run(cmd, timeout=timeout, check=check)


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
            }
            if not (
                component["display"]
                or component["component_id"]
                or pci_tuple_has_data(component["pci"])
            ):
                continue

            key = (
                component["component_id"],
                component["display"],
                component["pci"],
            )
            existing = component_index.get(key)
            if existing is None:
                component_index[key] = component
                inventory["components"].append(component)
                continue

            if not existing.get("version") and component.get("version"):
                existing["version"] = component["version"]
            if not existing.get("component_type") and component.get("component_type"):
                existing["component_type"] = component["component_type"]

    return inventory


def model_tokens(dmidecode_data):
    raw_values = [
        dmidecode_data.get("product", ""),
        dmidecode_data.get("sku", ""),
        os.environ.get("DELL_SUU_SUPPORT_MODEL", ""),
    ]
    tokens = set()
    for raw in raw_values:
        for value in re.findall(
            r"(?:PowerEdge\s+)?([A-Z]{1,3}\d{3,4}[A-Z]*|XE\d{3,4}|MX\d{4}[A-Z]*)",
            raw,
            flags=re.I,
        ):
            tokens.add(value.upper())
        model_match = re.search(r"ModelName=([^;]+)", raw)
        if model_match:
            tokens.update(model_tokens({"product": model_match.group(1), "sku": ""}))
    return sorted(tokens, key=len, reverse=True)


def component_terms(inventory):
    ignored = {
        "adapter",
        "access",
        "application",
        "a00",
        "a37",
        "bios",
        "bit",
        "broadcom",
        "collector",
        "controller",
        "cruzerblade",
        "dell",
        "diagnostics",
        "driver",
        "drivers",
        "eno1",
        "eno2",
        "eno3",
        "eno4",
        "ethernet",
        "firmware",
        "gigabit",
        "inc",
        "intel",
        "integrated",
        "lifecycle",
        "mini",
        "module",
        "nvidia",
        "pack",
        "perc",
        "power",
        "poweredge",
        "qlogic",
        "remote",
        "rev",
        "server",
        "service",
        "supply",
        "system",
        "uefi",
        "version",
    }
    terms = set()
    inventory_text = normalise_text(
        " ".join(c.get("display", "") for c in inventory["components"])
    )
    for component in inventory["components"]:
        text = component.get("display", "")
        for word in re.findall(r"[A-Za-z][A-Za-z0-9]{2,}", text):
            lower = word.lower()
            if lower not in ignored:
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
        (3, ("perc", "h730", "sas raid", "sas non raid")),
        (4, ("network", "ethernet", "intel", "x520", "broadcom")),
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
    return sorted(path for path in extract_dir.rglob("*.BIN") if path.is_file())


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


def check_dup(source_dir, bin_path):
    proc = run_dup(
        [FHS, source_dir, "--launcher", str(bin_path), "--", "-q", "-c"], timeout=360
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
        if stripped.lower().startswith("package version:"):
            package_version = stripped.split(":", 1)[1].strip()
        elif stripped.lower().startswith("installed version:"):
            installed_version = stripped.split(":", 1)[1].strip()
        elif (
            not display
            and not stripped.startswith("DELL ")
            and "warning:" not in stripped.lower()
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
        print("dell-suu: using cached Dell yum support package report", file=sys.stderr)
        return 0

    repo_base = (
        os.environ.get("DELL_SUU_SUPPORT_REPO_BASE", DEFAULT_REPO_BASE).rstrip("/")
        + "/"
    )
    cache_dir = Path(args.cache_root) / "suu" / "support-yum"
    repo_dir = Path(args.repo)
    source_dir = args.source
    releases = list_releases(repo_base)
    max_releases = env_int("DELL_SUU_SUPPORT_MAX_RELEASES", 80)
    max_candidates = env_int("DELL_SUU_SUPPORT_MAX_CANDIDATES", 200)
    metadata_workers = max(1, env_int("DELL_SUU_SUPPORT_METADATA_WORKERS", 6))
    download_workers = max(1, env_int("DELL_SUU_SUPPORT_DOWNLOAD_WORKERS", 6))
    download_all = env_flag("DELL_SUU_SUPPORT_DOWNLOAD_ALL", False)
    require_metadata_match = env_flag("DELL_SUU_SUPPORT_REQUIRE_METADATA_MATCH", True)

    dmidecode_data = parse_dmidecode()
    inventory = parse_inventory()
    tokens = model_tokens(dmidecode_data)
    terms = component_terms(inventory)
    term_major_versions = inventory_major_versions(inventory)

    print(
        "dell-suu: Dell support discovery "
        f"model={dmidecode_data.get('product') or 'unknown'} "
        f"systemID={inventory.get('system_id') or 'unknown'} "
        f"inventoryComponents={len(inventory['components'])} "
        f"tokens={','.join(tokens) or 'none'}",
        file=sys.stderr,
    )

    seen_names = set()
    model_candidates = []
    component_candidates = []
    selected_releases = releases[:max_releases]
    metadata_by_release = {}
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

    for release in selected_releases:
        metadata = metadata_by_release.get(release)
        if not metadata:
            continue

        for record in package_records(metadata):
            if record["name"] in seen_names:
                continue
            kind = package_match_kind(
                record, tokens, terms, term_major_versions, download_all
            )
            if not kind:
                continue
            seen_names.add(record["name"])
            record = dict(record)
            record["match_kind"] = kind
            if kind in {"model", "all"}:
                model_candidates.append((release, record))
            else:
                component_candidates.append((release, record))

    release_rank = {release: index for index, release in enumerate(selected_releases)}
    candidates = model_candidates + component_candidates
    candidates.sort(
        key=lambda candidate: (
            candidate_priority(candidate[1]),
            release_rank.get(candidate[0], len(selected_releases)),
        )
    )
    if max_candidates > 0:
        candidates = candidates[:max_candidates]

    print(
        "dell-suu: checking "
        f"{len(candidates)} Dell yum support candidates "
        f"(download_all={'yes' if download_all else 'no'}, max_candidates={max_candidates or 'unlimited'}, "
        f"download_workers={download_workers})",
        file=sys.stderr,
    )

    def materialize_candidate(candidate):
        release, record = candidate
        rpm = download_rpm(repo_base, cache_dir, release, record)
        extract_dir = extract_rpm(cache_dir, release, rpm)
        bin_infos = []
        for bin_path in find_bins(extract_dir):
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

            if package_info and not package_supports_inventory(package_info, inventory):
                print(
                    f"dell-suu: skipping {bin_path.name}: package metadata does not match this system inventory",
                    file=sys.stderr,
                )
                continue

            if (
                not package_info
                and require_metadata_match
                and record.get("match_kind") == "all"
            ):
                print(
                    f"dell-suu: skipping {bin_path.name}: no package metadata for all-package discovery",
                    file=sys.stderr,
                )
                continue

            bin_infos.append((bin_path, package_info))
        return release, record, bin_infos

    best_components = {}
    materialized = 0
    download_workers = min(download_workers, max(1, len(candidates)))

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=download_workers
    ) as executor:
        future_to_candidate = {
            executor.submit(materialize_candidate, candidate): candidate
            for candidate in candidates
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
                try:
                    applicable, check = check_dup(source_dir, bin_path)
                except Exception as exc:
                    print(
                        f"dell-suu: warning: failed to check {bin_path.name}: {exc}",
                        file=sys.stderr,
                    )
                    continue
                if not applicable:
                    continue

                if not package_info:
                    package_info = parse_package_xml(bin_path)
                    if not package_info:
                        print(
                            f"dell-suu: warning: no package.xml found after checking {bin_path.name}; using DUP output only",
                            file=sys.stderr,
                        )

                matched_components = matching_inventory_components(
                    package_info, inventory
                )
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
                    check.get("installed_version")
                    or matched_component.get("version")
                    or ""
                )
                display = (
                    component_display_by_id(inventory, component_id)
                    or matched_component.get("display")
                    or check.get("display")
                    or package_info.get("device_display")
                    or package_info.get("name")
                    or record["summary"]
                    or record["name"]
                )
                package_id = (
                    package_info.get("package_id")
                    or package_info.get("release_id")
                    or record["name"].split("_", 2)[1]
                )
                rel_path = install_bin(repo_dir, release, bin_path)

                component = {
                    "packageID": package_id,
                    "packageFilePath": rel_path,
                    "name": display,
                    "index": 0,
                    "complianceStatus": False,
                    "componentType": component_type,
                    "componentTypeDisplay": component_type_display(component_type),
                    "categoryType": package_info.get("device_display") or display,
                    "criticality": package_info.get("criticality") or "Recommended",
                    "componentID": (
                        int(component_id) if str(component_id).isdigit() else 0
                    ),
                    "complianceMessage": "Upgrade",
                    "version": installed_version,
                    "baseLineVersion": package_version,
                    "rebootRequired": bool(package_info.get("reboot_required")),
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
                if previous and version_tuple(
                    previous.get("baseLineVersion")
                ) >= version_tuple(component.get("baseLineVersion")):
                    continue
                best_components[key] = component
                print(
                    f"dell-suu: support package applicable: {display} {installed_version} -> {package_version}",
                    file=sys.stderr,
                )

    components = list(best_components.values())

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
                    "command": "Dell yum repository support discovery",
                    "exitStatus": 0 if components else 34,
                    "statusMessage": (
                        "Compliance Success"
                        if components
                        else "No Applicable Update(s) Available"
                    ),
                },
                "BaseLineInformation": {
                    "identifier": "dell-yum-support",
                    "catalogName": "Dell yum repository support packages",
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
    if compliance_path.suffix.lower() in {".html", ".htm"}:
        compliance_path = Path("/usr/libexec/dell_dup/Compliance.json")
    support = load_json(SUPPORT_REPORT)
    support_components = support.get("SystemUpdateCompliance", [{}])[0].get(
        "UpdateableComponent", []
    )
    if not support_components:
        return 0

    base = load_json(compliance_path)
    if not base.get("SystemUpdateCompliance"):
        base["SystemUpdateCompliance"] = load_json(Path("/nonexistent"))[
            "SystemUpdateCompliance"
        ]

    target = base["SystemUpdateCompliance"][0]
    target.setdefault("UpdateableComponent", [])
    existing = {
        (
            component.get("packageFilePath", ""),
            str(component.get("componentID", "")),
            component.get("baseLineVersion", ""),
        )
        for component in target["UpdateableComponent"]
    }

    added = 0
    for component in support_components:
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

    compliance_path.parent.mkdir(parents=True, exist_ok=True)
    compliance_path.write_text(json.dumps(base, separators=(",", ":")) + "\n")
    runtime_compliance = Path("/usr/libexec/dell_dup/Compliance.json")
    if runtime_compliance.parent.exists() and runtime_compliance != compliance_path:
        runtime_compliance.write_text(json.dumps(base, separators=(",", ":")) + "\n")
    print(f"dell-suu: support updates merged: {added}", file=sys.stderr)
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--merge", action="store_true")
    parser.add_argument("--source", default="/var/cache/dell/suu/online-source")
    parser.add_argument(
        "--repo", default="/var/cache/dell/suu/online-source/repository"
    )
    parser.add_argument("--cache-root", default="/var/cache/dell")
    parser.add_argument("--compliance", default="/usr/libexec/dell_dup/Compliance.json")
    args = parser.parse_args()

    if args.refresh:
        return refresh(args)
    if args.merge:
        return merge(args)
    parser.error("use --refresh or --merge")


if __name__ == "__main__":
    raise SystemExit(main())
