#!/bin/sh
# Restaura um backup num banco NOVO. Uso:
#
#   restore.sh list                       # lista os backups do bucket
#   restore.sh <chave-s3> <banco-destino> # restaura em <banco-destino>
#
# Nunca restaura por cima do banco em uso: o destino precisa ser outro nome e
# não pode existir. Trocar o banco de produção pelo restaurado é decisão
# humana, feita depois de conferir o resultado (ver docs/DEPLOY_PRODUCAO.md).
set -eu

: "${POSTGRES_HOST:?}"
: "${POSTGRES_USER:?}"
: "${POSTGRES_PASSWORD:?}"
: "${POSTGRES_DB:?}"
: "${BACKUP_S3_BUCKET:?}"

prefix="${BACKUP_S3_PREFIX:-postgres}"
endpoint_args=""
if [ -n "${BACKUP_S3_ENDPOINT:-}" ]; then
  endpoint_args="--endpoint-url $BACKUP_S3_ENDPOINT"
fi

if [ "${1:-}" = "list" ]; then
  # shellcheck disable=SC2086
  exec aws s3 ls "s3://$BACKUP_S3_BUCKET/$prefix/" $endpoint_args
fi

key="${1:?informe a chave do backup (veja: restore.sh list)}"
target="${2:?informe o nome do banco de destino}"
: "${BACKUP_ENCRYPTION_PASSPHRASE:?}"

case "$target" in
  *[!a-z0-9_]* | "")
    echo "restore: recusado — nome de banco inválido (use a-z, 0-9 e _)" >&2
    exit 1
    ;;
esac

if [ "$target" = "$POSTGRES_DB" ]; then
  echo "restore: recusado — o destino não pode ser o banco em uso ($POSTGRES_DB)" >&2
  exit 1
fi

export PGPASSWORD="$POSTGRES_PASSWORD"
pg_args="-h $POSTGRES_HOST -p ${POSTGRES_PORT:-5432} -U $POSTGRES_USER"

# shellcheck disable=SC2086
exists=$(psql $pg_args -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$target'")
if [ "$exists" = "1" ]; then
  echo "restore: recusado — o banco $target já existe" >&2
  exit 1
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT INT TERM

# shellcheck disable=SC2086
aws s3 cp "s3://$BACKUP_S3_BUCKET/$key" "$workdir/db.dump.gpg" --only-show-errors $endpoint_args

gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
  --decrypt --output "$workdir/db.dump" "$workdir/db.dump.gpg" 3<<EOF
$BACKUP_ENCRYPTION_PASSPHRASE
EOF

# shellcheck disable=SC2086
createdb $pg_args "$target"
# shellcheck disable=SC2086
pg_restore $pg_args -d "$target" --no-owner --exit-on-error "$workdir/db.dump"

echo "restore: concluído em $target — confira antes de qualquer troca"
# shellcheck disable=SC2086
psql $pg_args -d "$target" -tAc \
  "SELECT 'documents: ' || count(*) FROM documents UNION ALL SELECT 'patients: ' || count(*) FROM patients"
