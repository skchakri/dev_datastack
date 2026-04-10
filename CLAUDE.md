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
Nginx listens on ports 80 and 3000, routing by `server_name` to different host ports:

| Domain Pattern | Proxies To | Purpose |
|---|---|---|
| localhost:3000 | host:3000 | Default app |
| partylite.local, lvh.at, lvh.de/ch/fr/pl/sk/cz, my.lvhpl.com | host:3000 | Partylite |
| lvhavon.com (+ wildcard subdomains) | host:3001 | Avon |
| lvhstup.com (+ wildcard subdomains) | host:3002 | StampinUp |
| lvhnsp.com (+ wildcard subdomains) | host:3003 | Nature's Sunshine |
| lvhmonat.com (+ wildcard subdomains) | host:3004 | Monat |
| lvhpoe.com (+ wildcard subdomains) | host:3005 | PartyOrder |
| kibana.local | kibana:5601 | Kibana UI |
| postgres.local | pgadmin:80 | pgAdmin UI |

### Service Dependencies
- **db-importer**: Waits for mysql, postgres, mongo to be healthy before starting. Built from `importer/Dockerfile` (pre-installs clients + pigz), then runs `importer/import.sh`.
- **kibana**: Depends on elasticsearch.
- All services on `devnet` bridge network. Host access via `host.docker.internal`.

### Import System Details
- `importer/import.sh`: `db_from_name()` extracts database name from filename (strips extensions, takes text before `__`).
- MySQL imports also run `grant_mysql_privileges()` to grant ALL PRIVILEGES to a `pyr` user on startup.
- Imported files/directories are removed after processing.

### Key Configuration
- **Environment**: `.env` file (credentials, see `.env.example` for template)
- **Elasticsearch**: Two instances — ES 6.8.23 (ports 9200/9300) and ES 8.14.3 (ports 9201/9301). Both single-node, 1GB heap, security disabled. Requires `vm.max_map_count >= 262144`
- **Redis**: AOF persistence enabled (`--appendonly yes`)
- **PostgreSQL**: Uses `pgvector/pgvector:pg17` image (pgvector extension available)

## Service Endpoints
- **Kibana**: http://localhost:5601 or http://kibana.local
- **pgAdmin**: http://localhost:5050 or http://postgres.local
- **Adminer**: http://localhost:8080
- **Direct DB**: MySQL:3306, PostgreSQL:5432, MongoDB:27017, Elasticsearch 6.x:9200/9300, Elasticsearch 8.x:9201/9301, Redis:6379
