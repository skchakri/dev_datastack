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

import_mysql_file() {
  local f="$1" db; db="$(db_from_name "$f")"
  case "$f" in
    *.sql)
      if [ -n "$db" ]; then
        log "MySQL: ensure DB \`$db\` and import $f"
        mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$db\`;"
        mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$db" < "$f"
      else
        log "MySQL: import $f (as-is)"; mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" < "$f"
      fi
      log "MySQL: removing processed file $f"; rm -f "$f" ;;
    *.sql.gz)
      if [ -n "$db" ]; then
        log "MySQL: ensure DB \`$db\` and import (gz) $f"
        mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$db\`;"
        gunzip -c "$f" | mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$db"
      else
        log "MySQL: import (gz) $f (as-is)"
        gunzip -c "$f" | mysql -h "$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD"
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

import_pg_file(){
  local f="$1" db default_db; db="$(db_from_name "$f")"; default_db="postgres"; export PGPASSWORD="$POSTGRES_PASSWORD"; [ -z "$db" ] && db="$default_db"
  log "Postgres: ensure DB "$db""
  psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$default_db" -tc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1 ||     psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$default_db" -c "CREATE DATABASE "${db}";"
  case "$f" in
    *.sql) log "Postgres: import $f into "$db""; psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$db" -f "$f"
      log "Postgres: removing processed file $f"; rm -f "$f" ;;
    *.sql.gz) log "Postgres: import (gz) $f into "$db""; gunzip -c "$f" | psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$db"
      log "Postgres: removing processed file $f"; rm -f "$f" ;;
    *.dump) log "Postgres: restore $f into "$db""; pg_restore -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$db" --clean --if-exists "$f"
      log "Postgres: removing processed file $f"; rm -f "$f" ;;
    *) log "Postgres: skip $f" ;;
  esac
}

initial_pg(){ shopt -s nullglob; for f in /input/postgres/*; do [ -f "$f" ] && import_pg_file "$f"; done; }
watch_pg(){ inotifywait -m -e close_write,create,move /input/postgres --format '%w%f' | while read -r f; do [ -f "$f" ] && import_pg_file "$f"; done; }

mongo_restore_path(){
  local path="$1" db; db="$(db_from_name "$path")"; local auth="-u $MONGO_USER -p $MONGO_PASSWORD --authenticationDatabase admin"
  if [ -d "$path" ]; then
    if [ -n "$db" ]; then log "Mongo: restore dir $path -> db $db"; mongorestore --host "$MONGO_HOST" $auth --drop --db "$db" "$path"
    else log "Mongo: restore dir $path (as-is)"; mongorestore --host "$MONGO_HOST" $auth --drop "$path"; fi
    log "Mongo: removing processed directory $path"; rm -rf "$path"
  else
    case "$path" in
      *.archive) if [ -n "$db" ]; then log "Mongo: restore $path -> db $db"; mongorestore --host "$MONGO_HOST" $auth --drop --archive="$path" --db "$db"
                 else log "Mongo: restore $path (as-is)"; mongorestore --host "$MONGO_HOST" $auth --drop --archive="$path"; fi
                 log "Mongo: removing processed file $path"; rm -f "$path" ;;
      *.archive.gz) if [ -n "$db" ]; then log "Mongo: restore (gz) $path -> db $db"; gunzip -c "$path" | mongorestore --host "$MONGO_HOST" $auth --drop --archive --db "$db"
                    else log "Mongo: restore (gz) $path (as-is)"; gunzip -c "$path" | mongorestore --host "$MONGO_HOST" $auth --drop --archive; fi
                    log "Mongo: removing processed file $path"; rm -f "$path" ;;
      *) log "Mongo: skip $path" ;;
    esac
  fi
}

initial_mongo(){ shopt -s nullglob; for p in /input/mongo/*; do [ -e "$p" ] && mongo_restore_path "$p"; done; }
watch_mongo(){ inotifywait -m -e close_write,create,move /input/mongo --format '%w%f' | while read -r p; do [ -e "$p" ] && mongo_restore_path "$p"; done; }

log "Running initial imports (if any)…"
initial_mysql; initial_pg; initial_mongo
log "Watching input folders for changes…"
watch_mysql & watch_pg & watch_mongo &
wait -n
