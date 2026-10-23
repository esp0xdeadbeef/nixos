# CVE-2026-111943 / eMudhra intermediate CA compromise (2026-10-17).
#
# Eight eMudhra intermediate CA private keys were recoverable from the
# certificates themselves (flawed key generation), so anyone could impersonate
# any site to clients that still trust the affected subtree.  Browsers block it
# via OneCRL/CRLSets, but OpenSSL/libcurl and other clients that read a static
# CA bundle do not consume revocation information, so they keep verifying.
#
# Our `nixpkgs` pin (26.05) now CONTAINS nixpkgs PR #576390: security.pki
# blacklists these roots unconditionally, so NixOS' own system bundle is already
# covered.  This overlay is still required for the other half: plain
# `pkgs.cacert` ships `blacklist ? []`, so non-NixOS consumers of pkgs.cacert /
# pkgs.nss-cacert (Go, containers, anything reading the bundle directly) would
# still trust the compromised subtree.
#
# Remove this overlay once the pin ships NSS 3.131.1+, which drops the roots
# from the NSS bundle upstream, making the blacklist unnecessary.
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
    "NOTE: local eMudhra CA-distrust overlay is active (CVE-2026-111943): "
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
