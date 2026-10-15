#!/bin/sh
# Renovação contínua: tenta a cada 12h, e o certbot só renova o que vence em
# menos de 30 dias. O `--webroot` sobrescreve o `standalone` gravado na
# emissão inicial — com o nginx de pé, a porta 80 é dele.
set -eu

trap exit TERM

while :; do
  certbot renew --webroot -w /var/www/certbot --quiet || echo "certbot: renovação falhou" >&2
  sleep 43200 &
  wait $!
done
