# CVE-2026-111943 / eMudhra intermediate CA compromise (2026-10-17).
#
# Eight eMudhra intermediate CA private keys were recoverable from the
# certificates themselves (flawed key generation), so anyone could impersonate
# any site to clients that still trust the affected subtree.  Browsers block it
# via OneCRL/CRLSets, but OpenSSL/libcurl and other clients that read a static
# CA bundle do not consume revocation information, so they keep verifying.
#
# Our `nixpkgs` pin (26.05) predates the nixpkgs mitigation; `nixpkgs-unstable`
# already carries it in nixos/modules/security/ca.nix (nixpkgs PRs #576390,
# #576401, tracking issue #576485, NSS 3.131.1).  This overlay reproduces the
# exact upstream blacklist so stable-pinned hosts (all NixOS hosts here) get the
# same protection, and so non-NixOS consumers of pkgs.cacert / pkgs.nss-cacert
# (Go, containers, anything reading the bundle directly) are covered too.
#
# Note: `security.pki` rebuilds its bundle with
# `cacert.override { blacklist = cfg.caCertificateBlacklist ++ [<upstream list>]; }`,
# so for the SYSTEM bundle the same roots are applied via
# `security.pki.caCertificateBlacklist` in flake.nix.  Both halves are needed.
#
# Remove this overlay (and the flake-level caCertificateBlacklist) once the
# `nixpkgs` pin is advanced to a revision containing nixpkgs PR #576390.
#
# Upstream list (nixpkgs #576485):
#   "Comodo AAA Services root"      # CVE-2026-111943
#   "emSign ECC Root CA - G3"       # NSS 26d38a0c3fb8
#   "emSign Root CA - C1"           # NSS 8159223c48ce
#   "emSign ECC Root CA - C3"       # NSS 8159223c48ce
# (`emSign Root CA - G1` was deliberately NOT distrusted by NSS.)
final: prev:
let
  blacklist = [
    "Comodo AAA Services root"
    "emSign ECC Root CA - G3"
    "emSign Root CA - C1"
    "emSign ECC Root CA - C3"
  ];

  warn = builtins.trace (
    "WARNING: local eMudhra CA-distrust overlay is active (CVE-2026-111943): "
    + "cacert blacklist = [ ${builtins.concatStringsSep ", " (map (n: ''"${n}"'') blacklist)} ]; "
    + "remove it once the nixpkgs pin contains PR #576390."
  );
in
{
  cacert = warn (
    prev.cacert.override {
      blacklist = (prev.cacert.blacklist or [ ]) ++ blacklist;
    }
  );
}
