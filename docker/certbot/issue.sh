#!/bin/sh
# Emissão inicial do certificado (uma vez por servidor): `make prod-cert-init`.
#
# Roda em modo standalone, com o nginx parado — o nginx de produção não sobe
# sem o certificado, então a primeira emissão não pode depender dele. As
# renovações seguintes usam o webroot servido pelo nginx (renew.sh).
#
# LETSENCRYPT_STAGING=true emite contra o ambiente de teste do Let's Encrypt,
# que não tem o limite de emissões da produção. Use na primeira tentativa.
set -eu

: "${APP_DOMAIN:?APP_DOMAIN é obrigatória}"
: "${LETSENCRYPT_EMAIL:?LETSENCRYPT_EMAIL é obrigatória}"

staging=""
if [ "${LETSENCRYPT_STAGING:-false}" = "true" ]; then
  staging="--staging"
fi

exec certbot certonly --standalone $staging \
  --cert-name prescsign \
  -d "$APP_DOMAIN" \
  -d "login.$APP_DOMAIN" \
  -d "register.$APP_DOMAIN" \
  -d "app.$APP_DOMAIN" \
  -d "admin.$APP_DOMAIN" \
  --email "$LETSENCRYPT_EMAIL" \
  --agree-tos --non-interactive --keep-until-expiring
