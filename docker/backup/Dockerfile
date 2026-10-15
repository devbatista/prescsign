# Mesma major do Postgres do compose (postgres:16-alpine): pg_dump de versão
# diferente da do servidor recusa o dump ou gera arquivo que não restaura.
FROM postgres:16-alpine

RUN apk add --no-cache aws-cli gnupg

COPY backup.sh restore.sh run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh /usr/local/bin/run.sh

ENTRYPOINT ["/usr/local/bin/run.sh"]
