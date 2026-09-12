{ pkgs, self, user, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin"; # Apple Silicon. Use "x86_64-darwin" for Intel Macs.
  nixpkgs.config.allowUnfree = true;

  # The Determinate installer manages the Nix daemon itself,
  # so nix-darwin must not manage it too (otherwise they fight).
  # If you used the OFFICIAL installer instead, delete this line and add:
  #   nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.enable = false;

  system.primaryUser = user;
  users.users.${user}.home = "/Users/${user}";

  programs.zsh.enable = true;

  # Minimal system-wide tools. Put your personal tools in home.nix instead.
  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  # GUI apps, through Homebrew casks (managed by nix-darwin).
  # Homebrew itself must be installed once, see the README.
  homebrew = {
    enable = true;

    # Apps listed here are installed. Removing one from the list uninstalls it
    # (because of the "zap" cleanup below), so keep this list complete.
    casks = [
      "zed"                     # code editor
      "terax"                   # AI-native terminal / dev workspace
      "firefox"                 # browser
      "thebrowsercompany-dia"   # Dia browser
      "yaak"                    # REST / GraphQL / gRPC client
    ];

    # brews = [ ];              # CLI tools that aren't in nixpkgs
    # masApps = { };            # Mac App Store apps, e.g. { Xcode = 497799835; }

    onActivation = {
      autoUpdate = true;   # refresh the cask list on every rebuild
      upgrade = true;      # upgrade installed casks on every rebuild
      cleanup = "zap";     # remove casks that are no longer listed above
    };
  };

  # Use Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  # A few sane macOS defaults (optional, remove what you don't like)
  system.defaults.finder.AppleShowAllExtensions = true;
  system.defaults.NSGlobalDomain.KeyRepeat = 2;
  system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;

  # Dock
  system.defaults.dock.autohide = true;            # hide the Dock until you move the pointer to it
  system.defaults.dock.autohide-delay = 0.0;       # no pause before it appears
  system.defaults.dock.autohide-time-modifier = 0.2; # faster show/hide animation
  system.defaults.dock.show-recents = false;       # don't append recent apps to the Dock

  # Trackpad
  system.defaults.trackpad.Clicking = true;                     # tap to click
  system.defaults.NSGlobalDomain."com.apple.mouse.tapBehavior" = 1; # tap to click (also on login screen)
  system.defaults.trackpad.TrackpadRightClick = true;           # two-finger tap = right click
  system.defaults.trackpad.TrackpadThreeFingerDrag = true;      # three fingers to drag windows / selections

  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;
}
