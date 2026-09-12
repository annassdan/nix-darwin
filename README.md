# nix-darwin config for my MacBook

My whole Mac setup, declared with **nix-darwin** and **home-manager** in one flake.

## What's inside

| File | What it does |
|---|---|
| `flake.nix` | Entry point. Wires nix-darwin and home-manager together. Set `user` and `hostname` here. |
| `darwin.nix` | System level: macOS settings, trackpad, Touch ID for sudo, system packages. |
| `home.nix` | User level: Node 24, pnpm, direnv, git, zsh, and pnpm/npm global paths. |
| `services.nix` | Background services: PostgreSQL on `5432` (with PostGIS), PostgreSQL on `54322`, Redis on `6379`. |
| `gpg.nix` | GPG with YubiKey, and gpg-agent used as the SSH agent. |

## Setup on a fresh Mac

### 1. Finish the macOS setup

Sign in, run any pending macOS updates, and restart. Then check your username:

```bash
whoami
```

### 2. Install the Xcode command line tools

This gives you `git`, which flakes need.

```bash
xcode-select --install
```

### 3. Install Nix (Determinate installer)

The config assumes this installer, which is why `darwin.nix` has `nix.enable = false`.

```bash
curl -fsSL https://install.determinate.systems/nix | sh -s -- install
```

Open a **new terminal** and check it works:

```bash
nix --version
```

> Using the official Nix installer instead? In `darwin.nix`, remove `nix.enable = false;` and add
> `nix.settings.experimental-features = [ "nix-command" "flakes" ];`

### 4. Install Homebrew

The GUI apps (Zed, Terax, Firefox, Dia, Yaak) come from Homebrew casks. nix-darwin runs `brew` for you during a rebuild, but it does **not** install Homebrew itself, so do that once by hand:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

It asks for your password, because it creates `/opt/homebrew`. After this you never need to type `brew install` yourself; the app list lives in `darwin.nix`.

Skip this only if you remove the `homebrew` block from `darwin.nix`.

### 5. Put the files in place

```bash
mkdir -p ~/.config/nix-darwin
# copy flake.nix, darwin.nix, home.nix, services.nix, gpg.nix (and this README) into it
```

### 6. Edit a few values

- **`flake.nix`**: set `user` to the output of `whoami`. You can keep `hostname = "dan-macbook"`; it's only a name for the config and doesn't have to match the Mac's real hostname, as long as you always use `#dan-macbook` in the commands.
- **`darwin.nix`**: on an **Intel** Mac, change `aarch64-darwin` to `x86_64-darwin`. Apple Silicon (M1/M2/M3/M4) needs no change.
- **`home.nix`** (optional): fill in git `userName` and `userEmail`.

### 7. Commit the files to git

Flakes only see files tracked by git. Skipping this causes "file not found" errors.

```bash
cd ~/.config/nix-darwin
git init && git add . && git commit -m "init"
```

### 8. First switch

This takes a while the first time because it downloads everything.

```bash
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ~/.config/nix-darwin#annas-macbook
```

### 9. Log out and back in (or restart)

This activates the trackpad settings and the GPG setup for GUI apps.

### 10. Check that everything works

Open a new terminal, plug in the YubiKey, and run:

```bash
node -v && pnpm -v && go version
echo $PNPM_HOME               # /Users/<you>/Library/pnpm
psql -c 'select version()'    # postgres on 5432 (with PostGIS)
psql -p 54322 -c 'select 1'   # postgres on 54322
redis-cli ping                # PONG
gpg --card-status             # shows the YubiKey
ssh-add -L                    # shows the key with cardno:...
```

### Don't do these

- Don't run `nix profile install` for anything. The config installs all of it.
- Don't manually edit `~/.zshrc` or `~/.gnupg/gpg-agent.conf`. Home-manager manages those files.
- Don't install Postgres, Redis, or Node from Homebrew or Postgres.app. They would fight over the same ports and commands.

## Daily use

After editing any file, apply the changes:

```bash
sudo darwin-rebuild switch --flake ~/.config/nix-darwin#dan-macbook
```

If you create a **new** `.nix` file, `git add` it first.

Update all packages to newer versions:

```bash
cd ~/.config/nix-darwin
nix flake update
sudo darwin-rebuild switch --flake .#dan-macbook
```

## Services

| Service | Port | Data | Log |
|---|---|---|---|
| PostgreSQL 17 + PostGIS | `5432` | `~/.local/share/dev-services/postgres-main-17` | `~/Library/Logs/postgres-main.log` |
| PostgreSQL 17 | `54322` | `~/.local/share/dev-services/postgres-alt-17` | `~/Library/Logs/postgres-alt.log` |
| Redis | `6379` | `~/.local/share/dev-services/redis` | `~/Library/Logs/redis.log` |

Both Postgres instances start once at login. After that, **you** control them with `pg_ctl` (launchd will not restart them after you stop them). Redis is always on and is restarted if it crashes.

**Postgres login:** user `postgres`, password `postgres`, on both instances. They listen on `127.0.0.1` only, so the password is a convenience rather than a secret; don't reuse this setup on a server. `psql` connects to `5432` by default; use `psql -p 54322` for the second instance.

`~/.pgpass` is written for you (mode 600, entries for both ports), so `psql` won't prompt. Connections over the unix socket are trusted, which is how the helper scripts get in. The rules live in a Nix-managed `pg_hba.conf`, not inside the data folder, so editing files in `~/.local/share/dev-services` has no effect; change `pgHba` in `services.nix` instead.

**Use `127.0.0.1`, not `localhost`.** Both servers bind to `127.0.0.1` only, and `PGHOST` is set to match. On macOS `localhost` can resolve to the IPv6 address `::1` first, which nothing is listening on, so a connection string using `localhost` may fail with "connection refused". Write `127.0.0.1` in `database.yml`, `.env` files, and `DATABASE_URL`.

To change the password, edit `pgPassword` in `services.nix` and rebuild. The next `pg-main start` applies it.

### Start and stop Postgres

Each instance has a helper command that wraps `pg_ctl` with the right data folder, port and log file:

```bash
pg-main start      # 5432 (PostGIS)
pg-main stop
pg-main restart
pg-main status
pg-main log        # follow the log
pg-main psql       # open psql on this instance

pg-alt start       # 54322, same subcommands
pg-alt stop
```

The first `start` creates the database cluster automatically.

Plain `pg_ctl` also works, because the port is stored in the data folder:

```bash
pg_ctl -D ~/.local/share/dev-services/postgres-main-17 status
pg_ctl -D ~/.local/share/dev-services/postgres-main-17 stop
```

For **starting** the 5432 instance, prefer `pg-main start`: it makes sure the PostGIS-enabled binary is used.

**Don't start an instance at login:** in `services.nix`, set `autoStart = false;` for it and rebuild. Then start it only when you need it with `pg-main start` / `pg-alt start`.

### Redis

Redis is managed by launchd, so you control it with `launchctl`:

```bash
# stop
launchctl bootout gui/$(id -u)/org.nix-community.home.redis

# start
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/org.nix-community.home.redis.plist

# restart
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.redis

# is it running?
redis-cli ping   # PONG = running
```

Don't use `redis-cli shutdown` to stop it. launchd would start Redis again right away, because it's set to restart when it stops.

Turn it off completely: set `enable = false;` for `redis` in `services.nix` and rebuild.

### After a restart or login

Everything starts again automatically. If you stop a service today, it will be running again after your next login (unless you set `autoStart = false;` for a Postgres instance, or `enable = false;` for Redis).

**Rails `database.yml`:**

```yaml
development:
  adapter: postgresql
  host: 127.0.0.1
  port: 5432        # or 54322
  username: postgres
  password: postgres
  database: myapp_development
```

### PostGIS

PostGIS is available on `5432` only, but each database must enable it once:

```bash
psql -d myapp_development -c 'CREATE EXTENSION postgis;'
```

In Rails, use `enable_extension "postgis"` in a migration (or the `activerecord-postgis-adapter` gem).

To have PostGIS in **every new** database on `5432` automatically:

```bash
psql -d template1 -c 'CREATE EXTENSION postgis;'
```

After a `nix flake update` brings a newer PostGIS, run `ALTER EXTENSION postgis UPDATE;` in each database that uses it.

### Upgrading Postgres

The data folder name includes the major version (e.g. `postgres-main-17`). Changing to `postgresql_18` starts a fresh, empty database instead of crashing; the old data stays in the old folder so you can dump it or use `pg_upgrade`.

### Port 54322 and Supabase

`54322` is also the port the Supabase CLI uses for its local database. Stop `postgres-alt` (or change its port) before running `supabase start`.

## Node and pnpm

Node 24 and pnpm come from Nix, and pnpm itself runs on Node 24.

Nix packages live in `/nix/store`, which is **read-only**, so global installs are redirected to your home folder:

- `pnpm add -g ...` installs into `~/Library/pnpm` (`PNPM_HOME`)
- `npm install -g ...` installs into `~/.npm-global` (`NPM_CONFIG_PREFIX`)

If a project has a `"packageManager": "pnpm@..."` field, pnpm can download and switch to that version by itself.

Avoid these:

- `corepack enable` (writes into the read-only Node folder)
- `pnpm self-update` (update pnpm with `nix flake update` instead)
- `sudo npm install -g ...`

## Go

Go and `gopls` (the language server, for editor autocomplete) come from Nix.

For the same read-only reason as pnpm, `go install` is pointed at your home folder:

- `GOPATH` = `~/go`
- `GOBIN` = `~/go/bin`, which is on your `PATH`

So `go install github.com/some/tool@latest` puts the binary in `~/go/bin` and it's immediately runnable.

To pin a different Go version per project, use a `flake.nix` dev shell instead of changing this global one.

## GUI apps

Installed as Homebrew casks, listed in `darwin.nix`:

| App | Cask |
|---|---|
| Zed | `zed` |
| Terax | `terax` |
| Firefox | `firefox` |
| Dia | `thebrowsercompany-dia` |
| Yaak | `yaak` |

They're installed on the next rebuild; no `.dmg` files needed, and the apps keep their own auto-update.

**Add an app:** find its cask name at [formulae.brew.sh/cask](https://formulae.brew.sh/cask/), add it to the `casks` list, and rebuild. To check a name first: `brew search --cask <name>`.

**Remove an app:** delete it from the list and rebuild. Because `cleanup = "zap"` is set, anything not in the list gets removed, so keep the list complete.

### The `cleanup` option

`onActivation.cleanup` in `darwin.nix` decides what happens to casks that are **not** in the list:

| Value | What it does |
|---|---|
| `"zap"` | Uninstalls them, **and** deletes their settings and leftover files. This is what's set here, so the list stays the single source of truth. |
| `"uninstall"` | Uninstalls them, but leaves their settings behind, so reinstalling later keeps your config. |
| `"none"` | Leaves them alone. Nothing is removed automatically. |

With `"zap"` or `"uninstall"`, an app you install by hand with `brew install --cask` disappears on the next rebuild. Add it to the `casks` list instead, or switch to `"none"`.

This only affects apps **Homebrew** installed. Homebrew keeps a record of those. An app you downloaded as a `.dmg` and dragged to Applications yourself isn't in that record, so it's never touched.

If an app isn't in Homebrew at all, install it from its `.dmg` by hand and the config will leave it alone.

## Dock

Set in `darwin.nix`:

- Auto-hide, with no delay and a fast animation
- Recent apps are not added to the Dock

Remove or change any of the `system.defaults.dock.*` lines if you prefer the Dock always visible.

## Trackpad

Set in `darwin.nix`:

- Tap to click
- Two-finger tap for right click
- Three-finger drag (drag windows by the title bar, select text, move files)

These may only take effect after logging out and back in.

If three-finger swipes (switching desktops, Mission Control) act strangely, go to **System Settings → Trackpad → More Gestures** and set those swipes to four fingers.

Optional: to drag a window from **anywhere** inside it with Ctrl+Cmd, add to `darwin.nix`:

```nix
system.defaults.CustomUserPreferences.NSGlobalDomain.NSWindowShouldDragOnGesture = true;
```

## GPG and YubiKey

`gpg.nix` sets up:

- `gnupg`, `pinentry-mac` (PIN popup) and `ykman`
- gpg-agent with SSH support, used as the SSH agent in every terminal
- a login agent that also makes GUI apps (VS Code, git GUIs) use gpg-agent for SSH

Useful YubiKey commands:

```bash
ykman list            # is the YubiKey detected?
ykman openpgp info    # OpenPGP app status
gpg --card-status     # gpg reads the card
ssh-add -L            # SSH public key from the card
```

**"No such device" or "card not available" from `gpg --card-status`:** this is a common macOS driver clash. Add to `gpg.nix`:

```nix
programs.gpg.scdaemonSettings.disable-ccid = true;
```

Then rebuild, run `gpgconf --kill scdaemon`, and try again.

## Troubleshooting

- **`nix: command not found` after a big macOS update.** macOS sometimes resets `/etc/zshrc` and removes the Nix lines. Re-running the Determinate installer usually repairs it.
- **"file not found" during a rebuild.** A new file isn't tracked by git yet. Run `git add <file>`.
- **A home-manager file already exists.** Home-manager owns files like `~/.zshrc` and `~/.gnupg/gpg-agent.conf`, and replaces them with symlinks into the Nix store. Because `backupFileExtension = "hm-backup"` is set in `flake.nix`, an existing file is renamed (`~/.zshrc` → `~/.zshrc.hm-backup`) instead of failing the rebuild. Open the backup, move anything you want to keep into `home.nix` (not back into `~/.zshrc`, which gets overwritten on every rebuild), then delete the backup. Only **one** backup per file is kept, so a later rebuild fails if a `.hm-backup` is still sitting there.
- **A service doesn't start.** Check its log in `~/Library/Logs/` (or run `pg-main log`). The most common cause is another program already using the port (`lsof -i :5432`).
- **Something looks different from a tutorial.** nix-darwin and home-manager change over time. Check the [nix-darwin README](https://github.com/nix-darwin/nix-darwin) and the [home-manager manual](https://nix-community.github.io/home-manager/).
