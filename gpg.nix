{ config, pkgs, ... }:

# GPG with YubiKey (OpenPGP), and gpg-agent used as your SSH agent.
# This is the same setup you did by hand before, but declared in Nix.

let
  gpgconf = "${config.programs.gpg.package}/bin/gpgconf";
in
{
  # Installs gnupg and creates ~/.gnupg with the correct 700 permissions
  programs.gpg.enable = true;

  # On macOS, the Nix build of gnupg links against nixpkgs' pcsclite, which
  # expects a pcscd daemon that doesn't exist here — scdaemon then fails with
  # "selecting card failed: Service is not running".
  # Point it at Apple's own PC/SC implementation instead.
  programs.gpg.scdaemonSettings = {
    disable-ccid = true;
    pcsc-driver = "/System/Library/Frameworks/PCSC.framework/Versions/Current/PCSC";
  };

  home.packages = [
    pkgs.pinentry_mac      # macOS popup for your YubiKey PIN
    pkgs.yubikey-manager   # ykman
  ];

  # ~/.gnupg/gpg-agent.conf
  # (points straight to the Nix store path, so it never breaks if your profile changes)
  home.file.".gnupg/gpg-agent.conf".text = ''
    enable-ssh-support
    pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac
  '';

  # Every terminal: use gpg-agent as the SSH agent
  programs.zsh.initContent = ''
    # Use gpg-agent as SSH agent (YubiKey OpenPGP)
    export GPG_TTY=$(tty)
    export SSH_AUTH_SOCK=$(${gpgconf} --list-dirs agent-ssh-socket)
    ${gpgconf} --launch gpg-agent
  '';

  # At login: start gpg-agent and tell GUI apps (VS Code, git GUIs, ...)
  # to use it for SSH too, not only terminals.
  launchd.agents.gpg-agent-ssh = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "${gpgconf} --launch gpg-agent && /bin/launchctl setenv SSH_AUTH_SOCK \"$(${gpgconf} --list-dirs agent-ssh-socket)\""
      ];
      RunAtLoad = true;
      AbandonProcessGroup = true; # keep gpg-agent running after this script exits
    };
  };
}
