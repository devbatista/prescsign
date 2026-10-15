#!/bin/sh
# Recarrega o nginx a cada 6h para pegar o certificado renovado pelo certbot,
# que roda em outro container e não tem como sinalizar este.
#
# Fica em /docker-entrypoint.d/ e não no `command` do Compose: sobrescrever o
# command faz o entrypoint da imagem pular o processamento dos templates.
set -eu

(
  while :; do
    sleep 21600
    nginx -s reload
  done
) &
