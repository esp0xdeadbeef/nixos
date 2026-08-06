#!/usr/bin/env python3
"""Render Postfix/Dovecot runtime config from SOPS mailbox sets and accounts."""

import argparse
import os
import subprocess
import sys
from pathlib import Path


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def require_env(name: str) -> str:
    val = os.environ.get(name)
    if not val:
        die(f"required mail runtime variable is missing: {name}")
    return val


def source_env(path: str) -> None:
    """Source a KEY=VALUE env file into os.environ."""
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip("'\"")
            os.environ[key] = value


def bool_true(val: str | None) -> bool:
    return str(val).lower() in ("1", "true", "yes", "on")


def expand_address(domain: str, value: str) -> str:
    if "@" in value:
        return value
    return f"{value}@{domain}"


def write_address_domain(address: str, output: Path) -> None:
    domain = address.partition("@")[2]
    if domain and domain != address:
        with open(output, "a") as f:
            f.write(f"{domain}\n")


def account_env_path(account_ref: str, env_path_list: str) -> str:
    secret_name = f"mail/accounts/{account_ref}/env"
    with open(env_path_list) as f:
        for line in f:
            line = line.rstrip("\n")
            if "=" not in line:
                continue
            name, _, path = line.partition("=")
            if name == secret_name:
                return path
    die(f"mail account secret is not declared for this server: {account_ref}")
    return ""  # unreachable


def account_var(name: str) -> str:
    return os.environ.get(f"MAIL_ACCOUNT_{name}", "")


def account_address(domain: str, account_ref: str) -> str:
    localpart = account_var("LOCALPART")
    if not localpart:
        die(f"mail account is missing LOCALPART: {account_ref}")
    return f"{localpart}@{domain}"


def apply_mailbox_aliases(
    *,
    domain: str,
    first_domain: str,
    catchall_target: str,
    catchall_password_hash: str,
    catchall_owner_home: str,
    mailbox_aliases: str,
    valias: Path,
    vaccounts_raw: Path,
    passwd_file: Path,
    valias_domains_raw: Path,
) -> None:
    if not mailbox_aliases:
        return

    for alias_spec in mailbox_aliases.split():
        if not alias_spec:
            continue

        alias_localpart, _, targets = alias_spec.partition("=")

        # Fall back to catchall if no explicit targets
        if not targets or targets == alias_spec:
            if not catchall_password_hash:
                continue
            catchall_addr = expand_address(first_domain, catchall_target)
            alias_address = expand_address(domain, alias_localpart)
            write_address_domain(alias_address, valias_domains_raw)
            with open(valias, "a") as va, open(vaccounts_raw, "a") as vr, open(
                passwd_file, "a"
            ) as pf:
                va.write(f"{alias_address} {catchall_addr}\n")
                vr.write(f"{alias_address} {catchall_addr}\n")
                pf.write(
                    f"{alias_address}:{catchall_password_hash}::::"
                    f"{catchall_owner_home}::mail=maildir:{catchall_owner_home}/mail\n"
                )
        else:
            # Comma-separated targets -> Postfix recipient list
            alias_address = expand_address(domain, alias_localpart)
            write_address_domain(alias_address, valias_domains_raw)

            expanded: list[str] = []
            for target in targets.split(","):
                target = target.strip()
                if not target:
                    continue
                expanded.append(expand_address(first_domain, target))

            if expanded:
                with open(valias, "a") as f:
                    f.write(f"{alias_address} {','.join(expanded)}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mail-env", required=True)
    parser.add_argument("--network-env", required=True)
    parser.add_argument("--mailbox-set-env-list", required=True)
    parser.add_argument("--mail-account-env-list", required=True)
    parser.add_argument("--postfix-dir", required=True)
    parser.add_argument("--dovecot-dir", required=True)
    parser.add_argument("--tls-fullchain", required=True)
    parser.add_argument("--tls-key", required=True)
    parser.add_argument("--shared-sender-login-map", required=True)
    args = parser.parse_args()

    if not os.path.isfile(args.mail_env):
        die(f"mail runtime env is missing: {args.mail_env}")

    source_env(args.mail_env)
    source_env(args.network_env)

    require_env("MAIL_FQDN")
    require_env("PUBLIC_IPV4")
    require_env("WEB_IPV6")

    postfix_dir = Path(args.postfix_dir)
    dovecot_dir = Path(args.dovecot_dir)

    postfix_dir.mkdir(mode=0o750, parents=True, exist_ok=True)
    dovecot_dir.mkdir(mode=0o750, parents=True, exist_ok=True)
    subprocess.run(["chown", "root:postfix", str(postfix_dir)], check=True)
    subprocess.run(["chown", "root:dovecot2", str(dovecot_dir)], check=True)

    vdomains = postfix_dir / "vdomains"
    vdomains_raw = postfix_dir / "vdomains.raw"
    valias_domains = postfix_dir / "valias_domains"
    valias_domains_raw = postfix_dir / "valias_domains.raw"
    valias = postfix_dir / "valias"
    vmailbox = postfix_dir / "vmailbox"
    vaccounts_raw = postfix_dir / "vaccounts.raw"
    vaccounts = postfix_dir / "vaccounts"
    shared_vaccounts = Path(args.shared_sender_login_map)
    local_sender_reject = postfix_dir / "local_sender_reject"
    passwd_file = dovecot_dir / "passwd"

    # Truncate all output files
    for f in (
        vdomains,
        vdomains_raw,
        valias_domains,
        valias_domains_raw,
        valias,
        vmailbox,
        vaccounts_raw,
        vaccounts,
        shared_vaccounts,
        local_sender_reject,
        passwd_file,
    ):
        f.write_text("")

    first_domain = ""

    with open(args.mailbox_set_env_list) as msel:
        for line in msel:
            line = line.rstrip("\n")
            if not line:
                continue
            mailbox_set_path = line.partition("=")[2]

            if not os.path.isfile(mailbox_set_path):
                die(f"mailbox set env is missing: {mailbox_set_path}")

            source_env(mailbox_set_path)
            domain = os.environ.pop("MAILBOX_DOMAIN", "")
            account_ids = os.environ.pop("MAILBOX_ACCOUNTS", "")
            catchall_target = os.environ.pop("MAILBOX_CATCHALL", "")
            mailbox_aliases_str = os.environ.pop("MAILBOX_ALIASES", "")

            if not domain:
                die(f"mailbox set is missing MAILBOX_DOMAIN: {mailbox_set_path}")
            if not account_ids:
                die(f"mailbox set is missing MAILBOX_ACCOUNTS: {mailbox_set_path}")
            if not first_domain:
                first_domain = domain

            with open(vdomains_raw, "a") as f:
                f.write(f"{domain}\n")

            catchall_password_hash = ""
            catchall_owner_home = ""

            for account_ref in account_ids.replace(",", " ").split():
                account_ref = account_ref.strip()
                if not account_ref:
                    continue

                env_path = account_env_path(account_ref, args.mail_account_env_list)
                if not os.path.isfile(env_path):
                    die(f"mail account env is missing: {env_path}")

                # Clear previous account vars
                for k in list(os.environ):
                    if k.startswith("MAIL_ACCOUNT_"):
                        del os.environ[k]

                source_env(env_path)

                if not bool_true(os.environ.get("MAIL_ACCOUNT_SERVER", "true")):
                    continue

                address = account_address(domain, account_ref)
                aliases_str = account_var("ALIASES")
                password = account_var("PASSWORD")
                owner_domain = address.partition("@")[2]
                owner_local = address.partition("@")[0]
                owner_home = f"/var/vmail/{owner_domain}/{owner_local}"

                if not password:
                    die(f"mail account is missing PASSWORD: {account_ref}")

                result = subprocess.run(
                    ["doveadm", "pw", "-s", "BLF-CRYPT", "-p", password],
                    capture_output=True,
                    text=True,
                    check=True,
                )
                password_hash = result.stdout.strip()

                with open(vmailbox, "a") as vm, open(vaccounts_raw, "a") as vr, open(
                    passwd_file, "a"
                ) as pf:
                    vm.write(f"{address} {address}\n")
                    vr.write(f"{address} {address}\n")
                    pf.write(f"{address}:{password_hash}::::::\n")

                for alias in aliases_str.replace(",", " ").split():
                    alias = alias.strip()
                    if not alias:
                        continue
                    alias_address = expand_address(domain, alias)
                    write_address_domain(alias_address, valias_domains_raw)
                    with open(valias, "a") as va, open(vaccounts_raw, "a") as vr, open(
                        passwd_file, "a"
                    ) as pf:
                        va.write(f"{alias_address} {address}\n")
                        vr.write(f"{alias_address} {address}\n")
                        pf.write(
                            f"{alias_address}:{password_hash}::::"
                            f"{owner_home}::mail=maildir:{owner_home}/mail\n"
                        )

                if catchall_target:
                    catchall_check = expand_address(first_domain, catchall_target)
                    if address == catchall_check:
                        catchall_password_hash = password_hash
                        catchall_owner_home = owner_home

            apply_mailbox_aliases(
                domain=domain,
                first_domain=first_domain,
                catchall_target=catchall_target,
                catchall_password_hash=catchall_password_hash,
                catchall_owner_home=catchall_owner_home,
                mailbox_aliases=mailbox_aliases_str,
                valias=valias,
                vaccounts_raw=vaccounts_raw,
                passwd_file=passwd_file,
                valias_domains_raw=valias_domains_raw,
            )

            if catchall_target:
                catchall_address = expand_address(first_domain, catchall_target)
                with open(valias, "a") as f:
                    f.write(f"@{domain} {catchall_address}\n")

    if not first_domain:
        die("no mailbox set domains were configured")

    # vdomains
    seen: set[str] = set()
    with open(vdomains_raw) as raw, open(vdomains, "w") as out:
        for line in raw:
            line = line.strip()
            if line and line not in seen:
                seen.add(line)
                out.write(f"{line} OK\n")

    # local_sender_reject
    seen.clear()
    with open(vdomains_raw) as raw, open(local_sender_reject, "w") as out:
        for line in raw:
            line = line.strip()
            if line and line not in seen:
                seen.add(line)
                out.write(
                    f"{line} REJECT Sender domain is locally hosted; submit via authenticated SMTP on port 587\n"
                )

    # valias_domains
    mailbox_domains: set[str] = set()
    with open(vdomains_raw) as raw:
        for line in raw:
            line = line.strip()
            if line:
                mailbox_domains.add(line)
    seen.clear()
    with open(valias_domains_raw) as raw, open(valias_domains, "w") as out:
        for line in raw:
            line = line.strip()
            if line and line not in mailbox_domains and line not in seen:
                seen.add(line)
                out.write(f"{line} OK\n")

    # vaccounts — dedup sender login entries
    senders: dict[str, set[str]] = {}
    sender_order: list[str] = []
    with open(vaccounts_raw) as raw:
        for line in raw:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            sender = parts[0]
            if sender not in senders:
                senders[sender] = set()
                sender_order.append(sender)
            for i in range(1, len(parts)):
                for login in parts[i].split(","):
                    login = login.strip()
                    if login:
                        senders[sender].add(login)
    with open(vaccounts, "w") as out:
        for sender in sender_order:
            out.write(f"{sender} {','.join(senders[sender])}\n")

    # Cleanup raw files
    vdomains_raw.unlink(missing_ok=True)
    valias_domains_raw.unlink(missing_ok=True)
    vaccounts_raw.unlink(missing_ok=True)

    # Set ownership and permissions
    for f in (
        vdomains,
        valias_domains,
        valias,
        vmailbox,
        vaccounts,
        shared_vaccounts,
        local_sender_reject,
    ):
        subprocess.run(["chown", "root:postfix", str(f)], check=True)
        subprocess.run(["chmod", "0640", str(f)], check=True)
    subprocess.run(["chown", "root:dovecot2", str(passwd_file)], check=True)
    subprocess.run(["chmod", "0440", str(passwd_file)], check=True)

    # Postmap
    for f in (
        vdomains,
        valias_domains,
        valias,
        vmailbox,
        vaccounts,
        shared_vaccounts,
        local_sender_reject,
    ):
        subprocess.run(["postmap", str(f)], check=True)
        db = Path(str(f) + ".db")
        subprocess.run(["chown", "root:postfix", str(db)], check=True)
        subprocess.run(["chmod", "0640", str(db)], check=True)

    # Postfix config
    main_cf = Path("/var/lib/postfix/conf/main.cf")
    if main_cf.is_symlink():
        target = main_cf.resolve()
        content = target.read_bytes()
        main_cf.unlink()
        main_cf.write_bytes(content)

    subprocess.run(
        [
            "postconf",
            "-c",
            "/var/lib/postfix/conf",
            "-e",
            f"myhostname = {os.environ['MAIL_FQDN']}",
            f"mydomain = {first_domain}",
            f"myorigin = {first_domain}",
            f"smtp_bind_address = {os.environ['PUBLIC_IPV4']}",
            f"smtp_bind_address6 = {os.environ['WEB_IPV6']}",
            f"smtp_helo_name = {os.environ['MAIL_FQDN']}",
            f"smtpd_banner = {os.environ['MAIL_FQDN']} ESMTP",
            f"virtual_mailbox_domains = hash:{vdomains}",
            f"virtual_alias_domains = hash:{valias_domains}",
            f"virtual_mailbox_maps = hash:{vmailbox}",
            f"virtual_alias_maps = hash:{valias}",
            f"smtpd_sender_login_maps = hash:{vaccounts} hash:{shared_vaccounts}",
            "smtpd_sender_restrictions = permit_mynetworks, "
            f"permit_sasl_authenticated, check_sender_access hash:{local_sender_reject}",
            f"smtpd_tls_chain_files = {args.tls_key} {args.tls_fullchain}",
        ],
        check=True,
    )

    subprocess.run(["postfix", "-c", "/var/lib/postfix/conf", "check"], check=True)


if __name__ == "__main__":
    main()
