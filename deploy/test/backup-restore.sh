#!/bin/sh
# Verifie de bout en bout la sauvegarde chiffree et la restauration, sur une vraie base PostgreSQL.
# Prerequis : pg_dump, psql, age, une base accessible (variables PG* ou DATABASE_URL_ADMIN).
#   PGHOST=localhost PGUSER=ardoiz PGPASSWORD=ardoiz PGDATABASE=ardoiz_test sh deploy/test/backup-restore.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"; psql -qd postgres -c "DROP DATABASE IF EXISTS carne_restore_check" >/dev/null 2>&1 || true' EXIT

age-keygen -o "$tmp/key.txt" 2>"$tmp/pub.txt"
recipient="$(sed -n 's/^Public key: //p' "$tmp/pub.txt")"
[ -n "$recipient" ] || { echo "cle age non generee" >&2; exit 1; }

before="$(psql -Atqc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")"
users_before="$(psql -Atqc "SELECT count(*) FROM users")"

AGE_RECIPIENT="$recipient" BACKUP_DIR="$tmp/out" sh "$here/../backup/backup.sh"
file="$(ls "$tmp"/out/carne-*.sql.gz.age)"

# 1. Le fichier est bien chiffre : aucun texte lisible de la base.
if gunzip -c "$file" >/dev/null 2>&1 || grep -aq 'CREATE TABLE' "$file"; then echo "ECHEC : sauvegarde non chiffree" >&2; exit 1; fi

# 2. Sans la cle privee, impossible a lire.
age-keygen -o "$tmp/other.txt" 2>/dev/null
if age -d -i "$tmp/other.txt" "$file" >/dev/null 2>&1; then echo "ECHEC : dechiffrable avec une autre cle" >&2; exit 1; fi

sleep 1  # horodatages distincts
# 3. Retention : un vieux fichier est supprime, un recent est conserve.
touch -d '31 days ago' "$tmp/out/carne-20200101T000000Z.sql.gz.age"
AGE_RECIPIENT="$recipient" BACKUP_DIR="$tmp/out" BACKUP_KEEP_DAYS=30 sh "$here/../backup/backup.sh" >/dev/null
[ ! -e "$tmp/out/carne-20200101T000000Z.sql.gz.age" ] || { echo "ECHEC : vieille sauvegarde conservee" >&2; exit 1; }
[ "$(ls "$tmp"/out | wc -l)" -ge 2 ] || { echo "ECHEC : sauvegardes recentes supprimees" >&2; exit 1; }

# 4. Restauration dans une base neuve, memes tables et memes comptes.
psql -qd postgres -c "DROP DATABASE IF EXISTS carne_restore_check" -c "CREATE DATABASE carne_restore_check"
base_url="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST:-localhost}/carne_restore_check"
sh "$here/../backup/restore.sh" "$file" "$tmp/key.txt" "$base_url"
after="$(psql -Atqd carne_restore_check -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")"
users_after="$(psql -Atqd carne_restore_check -c "SELECT count(*) FROM users")"
[ "$before" = "$after" ] && [ "$users_before" = "$users_after" ] || { echo "ECHEC : $before/$users_before tables/comptes avant, $after/$users_after apres" >&2; exit 1; }
echo "OK : sauvegarde chiffree, retention et restauration verifiees ($after tables, $users_after comptes)"
