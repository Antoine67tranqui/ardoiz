#!/bin/sh
# Planifie la sauvegarde quotidienne (02 h 30, heure du serveur) puis laisse crond au premier plan.
set -eu
# export -p protege correctement les caracteres speciaux eventuels des valeurs.
export -p | grep -E '^export (PG[A-Z]+|AGE_RECIPIENT|BACKUP_[A-Z_]+)=' > /etc/backup.env
echo '30 2 * * * . /etc/backup.env && /usr/local/bin/backup.sh >> /proc/1/fd/1 2>&1' > /etc/crontabs/root
mkdir -p "${BACKUP_DIR:-/backups}"
exec crond -f -l 8
