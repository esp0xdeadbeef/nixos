{ inputs
, lib
, pkgs
,
}:

let
  packageSet = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  isRunnablePackage = _name: package:
    lib.isDerivation package
    && package ? meta
    && package.meta ? mainProgram;

  emptyPersistence = {
    directories = [ ];
    files = [ ];
  };

  hermesPersistence = {
    directories = [
      ".hermes"
    ];
    files = [ ];
  };
in
rec {
  inherit packageSet;

  runnablePackages = lib.filterAttrs isRunnablePackage packageSet;
  runnablePackageNames = lib.attrNames runnablePackages;

  defaultPackageNames = [
    "codex"
    "hermes-agent"
    "hermes-desktop"
    "hermes-hud"
  ];

  explicitPersistencePackageNames = [
    "agent-browser"
    "agent-deck"
    "agentsview"
    "aionui"
    "amp"
    "annot"
    "antigravity"
    "antigravity-cli"
    "aperant"
    "apm"
    "auto-claude"
    "backlog-md"
    "beads"
    "beads-rust"
    "beads-viewer"
    "bernstein"
    "bun2nix"
    "but"
    "catnip"
    "cc-sdd"
    "cc-switch-cli"
    "ccstatusline"
    "ccusage"
    "chainlink"
    "ck"
    "claude-agent-acp"
    "claude-code"
    "claude-code-router"
    "claude-plugins"
    "claudebox"
    "claw-code"
    "cli-proxy-api"
    "code"
    "code-review-graph"
    "codegraph"
    "coderabbit-cli"
    "codex"
    "codex-acp"
    "codex-auth"
    "context-hub"
    "copilot-cli"
    "copilot-language-server"
    "crush"
    "cubic"
    "cursor-agent"
    "default"
    "dolt"
    "droid"
    "eca"
    "entire"
    "fence"
    "forge"
    "forgecode"
    "formatter"
    "gascity"
    "gastown"
    "gemini-cli"
    "git-surgeon"
    "gitbutler"
    "gitclaw"
    "gitnexus"
    "gnhf"
    "gno"
    "goose-cli"
    "grok"
    "handy"
    "happy-coder"
    "herdr"
    "hermes-agent"
    "hermes-desktop"
    "hermes-hud"
    "hunk"
    "icm"
    "iflow-cli"
    "jules"
    "junie"
    "kilocode-cli"
    "lean-ctx"
    "letta-code"
    "localgpt"
    "mardi-gras"
    "mcporter"
    "memvid-cli"
    "mimo-code"
    "mistral-vibe"
    "nanocoder"
    "nono"
    "officecli"
    "oh-my-claudecode"
    "oh-my-codex"
    "oh-my-opencode"
    "omp"
    "openclaw"
    "opencode"
    "openfang"
    "openskills"
    "openspec"
    "openspecui"
    "parallel-cli"
    "paseo-desktop"
    "pi"
    "picoclaw"
    "qmd"
    "qoder-cli"
    "qwen-code"
    "ralph-tui"
    "reasonix"
    "rtk"
    "sandbox-runtime"
    "semble"
    "showboat"
    "sidecar"
    "skills"
    "skills-installer"
    "spec-kit"
    "td"
    "toon"
    "tuicr"
    "vessel-browser"
    "vibe-kanban"
    "vix"
    "voxterm"
    "voxtype"
    "workmux"
    "zat"
    "zeroclaw"
  ];

  knownPersistenceByPackageName = {
    agent-deck = {
      directories = [
        ".agent-deck"
        ".config/agent-deck"
        ".local/share/agent-deck"
      ];
      files = [ ];
    };

    amp = {
      directories = [
        ".config/amp"
        ".local/share/amp"
      ];
      files = [ ];
    };

    antigravity = {
      directories = [
        ".gemini"
      ];
      files = [ ];
    };
    antigravity-cli = {
      directories = [
        ".gemini"
      ];
      files = [ ];
    };

    apm = {
      directories = [
        ".apm"
      ];
      files = [ ];
    };

    but = {
      directories = [
        ".config/gitbutler"
      ];
      files = [ ];
    };

    catnip = {
      directories = [
        ".catnip"
      ];
      files = [ ];
    };

    cc-switch-cli = {
      directories = [
        ".cc-switch"
      ];
      files = [ ];
    };

    claude-code = {
      directories = [
        ".claude"
        ".config/anthropic"
      ];
      files = [
        ".claude.json"
      ];
    };

    claudebox = {
      directories = [
        ".claude"
      ];
      files = [
        ".claude.json"
      ];
    };

    claw-code = {
      directories = [
        ".claw"
      ];
      files = [
        ".claw.json"
      ];
    };

    code = {
      directories = [
        ".code"
      ];
      files = [ ];
    };

    coderabbit-cli = {
      directories = [
        ".coderabbit"
      ];
      files = [ ];
    };

    codex = {
      directories = [
        ".codex"
      ];
      files = [ ];
    };

    codex-auth = {
      directories = [
        ".codex"
      ];
      files = [ ];
    };

    crush = {
      directories = [
        ".config/crush"
        ".local/share/crush"
      ];
      files = [ ];
    };

    cursor-agent = {
      directories = [
        ".cursor"
      ];
      files = [ ];
    };

    dolt = {
      directories = [
        ".dolt"
      ];
      files = [ ];
    };

    droid = {
      directories = [
        ".factory"
      ];
      files = [ ];
    };

    entire = {
      directories = [
        ".config/entire"
      ];
      files = [ ];
    };

    forge = {
      directories = [
        ".forge"
      ];
      files = [ ];
    };
    forgecode = {
      directories = [
        ".forge"
      ];
      files = [ ];
    };

    gitclaw = emptyPersistence;
    gnhf = {
      directories = [
        ".gnhf"
      ];
      files = [ ];
    };
    goose-cli = {
      directories = [
        ".local/share/goose"
        ".local/state/goose"
      ];
      files = [ ];
    };
    grok = {
      directories = [
        ".grok"
      ];
      files = [ ];
    };
    happy-coder = {
      directories = [
        ".happy"
      ];
      files = [ ];
    };
    herdr = {
      directories = [
        ".config/herdr"
        ".local/state/herdr"
      ];
      files = [ ];
    };
    hermes-agent = hermesPersistence;
    hermes-desktop = hermesPersistence;
    hermes-hud = hermesPersistence;
    jules = {
      directories = [
        ".jules"
      ];
      files = [ ];
    };
    kilocode-cli = {
      directories = [
        ".config/kilo"
        ".local/share/kilo"
        ".local/state/kilo"
      ];
      files = [ ];
    };
    mimo-code = {
      directories = [
        ".config/mimocode"
        ".local/share/mimocode"
        ".local/state/mimocode"
      ];
      files = [ ];
    };
    mistral-vibe = {
      directories = [
        ".vibe"
      ];
      files = [ ];
    };
    nanocoder = emptyPersistence;
    officecli = {
      directories = [
        ".officecli"
      ];
      files = [ ];
    };
    oh-my-claudecode = {
      directories = [
        ".claude"
      ];
      files = [
        ".claude.json"
      ];
    };
    oh-my-codex = {
      directories = [
        ".codex"
      ];
      files = [ ];
    };
    oh-my-opencode = {
      directories = [
        ".config/opencode"
        ".local/share/opencode"
        ".local/state/opencode"
      ];
      files = [ ];
    };
    omp = {
      directories = [
        ".omp"
      ];
      files = [ ];
    };
    openclaw = {
      directories = [
        ".openclaw"
        ".clawdbot"
      ];
      files = [ ];
    };
    opencode = {
      directories = [
        ".config/opencode"
        ".cache/opencode"
        ".local/share/opencode"
        ".local/state/opencode"
      ];
      files = [ ];
    };
    openfang = {
      directories = [
        ".openfang"
      ];
      files = [ ];
    };
    openspecui = {
      directories = [
        ".config/openspec"
      ];
      files = [ ];
    };
    parallel-cli = {
      directories = [
        ".config/parallel-web-tools"
      ];
      files = [ ];
    };
    pi = {
      directories = [
        ".pi"
      ];
      files = [ ];
    };
    picoclaw = emptyPersistence;
    qoder-cli = {
      directories = [
        ".qoder"
      ];
      files = [ ];
    };
    qwen-code = {
      directories = [
        ".qwen"
      ];
      files = [ ];
    };
    reasonix = {
      directories = [
        ".reasonix"
        ".config/reasonix"
      ];
      files = [ ];
    };
    rtk = {
      directories = [
        ".local/share/rtk"
      ];
      files = [ ];
    };
    sidecar = {
      directories = [
        ".config/td"
        ".local/state/sidecar"
      ];
      files = [ ];
    };
    td = {
      directories = [
        ".config/td"
      ];
      files = [ ];
    };
    vessel-browser = {
      directories = [
        ".config/vessel-browser"
      ];
      files = [ ];
    };
    vibe-kanban = {
      directories = [
        ".local/share/vibe-kanban"
      ];
      files = [ ];
    };
    vix = {
      directories = [
        ".vix"
      ];
      files = [ ];
    };
    voxterm = {
      directories = [
        ".local/share/voxterm"
      ];
      files = [ ];
    };
    voxtype = {
      directories = [
        ".config/voxtype"
        ".local/share/voxtype"
      ];
      files = [ ];
    };
    workmux = {
      directories = [
        ".local/state/workmux"
      ];
      files = [ ];
    };
    zeroclaw = {
      directories = [
        ".zeroclaw"
        ".config/zeroclaw"
      ];
      files = [ ];
    };
  };

  persistenceByPackageName =
    (lib.genAttrs explicitPersistencePackageNames (_name: emptyPersistence))
    // knownPersistenceByPackageName;
}
