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
