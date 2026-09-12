{ config, pkgs, ... }:

let
  homeDir = config.home.homeDirectory;

  nodejs = pkgs.nodejs_24;
  # Make pnpm itself run on node 24 too (instead of nixpkgs' default node).
  # nixpkgs wants nodejs-slim here, not nodejs — overriding nodejs prints
  # "pnpm: Override nodejs-slim instead of nodejs".
  pnpm = pkgs.pnpm.override { nodejs-slim = pkgs.nodejs-slim_24; };
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
    pkgs.ripgrep
    pkgs.fzf
    pkgs.jq
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
  ];

  programs.zsh.enable = true;

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
}
