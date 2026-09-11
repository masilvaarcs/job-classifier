# ☁️ featureArquitetura — Job Classifier 100% na nuvem via Cloudflare?

> **Estudo de viabilidade (2026-09-11) — nada foi implementado.**
> Objetivo declarado: deixar o projeto **funcionando independente de máquina**, na nuvem, **sem custos**.
> Pergunta central: dá para colocar tudo na Cloudflare? Se não, o que entra, o que fica de fora e por quê.

---

## 1. Resumo executivo (veredito curto)

| Pergunta | Resposta |
|---|---|
| Dá para colocar **o frontend** na Cloudflare de graça? | ✅ **Sim, perfeitamente** (Cloudflare Pages, plano free) |
| Dá para colocar **a API (.NET gRPC)** de graça? | ⚠️ **Não nativamente.** Workers não roda ASP.NET/gRPC server; Containers exige plano pago (US$ 5/mês) |
| Dá para colocar **o scraper Python** de graça? | ❌ **Não na Cloudflare.** Workload de longa duração + I/O intensivo; qualquer caminho free é uma gambiarra frágil |
| E o **MongoDB**? | ⚠️ Atlas M0 é grátis e roda na nuvem (não é Cloudflare, mas resolve o banco); o driver oficial **não conecta de Workers** |
| **Veredito** | **Híbrido**: Pages (frontend) + Workers (proxy/BFF, opcional) na Cloudflare **de graça**; o backend gRPC precisa de outra casa free (Fly.io / Railway / Oracle Cloud Always Free) + Atlas M0 |

Ou seja: **"tudo dentro da Cloudflare e de graça" não é possível com a arquitetura atual** — o gargalo não é o frontend, é o **backend gRPC de longa duração** e o **modelo de runtime** da Cloudflare. O documento abaixo explica o porquê e propõe caminhos.

---

## 2. Inventário atual — o que precisa "morar" em algum lugar

| Componente | Tecnologia | Como roda hoje (máquina local) | Perfil de runtime |
|---|---|---|---|
| `job-classifier-react` | React 19 + Vite | `npm run dev` (:5173) | **Static build** — ideal para CDN |
| `job-classifier-dotnet` | ASP.NET Core 10, gRPC + gRPC-Web, `:8000` | `dotnet run` | **Servidor HTTP/2 de longa duração** |
| `job-classifier-python` (gRPC) | grpcio, `:8002` | venv + `python -m src.grpc_server` | **Processo residente**, threads de scraping em background |
| `job-classifier-python` (FastAPI) | FastAPI, `:8001` | uvicorn --reload | HTTP curto, mas **Estado em memória** (dados do scraper) |
| MongoDB | Atlas M0 (planejado) / local efêmero | `mongod` na 57010 | Gerenciado (Atlas) — não é Cloudflare |
| `job-classifier-tools` | Node + tsx | one-off | Migração de dados — roda de qualquer máquina |
| PostgreSQL | serviço Windows | 5432 | **Legado** — pode ficar para trás após migração final |

---

## 3. Por que "tudo na Cloudflare" esbarra em limites reais (fatos apurados)

### 3.1 Workers não é um servidor tradicional — e gRPC server não entra

- **Workers Free**: 100.000 requests/dia e **10 ms de CPU por invocação**. Nosso `.NET` serve gRPC + gRPC-Web e faz agregações no Mongo — perfil de servidor, não de função.
- **gRPC server não é suportado no Workers.** O runtime fala HTTP/1.1 e HTTP/2 **server** para fetch, mas não expõe gRPC (trailers, framing). Client gRPC *de* Workers é possível; *servir* gRPC, não.
- O runtime é V8-isolate (tipo o navegador), **não .NET nem CPython**. ASP.NET Core e grpcio não rodam lá — seria reescrever a lógica em TypeScript/JS.

### 3.2 MongoDB a partir de Workers: caminho oficial foi descontinuado

- O driver MongoDB precisa de **TCP+TLS de longa duração**; Workers não expõe sockets TCP arbitrários.
- A solução oficial de anos atrás era o **Atlas Data API (HTTPS)** — o **MongoDB descontinuou o produto** (vigência encerrada em 2025/2026). Os fóruns oficiais da MongoDB e da Cloudflare confirmam que a integração "oficial" ficou sem caminho suportado.
- Existe o `nodejs_compat` (com `node:net`/`node:tls` desde 2025), mas relatos práticos indicam que **o driver oficial ainda não funciona de forma confiável dentro do Workers** (handshake SCRAM, timeouts, dependências nativas).
- Consequência: mesmo reescrevendo o backend em TS, o **acesso ao Atlas a partir da Cloudflare é terreno instável** hoje.

### 3.3 Containers (a resposta "oficial" para backends) é paga

- **Cloudflare Containers** (GA 2025) roda imagens OCI — inclusive nosso .NET e o Python. Porém:
  - Requer **Workers Paid (US$ 5/mês)** como pré-requisito;
  - Cobra por **GiB-horas/vCPU** além da franquia;
  - Nosso perfil (processo residente + scraping de minutos) faturaria acima da franquia.
- Conclusão: **Containers quebra a restrição "sem custos"**.

### 3.4 O que é de graça e serve

| Serviço CF | Free tier | Serve para |
|---|---|---|
| **Pages** | Builds ilimitados, banda e requests generosos, domínio `*.pages.dev` | ✅ Frontend React — caso de uso perfeito |
| **Workers Free** | 100k req/dia, 10ms CPU | ⚠️ BFF/proxy leve, CORS, rate-limit, health agregado — **não** para lógica de negócio |
| **Cron Triggers** | 3 crons/Worker (free) | ⚠️ Agendar chamadas HTTP (ex.: disparar scrape num backend externo) |
| **KV** | 100k leituras/dia, 1k escritas/dia | ⚠️ Cache/flags — **não** substitui o Mongo |
| **D1** (SQLite) | Limites diários de rows lidas/escritas | ❌ Seria trocar o Mongo por SQLite — outro projeto |
| **R2** | 10 GB | ⚠️ Guardar exports Excel, backups de coleção |
| **Queues/DOs** | DO free desde 2025, Queues pago | ⚠️ Futuro: fila de scraping **se** backend existir fora |

---

## 4. Opções de arquitetura (com custos e trade-offs)

### Opção A — "Cloudflare-first parcial" (100% free) ⭐ recomendada como 1º passo

```
┌─────────────────────────── Cloudflare (free) ───────────────────────────┐
│  Pages: frontend React (build do Vite)                                  │
│  Worker "bff": gRPC-Web ⇄ fetch para o backend externo, CORS, cache KV  │
└─────────────────────────────────────────────────────────────────────────┘
                 │ (HTTPS público)
                 ▼
┌──────────────────────── Fora da Cloudflare (free) ──────────────────────┐
│  Backend .NET gRPC :8000        → Fly.io / Railway / Oracle Always Free │
│  Microserviço Python (gRPC+HTTP) → idem (mesma máquina ou outra)        │
│  MongoDB Atlas M0               → nuvem MongoDB (não CF), free          │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Frontend**: Pages serve o `dist/` do Vite. O app React passa a chamar `https://api.seudominio/pages-dev...` (variável de ambiente de build).
- **Backend**: o `job-classifier-dotnet` e o `job-classifier-python` rodam num único serviço free que aceita **processos de longa duração**:
  - **Fly.io** (free legacy limitado; hoje ≈ 3 VMs shared-cpu-1x de 256 MB — comporta os dois serviços),
  - **Railway** (trial/credit — não é free para sempre),
  - **Oracle Cloud Always Free** (ARM Ampere 4 OCPU/24 GB — o mais generoso, exige cartão para verificação),
  - alternativa: um VPS barato.
- **Prós**: 100% free, independente da sua máquina, **zero reescrita** (o .NET e o Python seguem como estão), proto e contratos intactos.
- **Contras**: o backend fica fora da Cloudflare (o objetivo "tudo dentro da CF" cai por terra); free tiers de terceiros mudam de regra; a máquina local deixa de ser necessária, mas a operação passa por `flyctl`/`wrangler` etc.

### Opção B — "Cloudflare total, reescrevendo o backend" (100% CF, free… com asteriscos)

Reescrever o `VagaService` em **TypeScript para Workers** e trocar o Mongo por **D1/KV/R2**:

- **O que se ganha**: tudo dentro da CF, escala automático, custo zero.
- **O que se perde / custo real**:
  - Reescrever 11 RPCs + score + importação em TS para Workers;
  - **Scraping de minutos não cabe nos 10 ms de CPU** — teria que virar fila + cron + Durable Objects (complexidade alta);
  - D1 = SQLite (SQL, não Mongo) → remodelar dados e índices; KV não serve para consultas;
  - Python desaparece (FastAPI/Excel precisariam de substitutos em JS ou serviço externo);
  - gRPC para o frontend teria que virar Connect-Web puro (JSON) — o contrato muda de forma, não de nome.
- **Veredito**: viável como projeto de aprendizado avançado; **inviável como "mudança pequena"** e perde o objetivo de estudar **.NET + gRPC**.

### Opção C — "Cloudflare total com Containers" (US$ 5/mês + consumo)

- Manter o .NET e o Python como estão, em imagens Docker no **Cloudflare Containers**.
- **Prós**: tudo dentro da CF, DNS/CDN/TLS unificados, o código atual roda sem reescrita.
- **Contras**: **não é de graça** (US$ 5/mês fixo + GiB-horas), e o scraper residente consome franquia rapidamente.
- **Veredito**: a escolha mais "correta" tecnicamente dentro da CF, mas **viola a restrição de custo**.

### Opção D — "local + túnel" (free, mas não é nuvem)

- **Cloudflare Tunnel** (`cloudflared`) expõe o backend da sua máquina para a internet, free, sem abrir portas.
- **Prós**: zero custo, zero mudança de código, HTTPS e domínio da CF.
- **Contras**: **depende da sua máquina ligada** — contradiz o objetivo "independente de máquina". Serve como ponte temporária enquanto o Opção A não sai.

---

## 5. Comparativo resumido

| Critério | A (híbrido free) | B (100% CF, reescrita) | C (CF + Containers) | D (Tunnel) |
|---|---|---|---|---|
| Custo mensal | **R$ 0** | **R$ 0** | US$ 5+ | R$ 0 |
| Independente da sua máquina | ✅ | ✅ | ✅ | ❌ |
| Reescrita de código | ❌ nenhuma | 🔴 total (TS/D1) | ❌ nenhuma | ❌ nenhuma |
| Mantém gRPC/.NET/Python (objetivo de estudo) | ✅ | ❌ | ✅ | ✅ |
| Tudo "dentro" da Cloudflare | ❌ só front | ✅ | ✅ | ⚠️ domínio sim, runtime não |
| Complexidade de implantação | média | alta | média | baixíssima |
| Risco de free tier mudar regra | médio (Fly/Oracle) | baixo | baixo | baixo |
| Veredito | **recomendada** | não recomendada agora | se o custo for aceito | ponte temporária |

---

## 6. Roteiro de mudanças (Opção A, quando aprovada)

### Fase 0 — Pré-requisitos (fora de código)
1. Concluir a migração para o **Atlas M0** (pendência atual) — sem banco na nuvem, nada mais importa.
2. Criar conta/repo no GitHub para CI (Pages deploya do repo).

### Fase 1 — Frontend na Cloudflare (1 dia)
1. `npm run build` no `job-classifier-react` → `dist/`.
2. Criar projeto **Pages**, conectar ao repo, build command `npm run build`, output `dist`.
3. Variável de ambiente de build: `VITE_API_BASE=https://<backend>.fly.dev` (ou similar).
4. **Mudança no código**: `api.ts` passa a montar o transport com `import.meta.env.VITE_API_BASE` (fallback `/dotnet` para dev local). Única mudança de código real deste fase.
5. O Worker "bff" é **opcional** — o gRPC-Web do navegador pode ir direto ao backend se ele liberar CORS.

### Fase 2 — Backend num free tier que aceita servidores (1–2 dias)
1. `Dockerfile` para o .NET (multi-stage, `mcr.microsoft.com/dotnet/aspnet:10.0`).
2. `Dockerfile` ou `fly.toml` para o Python (ou juntar os dois numa VM com `supervisor`).
3. Deploy no Fly.io/Oracle; variáveis: `MONGODB_URI`, `PYTHON_GRPC_URL`, `PORT`.
4. **Mudança no código**: nenhuma. Apenas config.
5. Habilitar **CORS** no .NET para o domínio do Pages (`Grpc.AspNetCore.Web` + headers).

### Fase 3 — Endurecimento (1 dia)
1. HTTPS/TLS nos endpoints públicos (CF proxy + cert no backend).
2. **Autenticação simples** no backend (API key ou OAuth) — hoje é tudo aberto; na internet isso vira porta aberta.
3. Rate-limit no Worker/Pages Function.
4. Monitoramento: healthcheck externo (ex.: UptimeRobot free) + logs do `dotnet`.

### Fase 4 — Migração de dados e corte (0,5 dia)
1. `npm run migrate` (tools) apontando para o Atlas — os 4.109 docs sobem de uma vez.
2. Desligar o PostgreSQL da equação (mantê-lo só como backup congelado).

### O que NÃO muda
- Contratos `proto/job/v1` (fonte da verdade);
- Lógica de score, filtros, importação;
- O modelo mental: front → gRPC-Web → .NET → Mongo; .NET → gRPC → Python.

---

## 7. Riscos e limitações a documentar

1. **Free tiers são contratos de uma linha** — Fly.io já mudou o plano free; Railway saiu do free; Oracle pode restringir. Mitigação: arquitetura Docker-first permite trocar de provedor em horas.
2. **Scraping de plataformas** (LinkedIn etc.) de IPs de nuvem sofre bloqueio/banimento com mais frequência que IP residencial. É o maior risco **operacional** de rodar o scraper na nuvem.
3. **gRPC-Web no navegador via Pages**: o proxy do Vite deixa de existir em produção; o backend precisa de CORS corretamente configurado (ou um Worker BFF).
4. **Segredo no cliente**: nada de credenciais no bundle do React; só no backend.
5. **10 ms de CPU** do Workers free inviabiliza qualquer lógica pesada — manter o backend longe do Workers.
6. **Dependência de dois provedores** (CF + provedor de backend + Atlas) — documentar credenciais no vault e ter `docker compose` local como fallback.

---

## 8. Recomendação final

1. **Curto prazo**: Opção A — Pages (frontend) + backend free (Fly/Oracle) + Atlas M0. Cumpre "na nuvem, sem custo, independente de máquina" com **zero reescrita** e mantém o objetivo didático (.NET + gRPC + Python).
2. **Se um dia aceitar US$ 5/mês**: Opção C (Containers) unifica tudo na Cloudflare sem reescrever nada.
3. **Nunca como objetivo**: Opção B (reescrever em Workers/D1) — só como exercício avançado de aprendizado, desacoplado deste projeto.
4. **Enquanto isso**: Opção D (Tunnel) resolve o "mostrar para alguém de fora" hoje, de graça, sem deployment.

> 💡 Este documento é um estudo. Nenhum arquivo do projeto foi alterado além dele mesmo.
