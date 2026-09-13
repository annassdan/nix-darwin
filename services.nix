{ config, pkgs, lib, ... }:

# Dev database services.
#
# PostgreSQL is controlled with pg_ctl, through two helper commands:
#   pg-main start | stop | restart | status | log | psql     (port 5432, with PostGIS)
#   pg-alt  start | stop | restart | status | log | psql     (port 54322)
# With autoStart = true, the instance is also started once at login.
# (launchd only starts it; it does NOT restart it after you stop it.)
#
# Redis runs as a launchd agent (always on, restarted if it crashes).
#
# Data lives in ~/.local/share/dev-services, logs in ~/Library/Logs.

let
  homeDir = config.home.homeDirectory;
  dataRoot = "${homeDir}/.local/share/dev-services";

  # Dev password for the "postgres" role. Same on both instances.
  # Localhost-only, so this is a convenience, not a secret.
  pgPassword = "postgres";

  # Who may connect, managed by Nix (not edited inside the data dir).
  # - unix socket: trust, so the helper scripts can always get in
  # - TCP from 127.0.0.1: password required
  pgHba = pkgs.writeText "pg_hba.conf" ''
    local   all   all                  trust
    host    all   all   127.0.0.1/32   scram-sha-256
  '';

  # base       = plain postgres package, e.g. pkgs.postgresql_17
  # extensions = which extensions to make available, e.g. (ps: [ ps.postgis ])
  # autoStart  = start this instance at login
  mkPostgres = { name, port, base, extensions ? (_: [ ]), autoStart ? true }:
    let
      package = base.withPackages extensions;
      major = lib.versions.major base.version;
      # Version in the folder name: upgrading 17 -> 18 creates a NEW data dir
      # instead of crashing on an incompatible one. The old one stays for pg_upgrade/dump.
      dataDir = "${dataRoot}/postgres-${name}-${major}";
      logFile = "${homeDir}/Library/Logs/postgres-${name}.log";
      cmd = "pg-${name}";

      script = pkgs.writeShellScriptBin cmd ''
        set -euo pipefail
        PGDATA="${dataDir}"
        BIN="${package}/bin"

        prepare() {
          if [ ! -f "$PGDATA/PG_VERSION" ]; then
            echo "Creating new database cluster in $PGDATA"
            mkdir -p "$PGDATA"
            "$BIN/initdb" \
              --pgdata="$PGDATA" \
              --username=postgres \
              --auth=trust \
              --encoding=UTF8 \
              --locale=C
            echo "include_if_exists = 'nix.conf'" >> "$PGDATA/postgresql.conf"
          fi
          # Settings from Nix, rewritten on every start so they always match this config.
          # Because they live in the data dir, plain `pg_ctl -D <dir> start` also uses the right port.
          printf '%s\n' \
            "port = ${toString port}" \
            "listen_addresses = '127.0.0.1'" \
            "unix_socket_directories = '/tmp'" \
            "hba_file = '${pgHba}'" \
            > "$PGDATA/nix.conf"
        }

        is_running() {
          "$BIN/pg_ctl" -D "$PGDATA" status > /dev/null 2>&1
        }

        start() {
          if is_running; then
            echo "${cmd} is already running (port ${toString port})"
            return 0
          fi
          prepare
          # -p makes sure the PostGIS-enabled postgres binary is used
          "$BIN/pg_ctl" -D "$PGDATA" -p "$BIN/postgres" -l "${logFile}" start
          # Keep the dev password in sync with this config. Idempotent, and it also
          # fixes clusters created before the password was introduced.
          # Goes over the unix socket (/tmp), which pg_hba trusts.
          "$BIN/psql" -q -h /tmp -p ${toString port} -U postgres -d postgres \
            -c "ALTER USER postgres PASSWORD '${pgPassword}';" > /dev/null
        }

        stop() {
          if ! is_running; then
            echo "${cmd} is not running"
            return 0
          fi
          "$BIN/pg_ctl" -D "$PGDATA" stop
        }

        case "''${1:-}" in
          start)   start ;;
          stop)    stop ;;
          restart) stop; start ;;
          status)  "$BIN/pg_ctl" -D "$PGDATA" status || true ;;
          log)     tail -f "${logFile}" ;;
          psql)    shift; exec "$BIN/psql" -h 127.0.0.1 -p ${toString port} -U postgres "$@" ;;
          *)
            echo "usage: ${cmd} {start|stop|restart|status|log|psql}"
            echo "data: $PGDATA"
            exit 1
            ;;
        esac
      '';
    in
    {
      inherit package script;
      agent = {
        enable = autoStart;
        config = {
          ProgramArguments = [ "${script}/bin/${cmd}" "start" ];
          RunAtLoad = true;
          AbandonProcessGroup = true; # keep postgres running after this start script exits
          StandardOutPath = logFile;
          StandardErrorPath = logFile;
        };
      };
    };

  # 5432: with PostGIS available
  pgMain = mkPostgres {
    name = "main";
    port = 5432;
    base = pkgs.postgresql_17;
    extensions = ps: [ ps.postgis ];
  };

  # 54322: plain postgres. You can use a different version here, e.g. pkgs.postgresql_16
  pgAlt = mkPostgres {
    name = "alt";
    port = 54322;
    base = pkgs.postgresql_17;
    # autoStart = false;   # uncomment to only start it manually with: pg-alt start
  };

  redisStart = pkgs.writeShellScript "redis-start" ''
    set -euo pipefail
    mkdir -p "${dataRoot}/redis"
    exec ${pkgs.redis}/bin/redis-server \
      --port 6379 \
      --bind 127.0.0.1 ::1 \
      --dir "${dataRoot}/redis"
  '';
in
{
  launchd.agents = {
    postgres-main = pgMain.agent;
    postgres-alt = pgAlt.agent;

    redis = {
      enable = true;
      config = {
        ProgramArguments = [ "${redisStart}" ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${homeDir}/Library/Logs/redis.log";
        StandardErrorPath = "${homeDir}/Library/Logs/redis.log";
      };
    };
  };

  home.packages = [
    pgMain.package   # psql, pg_ctl, pg_dump, shp2pgsql (PostGIS) ... from the 5432 instance
    pgMain.script    # pg-main
    pgAlt.script     # pg-alt
    pkgs.redis       # redis-cli
  ];

  # So plain `psql` connects over TCP as the postgres user.
  # For the second instance: psql -p 54322  (or: pg-alt psql)
  home.sessionVariables = {
    PGHOST = "127.0.0.1";
    PGUSER = "postgres";

    # Ready-made connection URLs. No database name, so append one:
    #   psql "$PG_URL/myapp_development"
    #   DATABASE_URL="$PG_URL/myapp_development" rails db:migrate
    PG_URL = "postgresql://postgres:${pgPassword}@127.0.0.1:5432";
    PG_ALT_URL = "postgresql://postgres:${pgPassword}@127.0.0.1:54322";
    REDIS_URL = "redis://127.0.0.1:6379";
  };

  # ~/.pgpass so psql and other libpq tools don't prompt for the dev password.
  # Written by a script (not a symlink) because libpq ignores the file unless
  # it is mode 0600, and Nix store files are world-readable.
  # Existing entries for other hosts are kept.
  home.activation.pgpass = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    pgpass="${homeDir}/.pgpass"
    touch "$pgpass"
    grep -v -E '^(127\.0\.0\.1|localhost):(5432|54322):\*:postgres:' "$pgpass" > "$pgpass.tmp" || true
    printf '%s\n' \
      "127.0.0.1:5432:*:postgres:${pgPassword}" \
      "127.0.0.1:54322:*:postgres:${pgPassword}" \
      >> "$pgpass.tmp"
    mv "$pgpass.tmp" "$pgpass"
    chmod 600 "$pgpass"
  '';
}
