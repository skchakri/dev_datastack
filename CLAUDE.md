# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
Docker-based development data stack providing MySQL 8.0, PostgreSQL 17 (with pgvector), MongoDB 7, Elasticsearch 6.8.23 and 8.14.3, Redis 7, management UIs (Kibana, pgAdmin 9.9, Adminer), and Nginx reverse proxy. Designed as a turnkey local development environment with automatic database import via inotifywait file watching.

## Common Commands

### Stack Management
```bash
./bootstrap.sh                        # Full interactive setup (installs Docker, prompts for creds, starts stack)
docker compose up -d                  # Start all services
docker compose down                   # Stop all services
docker compose logs -f [service]      # View service logs
docker compose ps                     # Check service status
```

### Database Shells
```bash
docker compose exec mysql mysql -uroot -p$MYSQL_ROOT_PASSWORD
docker compose exec postgres psql -U $POSTGRES_USER
docker compose exec mongo mongosh -u root -p $MONGO_INITDB_ROOT_PASSWORD
docker compose exec redis redis-cli
```

### Database Import
Drop files into `input/` directories — the db-importer container watches with inotifywait and auto-imports:
- `input/mysql/*.sql` or `*.sql.gz` — database name extracted from filename prefix before `__`
- `input/postgres/*.sql`, `*.sql.gz`, or `*.dump` — same naming convention
- `input/mongo/<directory>` or `*.archive`, `*.archive.gz`

Files are **deleted after successful import**. Check importer logs with `docker compose logs -f db-importer`.

## Architecture

### Nginx Reverse Proxy Routing
Only port **80** is published to the host (`docker-compose.yml` maps `80:80`). The `listen 3000` block in `nginx/conf/app.conf` is not reachable from outside the container — the real Rails apps run on host ports 3000–3006 and nginx proxies to them via `host.docker.internal`. Routing is by `server_name`:

| Domain Pattern | Proxies To | Purpose |
|---|---|---|
| partylite.local, lvh.at, lvh.de/ch/fr/pl/sk/cz, my.lvhpl.com | host:3000 | Partylite |
| lvhavon.com (+ wildcard), avon.local | host:3001 | Avon |
| lvhstup.com (+ wildcard), stup.local | host:3002/3003 (see note) | StampinUp |
| lvhnsp.com (+ wildcard), nsp.local | host:3003/3002 (see note) | Nature's Sunshine |
| lvhmonat.com (+ wildcard), monat.local | host:3004 | Monat |
| lvhpoe.com (+ wildcard), pl.local | host:3005 | PartyOrder |
| kwiverr.local | host:3006 | Kwiverr |
| myprofvault.local | host:1100 | ProfVault |
| ownsites.local | host:8088 | OwnSites |
| kibana.local | kibana:5601 | Kibana UI |
| postgres.local | pgadmin:80 | pgAdmin UI |

**Note:** `stup.local`/`nsp.local` shortcut mappings in `nginx/conf/app.conf` are inverted relative to the `lvhstup.com`/`lvhnsp.com` mappings (stup.local → 3003, nsp.local → 3002). Verify intent in `nginx/conf/app.conf` before relying on a shortcut.

### Service Dependencies
- **db-importer**: Waits for mysql, postgres, mongo to be healthy, then runs `importer/import.sh`. Built from `importer/Dockerfile` (pre-installs mysql/postgres/mongo clients, `inotify-tools`, `pigz`). **`restart: "no"` is intentional** — unlike the other services (`unless-stopped`), the importer is a one-shot watcher. If it exits or you reboot, bring it back explicitly: `docker compose up -d db-importer`.
- **kibana**: Depends on `elasticsearch-8` (not ES 6). Kibana 8.14.3 talks to the ES 8 instance.
- All services on `devnet` bridge network. Host access via `host.docker.internal` (nginx has `extra_hosts: host-gateway` wired).

### Import System Details
- `importer/import.sh`: `db_from_name()` takes everything before `__` in the basename (after stripping `.sql`/`.sql.gz`/`.dump`/`.archive`/`.archive.gz`). A filename with no `__` produces an empty db name and the dump is imported **as-is** — no database is auto-created, so the dump must contain its own `CREATE DATABASE` / `USE` (MySQL) or land in the default `postgres` DB.
- Only `.sql` / `.sql.gz` / `.dump` (Postgres) / `.archive` / `.archive.gz` / directories are picked up. Anything else is logged as "skip" and left in place.
- MySQL imports also run `grant_mysql_privileges()` to grant ALL PRIVILEGES to a `pyr` user on startup (silently no-ops if the user doesn't exist yet — it's created by `input/mysql/00_init_users.sql`).
- Imported files/directories are removed after processing.
- **Gotcha — dual role of `input/{mysql,postgres}`:** these dirs are mounted both as `/docker-entrypoint-initdb.d:ro` on the MySQL/Postgres containers AND watched by `db-importer`. On a first boot with a populated input dir the official image init runs the `.sql` files once; the importer then also processes them. Numeric-prefixed init scripts (e.g. `00_init_users.sql`) are lexicographically first, so they run before dumps in the container-init path.
- Import-time tuning: MySQL session gets `FOREIGN_KEY_CHECKS=0`, `UNIQUE_CHECKS=0`, `AUTOCOMMIT=0`, `SQL_LOG_BIN=0` + `--max-allowed-packet=512M`. Postgres gets `synchronous_commit=off`, `maintenance_work_mem=512MB`, `max_wal_size=2GB`. `pg_restore` uses `--jobs=4`; `mongorestore` uses `--numParallelCollections=4 --numInsertionWorkersPerCollection=4`. Parallel decompression uses `pigz` if available, else `gunzip`.

### Key Configuration
- **Environment**: `.env` file (credentials, see `.env.example` for template). `docker compose --env-file .env up -d` is what `bootstrap.sh` runs.
- **Elasticsearch**: Two instances — ES 6.8.23 (ports 9200/9300) and ES 8.14.3 (ports 9201/9301). Both single-node, 1GB heap, security disabled. Requires `vm.max_map_count >= 262144`.
- **Redis**: AOF persistence enabled (`--appendonly yes`).
- **PostgreSQL**: Uses `pgvector/pgvector:pg17` image (pgvector extension available). Runs with `synchronous_commit=off`, `max_connections=500`, `shared_buffers=512MB` — dev-tuned for speed, not durability.
- **MySQL**: `--innodb-buffer-pool-size=1G`, `max_connections=500`, `innodb-flush-log-at-trx-commit=2` (also dev-tuned — do not copy to prod).

### Bootstrap-Managed Host State
`bootstrap.sh` mutates the host in ways not obvious from the repo alone:
- Installs Docker Engine + Compose plugin if missing; adds `$USER` to the `docker` group.
- Installs VLC media player (unrelated to the stack — bundled for convenience).
- Writes `vm.max_map_count=262144` via `sysctl -w` and appends it to `/etc/sysctl.conf` (for Elasticsearch).
- Generates a self-signed TLS cert at `nginx/certs/localhost.{crt,key}` if missing.
- Appends a **partial** `/etc/hosts` line: `kibana.local postgres.local partylite.local my.lvhpartylite.com lvhavon.com lvhstup.com lvhnsp.com lvhmonat.com partyorder.lvhpartylite.com`. Many server_names in `nginx/conf/app.conf` are **not** in this list (e.g. `lvhpoe.com`, all `*.local` shortcuts like `stup.local`/`nsp.local`/`monat.local`/`kwiverr.local`, `myprofvault.local`, `ownsites.local`, wildcard subdomains). When adding a new nginx server_name, add its `/etc/hosts` entry by hand.
- If `nginx/conf/app.conf` is missing, copies from `input/nginx/app.conf` as a fallback.

## Service Endpoints
- **Kibana**: http://localhost:5601 or http://kibana.local
- **pgAdmin**: http://localhost:5050 or http://postgres.local
- **Adminer**: http://localhost:8080
- **Direct DB**: MySQL:3306, PostgreSQL:5432, MongoDB:27017, Elasticsearch 6.x:9200/9300, Elasticsearch 8.x:9201/9301, Redis:6379
