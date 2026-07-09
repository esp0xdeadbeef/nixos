{
  description = "Flake voor pentest-tools: Python, PowerShell, Azure CLI, Azure PowerShell, Microsoft Graph, AADInternals, O365spray en MFA-Sweep";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    azurePS = {
      url = "https://github.com/Azure/azure-powershell/releases/download/v13.4.0-April2025/Az-Cmdlets-13.4.0.39483.tar.gz";
      flake = false;
    };
    aadinternals = {
      url = "github:Gerenios/AADInternals";
      flake = false;
    };
    o365spray = {
      url = "github:0xZDH/o365spray";
      flake = false;
    };
    mfasweep = {
      url = "github:dafthack/MFASweep";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , azurePS
    , aadinternals
    , o365spray
    , mfasweep
    ,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Azure PowerShell modules: pakketten direct uit de tarball uitpakken
      azModules = pkgs.stdenv.mkDerivation {
        name = "az-powershell-modules";
        src = azurePS;
        buildCommand = ''
          mkdir -p $out/share/powershell/Modules
          if [ -f "$src" ]; then
            echo "Extracting tarball..."
            tar -xzf $src -C $out/share/powershell/Modules
          else
            echo "Copying from directory..."
            cp -r $src/* $out/share/powershell/Modules/
          fi
        '';
      };

      # AADInternals module: kopieer de bron naar de gewenste module directory
      aadModules = pkgs.stdenv.mkDerivation {
        name = "AADInternals-module";
        src = aadinternals;
        buildCommand = ''
          mkdir -p $out/share/powershell/Modules/AADInternals
          cp -r ${aadinternals}/* $out/share/powershell/Modules/AADInternals
        '';
      };

      # MFASweep module: kopieer MFASweep.ps1 en maak een geldige manifest
      mfaModule = pkgs.stdenv.mkDerivation {
        name = "MFASweep-module";
        src = mfasweep;
        buildCommand = ''
                  mkdir -p $out/share/powershell/Modules/MFASweep
                  cp ${mfasweep}/MFASweep.ps1 $out/share/powershell/Modules/MFASweep/MFASweep.psm1
                  cat > $out/share/powershell/Modules/MFASweep/MFASweep.psd1 <<EOF
          @{
            ModuleVersion = '1.0'
            RootModule    = 'MFASweep.psm1'
          }
          EOF
        '';
      };

      # O365spray als Python applicatie
      o365sprayPkg = pkgs.python3Packages.buildPythonApplication {
        name = "o365spray";
        src = o365spray;
        pyproject = true;
        build-system = [ pkgs.python3Packages.setuptools ];
        propagatedBuildInputs = with pkgs.python3Packages; [
          beautifulsoup4
          colorama
          lxml
          requests
        ];
      };
    in
    {
      devShell.${system} = pkgs.mkShell {
        buildInputs = [
          pkgs.python3 # Python > 3.7
          pkgs.powershell # PowerShell 7
          pkgs.azure-cli # Azure CLI
          azModules # Azure PowerShell modules
          aadModules # AADInternals module
          mfaModule # MFASweep module
          o365sprayPkg # O365spray (Python app)
        ];
        shellHook = ''
          # Zorg dat de custom PowerShell modules zichtbaar zijn
          export PSModulePath="$PSModulePath:${azModules}/share/powershell/Modules:${aadModules}/share/powershell/Modules:${mfaModule}/share/powershell/Modules"
          echo "Installing Microsoft Graph PowerShell modules..."
          pwsh -NoProfile -Command "Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force"
          echo "Dev environment is ready. Gebruik 'pwsh' voor PowerShell of 'az' voor Azure CLI."
        '';
      };

      packages.${system}.azureToolset = pkgs.buildEnv {
        name = "azure-toolset";
        paths = [
          pkgs.python3
          pkgs.powershell
          pkgs.azure-cli
          azModules
          aadModules
          mfaModule
          o365sprayPkg
        ];
      };
    };
}
