#!/bin/sh
# Dump do Postgres, criptografado AQUI (antes de sair do servidor) e enviado ao
# bucket de backup.
#
# A criptografia é no cliente porque o dump tem dado de saúde de paciente
# (LGPD, art. 11): vazamento do bucket ou da credencial de backup não pode
# expor o conteúdo. Sem a BACKUP_ENCRYPTION_PASSPHRASE o backup é inútil —
# guarde-a fora deste servidor.
set -eu

: "${POSTGRES_HOST:?}"
: "${POSTGRES_USER:?}"
: "${POSTGRES_PASSWORD:?}"
: "${POSTGRES_DB:?}"
: "${BACKUP_S3_BUCKET:?}"
: "${BACKUP_ENCRYPTION_PASSPHRASE:?}"

prefix="${BACKUP_S3_PREFIX:-postgres}"
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
key="$prefix/${POSTGRES_DB}_${timestamp}.dump.gpg"
workdir=$(mktemp -d)
dump="$workdir/db.dump"
encrypted="$workdir/db.dump.gpg"

# O dump em claro nunca sobrevive ao script, nem em caso de falha.
trap 'rm -rf "$workdir"' EXIT INT TERM

endpoint_args=""
if [ -n "${BACKUP_S3_ENDPOINT:-}" ]; then
  endpoint_args="--endpoint-url $BACKUP_S3_ENDPOINT"
fi

echo "backup: iniciando dump de $POSTGRES_DB"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h "$POSTGRES_HOST" -p "${POSTGRES_PORT:-5432}" -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" --format=custom --file="$dump"

# Passphrase pelo descritor 3, não pela linha de comando: argumento de processo
# aparece no `ps` de qualquer um no container.
gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
  --symmetric --cipher-algo AES256 --output "$encrypted" "$dump" 3<<EOF
$BACKUP_ENCRYPTION_PASSPHRASE
EOF

# shellcheck disable=SC2086
aws s3 cp "$encrypted" "s3://$BACKUP_S3_BUCKET/$key" --only-show-errors $endpoint_args

# Confere que o objeto chegou com o tamanho certo antes de declarar sucesso.
local_size=$(wc -c < "$encrypted" | tr -d ' ')
# shellcheck disable=SC2086
remote_size=$(aws s3api head-object --bucket "$BACKUP_S3_BUCKET" --key "$key" \
  --query ContentLength --output text $endpoint_args)

if [ "$local_size" != "$remote_size" ]; then
  echo "backup: FALHOU — tamanho local $local_size, remoto $remote_size ($key)" >&2
  exit 1
fi

date -u +%s > /tmp/last_backup_success
echo "backup: concluído — s3://$BACKUP_S3_BUCKET/$key ($local_size bytes)"
