# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
This is a Docker-based development data stack that provides MySQL 8.0, PostgreSQL 16, MongoDB 7, Elasticsearch 8.14.3, Redis 7, plus management UIs (Kibana, pgAdmin, Adminer) and Nginx with TLS termination. It's designed as a turnkey development environment with automatic database import functionality.

## Common Commands

### Stack Management
```bash
# Full setup (fresh Ubuntu system)
./bootstrap.sh

# Start all services
docker compose up -d

# Stop all services
docker compose down

# View service logs
docker compose logs -f [service-name]

# Check service status
docker compose ps
```

### Database Import
```bash
# Import files by dropping into input directories:
# - input/mysql/*.sql or *.sql.gz (database name from filename before __)
# - input/postgres/*.sql, *.sql.gz, or *.dump
# - input/mongo/<directory> or *.archive, *.archive.gz

# Manual import trigger (if needed)
docker compose exec db-importer /app/import.sh
```

### Development
```bash
# Access container shells
docker compose exec mysql bash
docker compose exec postgres bash
docker compose exec mongo bash

# View importer logs (for debugging imports)
docker compose logs -f db-importer
```

## Architecture

### Service Dependencies
- **db-importer**: Depends on mysql, postgres, mongo being healthy
- **kibana**: Depends on elasticsearch being healthy
- **nginx**: Runs independently, proxies host port 3000

### Network Architecture
- All services communicate via `devnet` bridge network
- External access via mapped ports to localhost
- Nginx provides HTTPS termination with self-signed certificates

### Data Persistence
- All database data persisted in `./data/` directory
- Nginx logs in `./nginx/logs/`
- TLS certificates in `./nginx/certs/`

### Import System
The db-importer service uses `inotifywait` to monitor `./input/` directories and automatically imports new files:
- **MySQL**: Extracts database name from filename prefix (before `__`)
- **PostgreSQL**: Creates database from filename, handles .dump format via pg_restore
- **MongoDB**: Supports both directory dumps and .archive formats

## Service Endpoints
- **Application**: https://localhost:3000 (SSL-enabled, proxies to host)
- **Kibana**: http://localhost:5601
- **pgAdmin**: http://localhost:5050
- **Adminer**: http://localhost:8080
- **Direct DB access**: MySQL:3306, PostgreSQL:5432, MongoDB:27017, Elasticsearch:9200, Redis:6379

## Configuration
- **Environment variables**: Stored in `.env` file
- **Database credentials**: Set via bootstrap.sh or manually in .env
- **Elasticsearch**: Configured with 1GB heap size
- **System requirements**: Elasticsearch needs `vm.max_map_count >= 262144` (handled by bootstrap)

## File Structure Notes
- `bootstrap.sh`: Interactive setup script - handles Docker installation, credentials, TLS certs
- `docker-compose.yml`: Complete service definitions with health checks
- `importer/import.sh`: Database import logic with file watching
- `nginx/conf/app.conf`: Reverse proxy configuration
- Not a git repository - this is a standalone development toolkit