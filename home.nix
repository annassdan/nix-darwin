{ config, pkgs, lib, ... }:

let
  homeDir = config.home.homeDirectory;

  nodejs = pkgs.nodejs_24;
  # Make pnpm itself run on node 24 too (instead of nixpkgs' default node).
  # nixpkgs wants nodejs-slim here, not nodejs — overriding nodejs prints
  # "pnpm: Override nodejs-slim instead of nodejs".
  pnpm = pkgs.pnpm.override { nodejs-slim = pkgs.nodejs-slim_24; };

  # Repos cloned into $HOME on the first rebuild.
  # An existing folder is left alone — change the branch here and the clone
  # will NOT move; check out the new branch yourself in that case.
  # mkdirs: folders created inside the clone, only right after a fresh clone.
  repos = [
    {
      url = "https://github.com/bytebase/bytebase.git";
      dest = "${homeDir}/bytebase";
      branch = "release/3.22.1";
      mkdirs = [ "bytebase-build" ];
    }
  ];
in
{
  imports = [
    ./services.nix
    ./gpg.nix
  ];

  home.stateVersion = "25.11";

  home.packages = [
    nodejs
    pnpm
    pkgs.go
    pkgs.gopls        # Go language server (editor autocomplete / diagnostics)
    pkgs.rustc
    pkgs.cargo
    pkgs.rust-analyzer # Rust language server (editor autocomplete / diagnostics)
    pkgs.clippy
    pkgs.rustfmt
    pkgs.ripgrep
    pkgs.fzf
    pkgs.jq
    pkgs.typst
    pkgs.uv           # Python package/project manager (also installs Python versions)
  ];

  # ---- The important part for pnpm/npm ----
  # Nix-installed node lives in /nix/store, which is READ-ONLY.
  # So every "global" write must go to your home directory instead.
  home.sessionVariables = {
    PNPM_HOME = "${homeDir}/Library/pnpm";           # pnpm add -g, pnpm version switching
    NPM_CONFIG_PREFIX = "${homeDir}/.npm-global";     # npm install -g

    # Same idea for Go: `go install` writes binaries here, not into /nix/store
    GOPATH = "${homeDir}/go";
    GOBIN = "${homeDir}/go/bin";
  };

  home.sessionPath = [
    "${homeDir}/Library/pnpm"
    "${homeDir}/Library/pnpm/bin"   # pnpm 11 puts global binaries here
    "${homeDir}/.npm-global/bin"
    "${homeDir}/go/bin"
    "${homeDir}/.cargo/bin"   # `cargo install` writes binaries here, not into /nix/store
    "${homeDir}/.local/bin"   # `uv tool install` writes binaries here
    "/opt/homebrew/bin"       # brew itself + CLI casks (codex, claude-code)
  ];

  programs.zsh.enable = true;
  # Vite+ (`vp`, installed by the activation step below). Its env file puts
  # ~/.vite-plus/bin first and ~/.vite-plus/fallback-bin last on PATH.
  # .zshenv so every zsh (and IDEs/GUI apps that read the shell env) gets it;
  # .zshrc again so tab completion loads after compinit. Safe to source twice.
  programs.zsh.envExtra = ''
    [ -f "${homeDir}/.vite-plus/env" ] && . "${homeDir}/.vite-plus/env"
  '';
  programs.zsh.initContent = ''
    [ -f "${homeDir}/.vite-plus/env" ] && . "${homeDir}/.vite-plus/env"
  '';

  # Auto-load per-project flake dev shells when you cd into a folder
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.git = {
    enable = true;
    # Newer home-manager option names. On older versions these were
    # programs.git.userName / userEmail (still accepted, but warns).
    # settings.user.name = "DAN";
    # settings.user.email = "you@integer.id";
  };

  programs.home-manager.enable = true;

  # Clone repos listed above, once. Existing folders are skipped, so this never
  # touches work in progress. HTTPS on purpose: SSH would wait on the YubiKey
  # during activation and hang the rebuild.
  home.activation.cloneRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    lib.concatMapStrings (r: ''
      if [ -e "${r.dest}" ]; then
        echo "skipping ${r.dest} (already exists)"
      else
        echo "cloning ${r.url} (${r.branch}) -> ${r.dest}"
        if ${pkgs.git}/bin/git clone --branch "${r.branch}" "${r.url}" "${r.dest}"; then
          ${lib.concatMapStrings (d: ''
            mkdir -p "${r.dest}/${d}"
          '') (r.mkdirs or [ ])}
        else
          echo "clone failed for ${r.url}, continuing"
        fi
      fi
    '') repos
  );

  # Install Vite+ (`vp`) once, same as `curl -fsSL https://vite.plus | bash`.
  # Not in nixpkgs, so it lives outside the store in ~/.vite-plus. Skipped when
  # already installed; update it with `vp upgrade`, not by rebuilding.
  #  - CI=1 / VP_NODE_MANAGER=no: no prompts (activation has no terminal), and
  #    keep using the Nix node instead of letting Vite+ manage node.
  #  - VP_SELF_SETUP_NO_MODIFY_PATH=1: don't edit ~/.zshrc (it's a read-only
  #    Nix symlink); the env file is sourced in programs.zsh above.
  #  - `vp env off pnpm` (every rebuild): the `pnpm` shim in ~/.vite-plus/bin
  #    hands off to the Nix pnpm above instead of downloading its own.
  home.activation.installVitePlus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -x "${homeDir}/.vite-plus/bin/vp" ]; then
      echo "skipping Vite+ (already installed)"
    else
      echo "installing Vite+ -> ${homeDir}/.vite-plus"
      if ! PATH="${lib.makeBinPath [ pkgs.curl pkgs.gnutar pkgs.gzip pkgs.bash nodejs ]}:$PATH:/usr/bin:/bin" \
        CI=1 VP_NODE_MANAGER=no VP_SELF_SETUP_NO_MODIFY_PATH=1 VP_HOME="${homeDir}/.vite-plus" \
        ${pkgs.bash}/bin/bash -c "${pkgs.curl}/bin/curl -fsSL https://vite.plus | bash"; then
        echo "Vite+ install failed, continuing"
      fi
    fi
    if [ -x "${homeDir}/.vite-plus/bin/vp" ]; then
      PATH="${lib.makeBinPath [ pnpm nodejs ]}:$PATH" VP_HOME="${homeDir}/.vite-plus" \
        "${homeDir}/.vite-plus/bin/vp" env off pnpm || echo "vp env off pnpm failed, continuing"
    fi
  '';
}
