#!/usr/bin/env bash
set -euo pipefail
log() { echo -e "\n[IMPORTER] $*\n"; }

db_from_name() {
  local path="$1" base name
  base="$(basename "$path")"
  if [ -d "$path" ]; then echo "$base"; return 0; fi
  case "$base" in
    *.sql.gz) name="${base%.sql.gz}" ;;
    *.archive.gz) name="${base%.archive.gz}" ;;
    *) name="$base" ;;
  esac
  name="${name%.sql}"; name="${name%.dump}"; name="${name%.archive}"
  name="${name%%__*}"; [ -z "$name" ] && echo "" || echo "$name"
}

# Use pigz for parallel decompression if available, fall back to gunzip
DECOMPRESS="$(command -v pigz >/dev/null 2>&1 && echo 'pigz -dc' || echo 'gunzip -c')"

# MySQL: aggressive session-level tuning for bulk imports
MYSQL_FAST_FLAGS="--max-allowed-packet=512M --net-buffer-length=16M --init-command=\"SET SESSION FOREIGN_KEY_CHECKS=0, UNIQUE_CHECKS=0, AUTOCOMMIT=0, SQL_LOG_BIN=0;\""

import_mysql_file() {
  local f="$1" db; db="$(db_from_name "$f")"
  case "$f" in
    *.sql)
      if [ -n "$db" ]; then
        log "MySQL: ensure DB \`$db\` and import $f"
        mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$db\`;"
        { cat "$f"; echo "COMMIT;"; } | mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" $MYSQL_FAST_FLAGS "$db"
      else
        log "MySQL: import $f (as-is)"
        { cat "$f"; echo "COMMIT;"; } | mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" $MYSQL_FAST_FLAGS
      fi
      log "MySQL: removing processed file $f"; rm -f "$f" ;;
    *.sql.gz)
      if [ -n "$db" ]; then
        log "MySQL: ensure DB \`$db\` and import (gz) $f"
        mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$db\`;"
        { $DECOMPRESS "$f"; echo "COMMIT;"; } | mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" $MYSQL_FAST_FLAGS "$db"
      else
        log "MySQL: import (gz) $f (as-is)"
        { $DECOMPRESS "$f"; echo "COMMIT;"; } | mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" $MYSQL_FAST_FLAGS
      fi
      log "MySQL: removing processed file $f"; rm -f "$f" ;;
    *) log "MySQL: skip $f" ;;
  esac
}

grant_mysql_privileges(){
  log "MySQL: granting privileges to pyr user"
  mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "
    GRANT ALL PRIVILEGES ON *.* TO 'pyr'@'%' WITH GRANT OPTION;
    GRANT ALL PRIVILEGES ON *.* TO 'pyr'@'localhost' WITH GRANT OPTION;
    GRANT ALL PRIVILEGES ON *.* TO 'pyr'@'127.0.0.1' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
  " 2>/dev/null || log "MySQL: pyr user may not exist yet, skipping privilege grant"
}

initial_mysql(){ shopt -s nullglob; grant_mysql_privileges; for f in /input/mysql/*; do [ -f "$f" ] && import_mysql_file "$f"; done; }
watch_mysql(){ inotifywait -m -e close_write,create,move /input/mysql --format '%w%f' | while read -r f; do [ -f "$f" ] && import_mysql_file "$f"; done; }

# Postgres: session-level tuning for fast bulk imports
PG_SPEED_SETTINGS="SET maintenance_work_mem='512MB'; SET synchronous_commit=off; SET wal_buffers='64MB'; SET max_wal_size='2GB'; SET checkpoint_completion_target=0.9;"

import_pg_file(){
  local f="$1" db default_db; db="$(db_from_name "$f")"; default_db="postgres"; export PGPASSWORD="$POSTGRES_PASSWORD"; [ -z "$db" ] && db="$default_db"
  log "Postgres: ensure DB "$db""
  psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$default_db" -tc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1 || \
    psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$default_db" -c "CREATE DATABASE "${db}";"
  case "$f" in
    *.sql)
      log "Postgres: import $f into "$db""
      { echo "$PG_SPEED_SETTINGS"; cat "$f"; } | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$db" --single-transaction
      log "Postgres: removing processed file $f"; rm -f "$f" ;;
    *.sql.gz)
      log "Postgres: import (gz) $f into "$db""
      { echo "$PG_SPEED_SETTINGS"; $DECOMPRESS "$f"; } | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$db" --single-transaction
      log "Postgres: removing processed file $f"; rm -f "$f" ;;
    *.dump)
      log "Postgres: restore $f into "$db""
      pg_restore -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$db" --clean --if-exists --jobs=4 "$f"
      log "Postgres: removing processed file $f"; rm -f "$f" ;;
    *) log "Postgres: skip $f" ;;
  esac
}

initial_pg(){ shopt -s nullglob; for f in /input/postgres/*; do [ -f "$f" ] && import_pg_file "$f"; done; }
watch_pg(){ inotifywait -m -e close_write,create,move /input/postgres --format '%w%f' | while read -r f; do [ -f "$f" ] && import_pg_file "$f"; done; }

# Mongo: parallel collections and insertion workers
MONGO_PARALLEL_FLAGS="--numParallelCollections=4 --numInsertionWorkersPerCollection=4"

mongo_restore_path(){
  local path="$1" db; db="$(db_from_name "$path")"; local auth="-u $MONGO_USER -p $MONGO_PASSWORD --authenticationDatabase admin"
  if [ -d "$path" ]; then
    if [ -n "$db" ]; then log "Mongo: restore dir $path -> db $db"; mongorestore --host "$MONGO_HOST" $auth --drop --db "$db" $MONGO_PARALLEL_FLAGS "$path"
    else log "Mongo: restore dir $path (as-is)"; mongorestore --host "$MONGO_HOST" $auth --drop $MONGO_PARALLEL_FLAGS "$path"; fi
    log "Mongo: removing processed directory $path"; rm -rf "$path"
  else
    case "$path" in
      *.archive) if [ -n "$db" ]; then log "Mongo: restore $path -> db $db"; mongorestore --host "$MONGO_HOST" $auth --drop --archive="$path" --db "$db" $MONGO_PARALLEL_FLAGS
                 else log "Mongo: restore $path (as-is)"; mongorestore --host "$MONGO_HOST" $auth --drop --archive="$path" $MONGO_PARALLEL_FLAGS; fi
                 log "Mongo: removing processed file $path"; rm -f "$path" ;;
      *.archive.gz) if [ -n "$db" ]; then log "Mongo: restore (gz) $path -> db $db"; $DECOMPRESS "$path" | mongorestore --host "$MONGO_HOST" $auth --drop --archive --db "$db" $MONGO_PARALLEL_FLAGS
                    else log "Mongo: restore (gz) $path (as-is)"; $DECOMPRESS "$path" | mongorestore --host "$MONGO_HOST" $auth --drop --archive $MONGO_PARALLEL_FLAGS; fi
                    log "Mongo: removing processed file $path"; rm -f "$path" ;;
      *) log "Mongo: skip $path" ;;
    esac
  fi
}

initial_mongo(){ shopt -s nullglob; for p in /input/mongo/*; do [ -e "$p" ] && mongo_restore_path "$p"; done; }
watch_mongo(){ inotifywait -m -e close_write,create,move /input/mongo --format '%w%f' | while read -r p; do [ -e "$p" ] && mongo_restore_path "$p"; done; }

log "Running initial imports (if any)…"
initial_mysql & initial_pg & initial_mongo &
wait
log "Watching input folders for changes…"
watch_mysql & watch_pg & watch_mongo &
wait -n
