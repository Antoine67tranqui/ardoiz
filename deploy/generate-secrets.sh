#!/bin/sh
# Genere des secrets aleatoires pour deploy/.env (aucune valeur n'est enregistree ni envoyee ailleurs).
# Utiliser trois valeurs differentes pour les trois secrets JWT.
set -eu
command -v openssl >/dev/null || { echo "openssl est requis" >&2; exit 1; }
echo "DB_PASSWORD=$(openssl rand -hex 24)"
echo "JWT_ACCESS_SECRET=$(openssl rand -base64 48 | tr -d '\n=+/')"
echo "JWT_REFRESH_SECRET=$(openssl rand -base64 48 | tr -d '\n=+/')"
echo "JWT_OTP_SECRET=$(openssl rand -base64 48 | tr -d '\n=+/')"
echo "MOMO_WEBHOOK_SECRET=$(openssl rand -base64 48 | tr -d '\n=+/')"
