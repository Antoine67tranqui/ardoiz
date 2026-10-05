#!/bin/sh
# Controle apres deploiement : sh deploy/smoke.sh https://carne.example.bj
# Echoue (code 1) au premier probleme, avec un message clair.
set -eu
base="${1:?Usage: smoke.sh https://domaine}"
fail() { echo "ECHEC : $1" >&2; exit 1; }
ok() { echo "ok : $1"; }

curl -fsS "$base/api/v1/health" | grep -q '"status":"ok"' || fail "l'API ne repond pas sur /api/v1/health"
ok "API en ligne"

headers="$(curl -fsSI "$base/")"
echo "$headers" | grep -qi '^strict-transport-security:' || fail "HSTS absent"
echo "$headers" | grep -qi "^content-security-policy:.*default-src 'none'" || fail "CSP de la vitrine absente"
echo "$headers" | grep -qi '^x-content-type-options: nosniff' || fail "nosniff absent"
ok "en-tetes de securite du site"

app="$(curl -fsSI "$base/app/index.html")"
echo "$app" | grep -qi "^content-security-policy:.*script-src 'self'" || fail "CSP du client web absente"
ok "client web servi avec sa CSP"

for page in confidentialite.html conditions.html mentions-legales.html; do
  curl -fsS "$base/$page" >/dev/null || fail "$page introuvable"
done
ok "pages juridiques"
if [ "${SMOKE_ALLOW_PLACEHOLDERS:-0}" = "1" ]; then
  echo "attention : controle des points a completer ignore (SMOKE_ALLOW_PLACEHOLDERS=1), a ne faire qu'avant la publication"
elif curl -fsS "$base/confidentialite.html" "$base/conditions.html" "$base/mentions-legales.html" | grep -q '\[à \(compléter\|confirmer\)'; then
  fail "des passages [à compléter] ou [à confirmer] sont encore visibles dans les pages juridiques (voir docs/conformite/points-a-completer.md, ou SMOKE_ALLOW_PLACEHOLDERS=1 pour un essai prive)"
else
  ok "aucun point a completer restant dans les textes juridiques"
fi

[ "$(curl -s -o /dev/null -w '%{http_code}' "$base/test/app.test.mjs")" = "404" ] || fail "les fichiers de test sont accessibles"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$base/api/v1/auth/me")" = "401" ] || fail "/auth/me devrait refuser sans jeton (401)"
ok "fichiers de test inaccessibles, routes protegees"
code="$(curl -s -o /dev/null -w '%{http_code}' "http://${base#https://}/" || true)"
case "$code" in 301|302|307|308) ok "redirection HTTP vers HTTPS" ;; *) fail "pas de redirection de HTTP vers HTTPS (code $code)" ;; esac
echo "Tous les controles sont passes."
