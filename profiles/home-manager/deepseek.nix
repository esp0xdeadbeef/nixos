{ config, lib, ... }:
let
  apiKeyPath = "${config.home.homeDirectory}/.config/sops-nix/secrets/deepseek-api";
  xfieldApiKeyPath = "${config.home.homeDirectory}/.config/sops-nix/secrets/xfield-api";
in
{
  sops.secrets."deepseek-api" = { };
  sops.secrets."xfield-api" = { };

  home.sessionVariables = {
    OPENAI_BASE_URL = "https://api.deepseek.com/v1";
  };

  # Pi model configuration: built-in providers plus the xfield OpenAI-compatible
  # endpoint. Pi never writes this file at runtime (its own state lives in
  # models-store.json), so linking it to the flake store keeps it reproducible.
  home.file.".pi/agent/models.json".source = ./pi-models.json;

  home.file.".zshenv".text = ''
    # Add user bin to PATH for wrappers (e.g. claude)
    case ":$PATH:" in
      *:"$HOME/.local/bin":*) ;;
      *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac

    # Source home-manager session variables (OPENAI_BASE_URL etc.)
    if [ -f "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
      . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
    fi

    if [ -f ${apiKeyPath} ]; then
      export DEEPSEEK_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
    if [ -f ${xfieldApiKeyPath} ]; then
      export XFIELD_API_KEY="$(tr -d '\r\n' < ${xfieldApiKeyPath})"
    fi
  '';
  home.file.".profile".text = ''
    # Add user bin to PATH for wrappers (e.g. claude)
    case ":$PATH:" in
      *:"$HOME/.local/bin":*) ;;
      *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac

    # Source home-manager session variables (OPENAI_BASE_URL etc.)
    if [ -f "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
      . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
    fi

    if [ -f ${apiKeyPath} ]; then
      export DEEPSEEK_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
    if [ -f ${xfieldApiKeyPath} ]; then
      export XFIELD_API_KEY="$(tr -d '\r\n' < ${xfieldApiKeyPath})"
    fi
  '';

  home.file.".config/fish/conf.d/deepseek-api.fish".text = ''
    set -gx OPENAI_BASE_URL "https://api.deepseek.com/v1"

    if test -f ${apiKeyPath}
      set -gx DEEPSEEK_API_KEY (tr -d '\r\n' < ${apiKeyPath})
    end

    if test -f ${xfieldApiKeyPath}
      set -gx XFIELD_API_KEY (tr -d '\r\n' < ${xfieldApiKeyPath})
    end
  '';
}
