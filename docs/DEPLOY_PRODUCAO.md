# Deploy em produção

Como subir o PrescSign num servidor único com `docker-compose.prod.yml`: TLS
terminado no nginx (Let's Encrypt) e backup diário do Postgres para S3.

Escrito em **15/10/2026**. Validado localmente, com certificado autoassinado no
lugar do Let's Encrypt e um S3 simulado no lugar do bucket real. **A emissão
real do certificado e o envio ao bucket real ainda não foram exercitados** —
fazem parte do primeiro deploy (seção 3).

---

## 1. Pré-requisitos

- **Docker Compose >= 2.24.4.** O override usa `!reset` e `!override`, que não
  existem antes. Em versão anterior o `docker compose` falha no parse, em vez
  de subir com as portas do desenvolvimento.
- **DNS:** registro A (e AAAA, se houver IPv6) apontando para o servidor, para
  o domínio base e os quatro subdomínios: `prescsign.com.br`,
  `login.`, `register.`, `app.` e `admin.`. O certificado cobre exatamente
  esses cinco nomes.
- **Firewall:** só 22, 80 e 443 abertos. O compose não publica Postgres, Redis
  nem Puma, mas o firewall é a segunda barreira.
- **Bucket de backup**, separado do bucket dos PDFs, com:
  - credencial própria, com permissão só nesse bucket;
  - **regra de lifecycle** para expirar os dumps antigos (ex.: 35 dias) — o
    script não apaga nada;
  - versionamento ou Object Lock, para que uma credencial vazada não consiga
    apagar o histórico.
- **Bucket dos PDFs** com versionamento ligado: é onde ficam os documentos
  assinados, e o backup do Postgres não os cobre.

## 2. Variáveis de ambiente

O `.env` do servidor é entregue inteiro ao web e ao sidekiq (`env_file`). O
`dotenv-rails` não carrega em produção — o que não estiver no `.env` ou no
compose não chega ao app.

Além das integrações descritas no [README](../README.md), produção exige:

| Variável | Para quê |
| --- | --- |
| `APP_HOST`, `APP_DOMAIN` | Host do painel e domínio base. Sem `APP_DOMAIN` o boot falha. |
| `SECRET_KEY_BASE` | Sessão e tokens. Gere com `openssl rand -hex 64`. |
| `POSTGRES_PASSWORD` | Sem default em produção. |
| `SIGNATURE_PROVIDER` | `eval_crypto_cubo` ou `icp_brasil`. `internal` é recusado no boot. |
| `LETSENCRYPT_EMAIL` | Avisos de expiração do certificado. |
| `BACKUP_S3_*`, `BACKUP_ENCRYPTION_PASSPHRASE` | Backup (seção 4). |

Variável obrigatória faltando faz o `docker compose` parar com a mensagem
`... é obrigatória em produção`, antes de subir qualquer container.

## 3. Primeiro deploy

```bash
# 1. Certificado — com o nginx PARADO (a emissão usa a porta 80).
#    Primeira tentativa contra o ambiente de teste do Let's Encrypt:
LETSENCRYPT_STAGING=true make prod-cert-init
#    Deu certo? Emita o real (o de teste não é confiável para o navegador):
docker volume rm prescsign_certbot_certs
make prod-cert-init

# 2. Stack completa
make prod-up-d

# 3. Conferência
curl -I http://app.prescsign.com.br/sign-in   # 301 para https
curl -I https://app.prescsign.com.br/up       # 200
make prod-backup-list                         # o backup do boot já deve estar lá
```

A renovação é automática: o serviço `certbot` tenta a cada 12h (só renova o
que vence em menos de 30 dias) e o nginx recarrega a cada 6h para pegar o
certificado novo.

> **Banco já existente:** se o volume `postgres_data` foi criado com a senha
> `postgres`, mudar `POSTGRES_PASSWORD` não muda a senha do banco — o Postgres
> só lê a variável na primeira inicialização. Troque com
> `ALTER USER postgres PASSWORD '...'` antes de subir com a nova.

## 4. Backup

**O que faz:** `pg_dump` em formato custom, criptografado com GPG (AES-256)
**no servidor**, enviado ao bucket e conferido pelo tamanho. Roda ao subir o
container e diariamente em `BACKUP_TIME_UTC` (default 06:00 UTC = 03:00 em
Brasília). O dump em claro nunca fica em disco depois do script.

**Por que criptografado no cliente:** o dump tem dado de saúde de paciente
(LGPD, art. 11). Vazamento do bucket ou da credencial de backup não pode
expor o conteúdo.

**A passphrase é o ponto único de falha.** Sem ela o backup é irrecuperável.
Guarde-a num cofre de senhas, fora deste servidor — se ela só existir no
`.env`, perder o servidor é perder o backup junto.

**Monitoramento:** o container `backup` fica `unhealthy` se o último backup
bem-sucedido tiver mais de 26h (`docker compose ps`). Falhas aparecem no log
como `backup: FALHOU`. **Não há alerta ativo** — alguém precisa olhar, ou é
preciso ligar esse healthcheck a um monitor externo.

### Restore

```bash
make prod-backup-list
make prod-restore key=postgres/prescsign_production_20261015T060000Z.dump.gpg db=restore_20261015
```

O restore **sempre cria um banco novo** e recusa o nome do banco em uso ou de
um banco que já existe. Ao final mostra a contagem de documentos e pacientes
para conferência. Trocar o banco de produção pelo restaurado é decisão humana,
feita depois de conferir — o script não faz isso.

**Teste o restore todo mês.** Backup que nunca foi restaurado é hipótese, não
backup. Restaure num banco novo, confira as contagens contra produção e apague
o banco de teste.

## 5. Limites conhecidos

- **Perda máxima de 24h (RPO).** É dump diário, não WAL contínuo. Reduzir isso
  exige arquivamento de WAL (ex.: `pgbackrest`/`wal-g`) ou Postgres gerenciado
  com PITR.
- **Servidor único.** Sem redundância: se o servidor cair, o sistema cai.
- **`RUN_DB_PREPARE=true`** roda as migrations no boot do web. Funciona com uma
  instância; com mais de uma, a migration precisa sair do boot.
