{ lib
, fetchFromGitHub
, python3Packages
}:

python3Packages.buildPythonApplication rec {
  pname = "autorecon";
  version = "2.0.36-unstable-2026-06-21";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "AutoRecon";
    repo = "AutoRecon";
    rev = "e7e98f60bdc5fb1695159c1bbcdfdf2746d30fa6";
    hash = "sha256-xSRfsfLRYt7jS5Jpp6fz5/Kj2DiNI3hgUbUI9w3AHkw=";
  };

  build-system = with python3Packages; [
    poetry-core
  ];

  nativeBuildInputs = with python3Packages; [
    pythonRelaxDepsHook
  ];

  pythonRelaxDeps = [
    "impacket"
    "psutil"
  ];

  dependencies = with python3Packages; [
    colorama
    impacket
    platformdirs
    psutil
    requests
    toml
    unidecode
  ];

  pythonImportsCheck = [ "autorecon" ];

  meta = {
    description = "Multi-threaded network reconnaissance tool for automated service enumeration";
    homepage = "https://github.com/AutoRecon/AutoRecon";
    license = lib.licenses.gpl3Only;
    mainProgram = "autorecon";
  };
}
