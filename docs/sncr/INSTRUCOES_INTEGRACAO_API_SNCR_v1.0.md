# SNCR — Instruções de Integração da API (v1.0, jul/2026)

> Transcrição fiel do PDF **"Instruções de Integração API SNCR v1.0"** da Anvisa
> ("Instruções de apoio ao processo de integração — JUL/2026 — v1.0"). Fonte
> oficial: [Documentos do SNCR](https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/controlados/sncr/documentos-do-sncr).
>
> Copyright © 2026. Agência Nacional de Vigilância Sanitária (Anvisa). É
> permitida a reprodução parcial ou total desta obra, desde que citada a fonte.
>
> Complementa o [MANUAL_API_SNCR_1ed.md](MANUAL_API_SNCR_1ed.md) (contrato da
> API) com o **onboarding**: como o prescritor é cadastrado, se a plataforma
> precisa de credenciamento e o passo a passo de integração do frontend.

---

## 1. Apresentação

### 1.1. Objetivo da documentação

Apoiar usuários, desenvolvedores, analistas e demais profissionais de TI
interessados no uso do sistema SNCR e na integração de sistemas, servindo como
referência para a correta utilização dos recursos disponibilizados.

---

## 2. Cadastro de Prescritores

O sistema SNCR conta com um **fluxo de cadastro automatizado de prescritores**,
sendo necessário apenas **o acesso ao sistema uma vez**.

> O profissional deve possuir **inscrição ativa em conselho profissional (CFM,
> CFMV ou CFO)**.

Em virtude da necessidade dos dados do prescritor na base do SNCR para a
disponibilização de numerações via API, esse passo é **obrigatório para novos
usuários**.

### 2.1. Instruções para cadastro

1. Acesse a página **`https://sncr-treinamento.anvisa.gov.br/`**;
2. Clique em **"Entrar com gov.br"**;
3. Informe seu CPF;
4. Caso não possua conta ativa no **ambiente de testes do Gov.br**, será exibida
   a tela de criação de conta. Caso já possua, basta informar a senha;
5. Marque **"Li e estou de acordo com o Termo de Uso e Aviso de Privacidade"** e
   clique em **"Continuar"**;
6. Clique em **"Tentar de outra forma"**;
7. Na tela seguinte, marque as opções necessárias e clique em **"Continuar"**
   (dados de exemplo do ambiente de teste):
   - Primeiro nome da mãe: `MAMAE`
   - Mês de nascimento: `JANEIRO`
   - Dia de nascimento: `01`
   - Ano de nascimento: `1980`
8. Confirme os dados em **"Continuar"**;
9. Selecione a forma de ativação (e-mail ou SMS), preencha e clique em
   **"Continuar"** (se telefone, informe o DDD);
10. Digite o código de acesso recebido e clique em **"Continuar"**;
11. Cadastre uma senha (8–70 caracteres, com minúscula, maiúscula, número e
    símbolo) e clique em **"Continuar"** para finalizar;
12. **Desde que o profissional possua inscrição ativa em um dos conselhos
    consultados (CFM, CFMV ou CFO), o acesso ao SNCR é realizado com sucesso e o
    cadastro é concluído.** A partir daí a tela "Requisições de Numeração —
    Prescritor" exibe o saldo por tipo (NRA, NRB, NRB2, NRR, NRT) e o botão
    "Nova Solicitação de Numeração".

> **É este o passo que semeia o prescritor na base do SNCR.** Sem ele — ou com um
> CPF sem inscrição ativa em CFM/CFMV/CFO — a API de numeração retorna **404
> "Inscrição fornecida é diferente da autenticada"** (ver manual, 2.3.1.7/2.3.2.7).

---

## 3. Credenciamento de plataformas

**O credenciamento de plataformas não será necessário.** As validações do
profissional e, em breve, da organização mantenedora da plataforma de prescrição
eletrônica serão suficientes.

---

## 4. Passo a passo — Integração da API SNCR com login via Gov.br

### 4.1. Visão geral

Guia de como integrar seu frontend com a API SNCR usando autenticação via Gov.br.
O processo é simples e suporta qualquer domínio `.br`.

### 4.2. Preparação do frontend

**Pré-requisitos:**

- Frontend em qualquer tecnologia (Angular, React, Vue, etc.);
- Acesso à API SNCR (ex.: `https://sncr-api.apps.anvisa.gov.br`).

```js
// Exemplo em Angular
const API_URL = 'https://sncr-api.apps.anvisa.gov.br';
```

### 4.3. Redirecionar para login

Quando o usuário clicar em "Entrar":

```js
function fazerLogin() {
  const clientUrl = window.location.origin + window.location.pathname;
  const loginUrl =
    `${API_URL}/api/v1/auth/login?client_url=${encodeURIComponent(clientUrl)}`;
  window.location.href = loginUrl;
}
```

> **Importante:** o parâmetro `client_url` deve ser a URL completa do frontend
> para onde o usuário será redirecionado após a autenticação.

### 4.4. Processar callback

Ao retornar da autenticação (URL com `?session_id=xxx`):

```js
async function processarCallback() {
  const sessionId = new URLSearchParams(window.location.search).get('session_id');

  if (sessionId) {
    const response = await fetch(
      `${API_URL}/api/v1/auth/token?session_id=${sessionId}`
    );
    if (response.ok) {
      const data = await response.json();
      // Salva o token (localStorage, sessionStorage, etc.)
      localStorage.setItem('auth_token', data.access_token);
      // Remove session_id da URL
      window.history.replaceState({}, document.title, window.location.pathname);
      return true;
    }
  }
  return false;
}
```

### 4.5. Enviar token nas requisições

Para acessar endpoints protegidos, envie o token no header:

```js
function fazerRequisicaoProtegida() {
  const token = localStorage.getItem('auth_token');

  if (!token) {
    fazerLogin(); // Redireciona para login
    return;
  }

  fetch(`${API_URL}/api/v1/receita-branca/`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      conselho: 'CRM',
      tipo: 'RET',
      documento: '67665',
      uf: 'SP',
      cnpj: '11111111000221'
    })
  })
    .then(response => {
      if (response.status === 401) {
        // Token expirado, limpar e redirecionar
        localStorage.removeItem('auth_token');
        fazerLogin();
        return;
      }
      return response.json();
    })
    .then(data => {
      console.log(data); // Processa resposta
    });
}
```

> ⚠️ **Discrepância entre os docs oficiais (verificar no Swagger).** O exemplo
> 4.5 usa o path **`POST /api/v1/receita-branca/`** com o corpo
> `{conselho, tipo, documento, uf, cnpj}`. Já o **Manual da API** (2.3.2.1)
> documenta o mesmo corpo em **`POST /numeracoes/receita-especial-retencao`**.
> Nosso client ([Sncr::Client](../../app/services/sncr/client.rb)) segue o
> **manual** (`/numeracoes/...`). O `/receita-branca/` parece ser um path
> ilustrativo/legado deste guia. Confirmar o path correto no
> [Swagger de homologação](https://sncr-api.hmg.apps.anvisa.gov.br/swagger-ui/index.html#/)
> antes de tratar como bug.

### 4.6. Verificar autenticação

```ts
function isAutenticado(): boolean {
  const token = localStorage.getItem('auth_token');
  if (!token) return false;

  // Verifica expiração do JWT
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    return payload.exp * 1000 > Date.now();
  } catch {
    return false;
  }
}
```

### 4.7. Fluxo resumido

1. Usuário → clica "Entrar";
2. Frontend → redireciona para `/auth/login?client_url=SEU_SITE`;
3. Backend → redireciona para o Gov.br;
4. Usuário → faz login no Gov.br;
5. Backend → redireciona para `SEU_SITE?session_id=xxx`;
6. Frontend → pega `session_id` e faz `GET /auth/token?session_id=xxx`;
7. Frontend → salva o token retornado;
8. Frontend → usa o token em todas as requisições (`Authorization: Bearer token`).

### 4.8. Lista de verificação para integração

- [ ] Configurar a URL da API no frontend;
- [ ] Implementar redirecionamento com `client_url`;
- [ ] Implementar processamento do callback com `session_id`;
- [ ] Implementar armazenamento do token;
- [ ] Adicionar o token no header `Authorization` de todas as requisições;
- [ ] Tratar token expirado (401);
- [ ] Implementar limpeza de sessão no logout;
- [ ] Implementar verificação de autenticação.

### 4.9. Dicas importantes

- **Cross-Domain:** a API suporta CORS, então o frontend pode estar em qualquer
  domínio `.br`;
- **Segurança:** armazene o JWT de forma segura (prefira `sessionStorage` a
  `localStorage`);
- **Session ID:** use apenas uma vez; sempre troque pelo token imediatamente;
- **Expiração:** o token tem validade — verifique e renove quando necessário;
- **Erro 401:** sempre redirecione para o login ao receber esse erro.

---

## Observações de leitura (não fazem parte do documento)

- **Ambiente de treinamento:** `https://sncr-treinamento.anvisa.gov.br/` (front do
  SNCR) — diferente do host da API do manual (`sncr-api.hmg.apps.anvisa.gov.br`).
- **Como obter um "prescritor de teste":** não se cria um manualmente. Acessa-se
  o SNCR de treinamento **uma vez** via Gov.br (conta do ambiente de testes); se
  o CPF tiver inscrição ativa em CFM/CFMV/CFO, o cadastro é automático e a API
  passa a liberar numeração. O 404 que vínhamos vendo era exatamente a ausência
  desse cadastro/inscrição.
- **Credenciamento da plataforma (PrescSign):** não é necessário (seção 3).
- **Base URL de produção** aparece como `https://sncr-api.apps.anvisa.gov.br`
  (sem `hmg`) — homologação segue `sncr-api.hmg.apps.anvisa.gov.br`.
