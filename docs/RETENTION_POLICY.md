# Política de Retenção (MVP)

Este documento define a política operacional de retenção de dados e arquivos do PrescSign no MVP.

## Objetivo

- Reduzir acúmulo de dados não essenciais para operação diária.
- Manter rastreabilidade e evidências do ciclo documental.
- Preparar base para automação de limpeza por job agendado.

## Escopo

A política cobre:

- versões de documentos (`document_versions`) e PDFs associados (`Active Storage`);
- logs de auditoria (`audit_logs`);
- logs de entrega (`delivery_logs`);
- arquivos temporários locais (`tmp/`);
- blobs órfãos do Active Storage (sem attachment).

## Regras Padrão (MVP)

As janelas abaixo são valores padrão e podem ser alteradas por variável de ambiente:

| Categoria | Janela padrão | Variável |
| --- | --- | --- |
| Versões de documentos + PDFs | Permanente | `RETENTION_DOCUMENT_VERSIONS_DAYS=permanent` |
| Logs de auditoria | 2190 dias (6 anos) | `RETENTION_AUDIT_LOGS_DAYS` |
| Logs de entrega | 1825 dias (5 anos) | `RETENTION_DELIVERY_LOGS_DAYS` |
| Arquivos temporários (`tmp/`) | 7 dias | `RETENTION_TMP_FILES_DAYS` |
| Blobs sem vínculo (unattached) | 2 dias | `RETENTION_UNATTACHED_BLOBS_DAYS` |

## Execução

Desde 10/09/2026 a política tem implementação: `Retention::CleanupService`,
acionável por `RetentionCleanupJob` ou pela rake task.

```bash
bin/rails retention:cleanup           # simula e relata, sem remover nada
bin/rails retention:cleanup APPLY=1   # remove
```

**Nada roda sozinho, de propósito.** Não há agendador no projeto e o job não se
reenfileira. Simular é o padrão nos dois pontos de entrada — o `APPLY=1` da rake
e o `dry_run: false` do job são atos deliberados. O motivo está nas
pré-condições logo abaixo: enquanto a estratégia de backup/restore for pendência
aberta (seção 4 de [PENDENCIAS.md](PENDENCIAS.md)), uma limpeza agendada apaga
sem rede de segurança.

O que a varredura cobre, e o que não cobre:

| Categoria | Como remove |
| --- | --- |
| `audit_logs`, `delivery_logs` | `delete_all` em lotes de 1.000, recortado pela janela |
| Blobs sem vínculo | `purge`, que remove o registro **e** o arquivo no storage |
| `tmp/` | só arquivos no topo, fora da janela |
| Versões de documento + PDFs | **nunca** — ver abaixo |

**Versões de documento nunca são removidas.** `DocumentVersion` tem
`before_destroy :prevent_destroy` e a política as trata como permanentes; um
`delete_all` passaria por cima dessa guarda em silêncio. O serviço não as
varre, reporta `0` e registra `document_versions_policy: "permanent"` no log,
para que o zero não seja lido como "não havia nada".

**Consequência:** `RETENTION_DOCUMENT_VERSIONS_DAYS` com um número de dias não
tem efeito nenhum. Em produção o boot já exige `permanent`; fora dela, a
variável é aceita e ignorada. Resolver essa inconsistência — remover a variável
ou dar sentido a ela — está fora do escopo de quem só implementou a política.

Em `tmp/` a varredura é deliberadamente rasa: não desce em subdiretório
(`cache/`, `pids/`, `sockets/`, `storage/` são do framework) e preserva
`.keep`, `local_secret.txt` e `restart.txt`.

## Diretrizes de Aplicação

- Limpeza deve ser executada por job assíncrono e idempotente.
- Documentos e PDFs versionados não devem ser removidos automaticamente.
- Exclusão deve ocorrer apenas para registros/blobs fora da janela configurada.
- Operações devem gerar log técnico com quantidade removida por categoria.
- Antes de ativar limpeza em produção:
  - validar com time jurídico/compliance;
  - validar impacto em auditoria e suporte;
  - definir estratégia de backup/restore.

## Observações

- Esta política é operacional do MVP e não substitui avaliação legal/regulatória.
- Valores podem ser endurecidos por organização/ambiente conforme contrato e compliance.
- Em `production`, o app valida no boot:
  - `RETENTION_DOCUMENT_VERSIONS_DAYS` deve permanecer como `permanent`;
  - logs (`audit` e `delivery`) devem ter no mínimo 1825 dias (5 anos).
