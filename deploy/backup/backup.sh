#!/bin/sh
# Sauvegarde chiffree de la base : pg_dump, compression, chiffrement age avec la cle PUBLIQUE.
# Le serveur ne peut donc pas dechiffrer ses propres sauvegardes : un vol du serveur ou du volume
# de sauvegarde ne divulgue pas les donnees. Variables : PG* (connexion), AGE_RECIPIENT (cle
# publique age), BACKUP_DIR (defaut /backups), BACKUP_KEEP_DAYS (defaut 30).
set -eu
: "${AGE_RECIPIENT:?AGE_RECIPIENT est requis}"
dir="${BACKUP_DIR:-/backups}"
keep_days="${BACKUP_KEEP_DAYS:-30}"
mkdir -p "$dir"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
final="$dir/carne-$stamp.sql.gz.age"
work="$(mktemp -d)"
trap 'rm -rf "$work" "$final.part"' EXIT

# Etapes separees (pas de pipe) : un echec de pg_dump ne doit jamais produire une sauvegarde "valide" vide.
pg_dump --no-owner --no-privileges --format=plain --file="$work/dump.sql"
[ -s "$work/dump.sql" ] || { echo "Sauvegarde vide, abandon" >&2; exit 1; }
gzip -9 "$work/dump.sql"
age -r "$AGE_RECIPIENT" -o "$final.part" "$work/dump.sql.gz"
[ -s "$final.part" ] || { echo "Chiffrement echoue, abandon" >&2; exit 1; }
mv "$final.part" "$final"

# Retention exacte (en minutes) : au-dela de la duree annoncee dans la politique de confidentialite,
# les copies disparaissent.
find "$dir" -name 'carne-*.sql.gz.age' -mmin +"$((keep_days * 24 * 60))" -delete
echo "Sauvegarde ecrite : $final ($(wc -c < "$final") octets)"
