#!/usr/bin/env bash
set -euo pipefail

cyan() { echo -e "\033[36m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
red() { echo -e "\033[31m$*\033[0m"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || (echo "Missing $1" && return 1); }

# 1) Ensure dependencies
cyan "[1/6] Checking Docker & tools..."
if ! command -v docker >/dev/null 2>&1; then
  cyan "Installing Docker Engine..."
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo     "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu     $(. /etc/os-release && echo $VERSION_CODENAME) stable" |     sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER" || true
  green "Docker installed. You may need to log out/in for group changes."
fi

# 2) Prompt for credentials with defaults
cyan "[2/6] Gathering database credentials (press Enter for defaults)…"
read -rp "MySQL username [root]: " MYSQL_USER; MYSQL_USER=${MYSQL_USER:-root}
read -rsp "MySQL password [password]: " MYSQL_ROOT_PASSWORD; echo; MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-password}

read -rp "Postgres username [root]: " POSTGRES_USER; POSTGRES_USER=${POSTGRES_USER:-root}
read -rsp "Postgres password [password]: " POSTGRES_PASSWORD; echo; POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-password}

read -rp "Mongo root username [root]: " MONGO_INITDB_ROOT_USERNAME; MONGO_INITDB_ROOT_USERNAME=${MONGO_INITDB_ROOT_USERNAME:-root}
read -rsp "Mongo root password [password]: " MONGO_INITDB_ROOT_PASSWORD; echo; MONGO_INITDB_ROOT_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD:-password}

read -rp "pgAdmin email [admin@example.com]: " PGADMIN_DEFAULT_EMAIL; PGADMIN_DEFAULT_EMAIL=${PGADMIN_DEFAULT_EMAIL:-admin@example.com}
read -rsp "pgAdmin password [password]: " PGADMIN_DEFAULT_PASSWORD; echo; PGADMIN_DEFAULT_PASSWORD=${PGADMIN_DEFAULT_PASSWORD:-password}

# 3) Write .env
cyan "[3/6] Writing .env…"
cat > .env <<ENV
MYSQL_USER=${MYSQL_USER}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
MONGO_INITDB_ROOT_USERNAME=${MONGO_INITDB_ROOT_USERNAME}
MONGO_INITDB_ROOT_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD}
PGADMIN_DEFAULT_EMAIL=${PGADMIN_DEFAULT_EMAIL}
PGADMIN_DEFAULT_PASSWORD=${PGADMIN_DEFAULT_PASSWORD}
ENV
green "Saved credentials to .env"

# 4) Optional: ask for dump files to copy into input/*
cyan "[4/6] (Optional) Provide dump paths (leave blank to skip)"
read -rp "Path to a MySQL dump (.sql or .sql.gz) to copy: " MYSQL_DUMP || true
if [ -n "${MYSQL_DUMP:-}" ] && [ -e "$MYSQL_DUMP" ]; then cp -v "$MYSQL_DUMP" ./input/mysql/; fi

read -rp "Path to a Postgres dump (.sql, .sql.gz, or .dump) to copy: " PG_DUMP || true
if [ -n "${PG_DUMP:-}" ] && [ -e "$PG_DUMP" ]; then cp -v "$PG_DUMP" ./input/postgres/; fi

read -rp "Path to a Mongo dump (folder or .archive/.archive.gz) to copy: " MONGO_DUMP || true
if [ -n "${MONGO_DUMP:-}" ] && [ -e "$MONGO_DUMP" ]; then
  if [ -d "$MONGO_DUMP" ]; then cp -vr "$MONGO_DUMP" ./input/mongo/;
  else cp -v "$MONGO_DUMP" ./input/mongo/; fi
fi

# 5) Dev TLS cert, nginx config & sysctl for ES
cyan "[5/6] Preparing Nginx config, TLS cert and sysctl (Elasticsearch)…"

# Copy nginx configuration if it doesn't exist
if [ ! -f nginx/conf/app.conf ]; then
  if [ -f input/nginx/app.conf ]; then
    cp -v input/nginx/app.conf nginx/conf/app.conf
    green "Copied nginx configuration from input/nginx/app.conf"
  else
    red "Warning: input/nginx/app.conf not found, nginx configuration not copied"
  fi
fi

if [ ! -f nginx/certs/localhost.crt ] || [ ! -f nginx/certs/localhost.key ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout nginx/certs/localhost.key -out nginx/certs/localhost.crt -days 825 -subj "/CN=localhost"
  green "Generated self-signed certificate in nginx/certs"
fi

if ! sysctl vm.max_map_count | grep -q 262144; then
  sudo sysctl -w vm.max_map_count=262144
  echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf >/dev/null
  green "vm.max_map_count set to 262144"
fi

# 6) Bring up the stack
cyan "[6/6] Starting Docker stack…"
docker compose --env-file .env up -d
green "All services are starting."
echo
echo "URLs:"
echo " - Kibana:           http://localhost:5601 or http://kibana.local"
echo " - pgAdmin:          http://localhost:5050 or http://postgres.local (email: ${PGADMIN_DEFAULT_EMAIL})"
echo " - Adminer:          http://localhost:8080"
echo
echo "Next steps:"
echo " - Put DB dumps in ./input/{mysql,postgres,mongo}. Importer will auto-load."
echo " - Add kibana.local and postgres.local to /etc/hosts pointing to 127.0.0.1 for local domain access."
