#!/bin/sh
# Agendador do backup: um dump ao subir o container (cobre o deploy) e um por
# dia em BACKUP_TIME_UTC (default 06:00 UTC = 03:00 em Brasília).
#
# Loop simples em vez de crond: o crond do busybox roda o job sem o ambiente do
# container, e passar as credenciais exigiria gravá-las em arquivo.
#
# `docker compose run --rm backup restore.sh ...` cai direto no comando pedido.
set -eu

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

backup_time="${BACKUP_TIME_UTC:-06:00}"
last_run_day=""

run_backup() {
  backup.sh || echo "backup: FALHOU — ver a saída acima" >&2
}

if [ "${BACKUP_ON_START:-true}" = "true" ]; then
  run_backup
fi

while :; do
  today=$(date -u +%Y-%m-%d)
  if [ "$(date -u +%H:%M)" = "$backup_time" ] && [ "$last_run_day" != "$today" ]; then
    last_run_day="$today"
    run_backup
  fi
  sleep 30
done
