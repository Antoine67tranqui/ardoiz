#!/bin/sh
# Restauration d'une sauvegarde, A EXECUTER SUR VOTRE POSTE (la cle privee ne doit jamais etre sur le serveur).
#   ./restore.sh carne-20261006T023000Z.sql.gz.age cle-privee-age.txt postgresql://utilisateur:motdepasse@hote/base
# La base cible doit etre VIDE (ou nouvelle) : le script ne supprime rien.
set -eu
[ "$#" -eq 3 ] || { echo "Usage: restore.sh <fichier.age> <cle-privee.txt> <url-postgres>" >&2; exit 2; }
age -d -i "$2" "$1" | gunzip | psql --set ON_ERROR_STOP=1 --quiet "$3"
echo "Restauration terminee."
