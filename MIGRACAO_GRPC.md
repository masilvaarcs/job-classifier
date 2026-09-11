# 🔌 Job Classifier — Migração REST → gRPC

> Registro técnico da migração da API REST (Express) para **gRPC/ConnectRPC**,
> e do **PostgreSQL** para o **MongoDB Atlas**. Este documento explica as decisões,
> a arquitetura nova e como evoluir os contratos.

---

## 📋 Resumo da mudança

| Antes | Depois |
|---|---|
| API REST (Express) na porta 8000 | Serviço **ConnectRPC** na porta 8000 (fala Connect, gRPC e gRPC-Web) |
| Frontend → REST via axios | Frontend → **cliente ConnectRPC tipado** (JSON sobre HTTP, proxy Vite) |
| Node → Python via HTTP (POST /api/importar etc.) | Node → Python via **gRPC nativo HTTP/2** (porta 8002) |
| PostgreSQL (job_vagas) | **MongoDB Atlas** (coleção `vagas`) — migração em andamento |

**Por que ConnectRPC?** Browsers não falam gRPC nativo (exige HTTP/2 trailers).
O ConnectRPC resolve isso com um protocolo JSON sobre HTTP/1.1 que funciona
direto no navegador **e** é compatível no fio com gRPC/gRPC-Web — o mesmo
servidor atende os três protocolos, sem proxy Envoy.

---

## 🏗️ Arquitetura nova

```
┌──────────────┐  Connect (JSON/HTTP)   ┌─────────────────────┐
│ React (5173) │ ─────────────────────▶ │ job-classifier-rpc  │──▶ MongoDB Atlas
│   Vite proxy │        /rpc/*          │  (Node, porta 8000) │
└──────────────┘                        │  VagaService        │
                                        └─────────┬───────────┘
                                                  │ gRPC nativo (HTTP/2)
                                                  ▼
                                        ┌─────────────────────┐
                                        │ job-classifier-python│
                                        │ ScrapingService     │
                                        │ (grpcio, porta 8002)│
                                        └─────────────────────┘
                                        FastAPI (HTTP 8001) fica
                                        para Swagger + export Excel
```

### Portas

| Serviço | Porta | Protocolo |
|---|---|---|
| `job-classifier-dotnet` (**primário**) | 8000 | gRPC + gRPC-Web (mesmos contratos proto) |
| `job-classifier-rpc` (arquivado) | — | Node/ConnectRPC — em `_archive/`, referência histórica |
| `job-classifier-python` (FastAPI) | 8001 | HTTP (Swagger, export Excel) |
| `job-classifier-python` (gRPC) | 8002 | gRPC nativo HTTP/2 (`job.v1.ScrapingService`) |
| Frontend Vite | 5173 | HTTP (proxy `/rpc` → 8000, `/dotnet` → 8010) |

---

## 📜 Contratos (fonte única de verdade)

Os contratos vivem na **raiz do monorepo**, pasta `proto/`:

```
proto/job/v1/
├── vagas.proto      # job.v1.VagaService (11 RPCs) + mensagens de domínio
└── scraping.proto   # job.v1.ScrapingService (StartScraping, GetStatus)
```

### Regras do projeto

1. **Toda mudança de contrato começa no `.proto`.** Depois rode na raiz:

   ```powershell
   npm run proto:all     # buf lint + buf generate
   ```

   Isso regenera:
   - `job-classifier-rpc/src/gen/job/v1/*_pb.ts` (servidor Node)
   - `job-classifier-react/src/gen/job/v1/*_pb.ts` (cliente browser)
   - `job-classifier-python/src/gen/job/v1/*_pb2*.py` (Python — usa grpcio-tools, ver abaixo)

2. **Versionamento por pacote**: evoluções incompatíveis criam `proto/job/v2/`,
   nunca quebram `v1` (buf lint + `breaking: FILE` protegem).

3. **Stubs Python** são gerados com grpcio-tools (não fazem parte do buf.gen.yaml):

   ```powershell
   cd job-classifier-python
   .\venv\Scripts\python.exe -m grpc_tools.protoc -I ..\proto `
     --python_out=src\gen --grpc_python_out=src\gen job/v1/vagas.proto job/v1/scraping.proto
   ```

### RPCs do `job.v1.VagaService`

| RPC | Equivalente REST antigo |
|---|---|
| `ListVagas` | `GET /api/vagas` |
| `UpdateVaga` | `PUT /api/vagas/:id/status` |
| `IgnorarVaga` | `POST /api/vagas/:id/ignorar` |
| `RestaurarVaga` | `POST /api/vagas/:id/restaurar` |
| `ToggleFavoritar` | `POST /api/vagas/:id/favoritar` |
| `RecalcularScores` | `POST /api/calcular-scores` |
| `GetStats` | `GET /api/stats` |
| `ListPlataformas` | `GET /api/plataformas` |
| `StartScraping` | `POST /api/buscar/todas` e `/buscar/:plataforma` |
| `GetScrapingStatus` | `GET /api/status` |
| `ImportVagas` | `POST /api/importar` |

### Decisão v1: filtros com strings de exibição

O frontend envia hoje `'🟢 Remoto'` e `'Pendente'` (strings de UI) e o serviço
mapeia para os valores do banco (`REMOTO`, `pendente`). Mantivemos isso no v1
para uma substituição 100% transparente do REST. **Com o MongoDB**, vale
migrar os filtros para enums proto (`TipoTrabalho`, `StatusUsuario`) —
quebrar a compatibilidade com o REST antigo deixa de ser um risco.

---

## 🧱 Estrutura do job-classifier-rpc

```
job-classifier-rpc/
├── src/
│   ├── gen/job/v1/          # ← gerado (buf), não editar
│   ├── db/mongodb.ts        # cliente MongoDB (driver oficial)
│   ├── services/
│   │   ├── vagaService.ts   # lógica de negócio (coleção `vagas`)
│   │   ├── scoreService.ts  # score de compatibilidade (porta do original)
│   │   └── scrapingClient.ts# cliente gRPC nativo → Python 8002
│   ├── routes.ts            # implementação do VagaService
│   ├── scripts/
│   │   └── migrate-pg-to-mongo.ts  # migração de dados
│   └── server.ts            # http server + connectNodeAdapter
├── .env.example
└── package.json             # npm run dev | migrate | typecheck
```

---

## 🖥️ Frontend (job-classifier-react)

- `src/services/api.ts` foi reescrito para **ConnectRPC**; as funções exportadas
  e suas assinaturas continuam as mesmas — **nenhum componente mudou**.
- Tipos proto (snake_case → camelCase no cliente) são convertidos em um único
  lugar: `api.ts`. Componentes continuam consumindo os tipos locais
  (`src/types/index.ts`).
- O proxy do Vite encaminha `/rpc/*` → `http://127.0.0.1:8000` (sem CORS em dev).
- `axios` foi removido das dependências.

---

## 🐍 Microserviço Python

- Novo `src/grpc_server.py`: serve `job.v1.ScrapingService` com **grpcio**
  na porta 8002 (thread pool, scraping em background threads — mesmo
  comportamento do BackgroundTasks do FastAPI).
- O FastAPI **não foi removido**: segue na 8001 para Swagger (`/docs`)
  e exportação Excel (download binário fica melhor em HTTP puro por ora).
- Dependências novas: `grpcio`, `grpcio-tools` (já em `requirements.txt`).

---

## 🗄️ MongoDB (migração do PostgreSQL)

- Novo serviço de dados: `job-classifier-rpc/src/db/mongodb.ts` + `vagaService.ts`.
- Coleção única **`vagas`** com documento espelhando a tabela `job_vagas`
  (mesmos nomes de campo snake_case, para portar a lógica sem surpresas).
- `id` numérico **preservado** (contador interno da aplicação; `link` segue
  como chave natural única).
- Índices criados pela migração: `link` único, `id` único, consultas por
  plataforma/data, score, status, ignorada, pra_mim.

### Como rodar a migração

```powershell
cd job-classifier-rpc
Copy-Item .env.example .env
# Preencha: MONGODB_URI, MONGODB_DB e PG_URL
npm run migrate
```

O script é **idempotente** (upsert por `link`) e cria os índices antes de migrar.

### Checklist pós-migração

- [ ] `npm run migrate` executou sem erros e reportou o total esperado
- [ ] Frontend lista vagas reais (`ListVagas` com dados)
- [ ] `GetStats` bate com o `COUNT(*)` do PostgreSQL
- [ ] Update de status/favoritar persiste (recarregue a página)
- [ ] Desligar o serviço REST antigo (`job-classifier-api`) do dia a dia

---

## 🧪 Como testar manualmente

```powershell
# Connect protocol (JSON sobre HTTP) — o que o browser usa
curl --header "Content-Type: application/json" --data "{\"filtros\":{\"page\":1,\"perPage\":5}}" http://localhost:8000/job.v1.VagaService/ListVagas

# gRPC-Web também funciona na mesma porta (testável via Postman/grpcurl)
```

---

## 🖥️ Serviço .NET primário (job-classifier-dotnet)

Implementação do **mesmo** `job.v1.VagaService` em ASP.NET Core (`Grpc.AspNetCore`),
codegen via `Grpc.Tools` direto de `../proto`, `MongoDB.Driver` e gRPC-Web nativo
(`Grpc.AspNetCore.Web`) — sem proxy Envoy. Serve de comparação de plataforma e
caminho de estudo para o mercado .NET:

- **Porta 8000 (primário)**, healthcheck `/healthz`, mesma coleção MongoDB.
- Paridade 1:1 validada (ListVagas, GetStats, ToggleFavoritar, canal → Python).
- Frontend já usa gRPC-Web por padrão (`createGrpcWebTransport` → proxy `/dotnet`).
- O serviço Node foi arquivado em `_archive/job-classifier-rpc` (referência histórica).
- Ferramentas de migração/dev-mongo extraídas para `job-classifier-tools`.
- Ver `job-classifier-dotnet/README.md` para o mapa de arquivos e próximos passos.

## 🗺️ Próximos passos sugeridos

1. **Filtros com enums proto** (após MongoDB estabilizar).
2. **Server-streaming no `GetScrapingStatus`** — progresso do scraping em tempo real.
3. **ConnectRPC interceptors** para logging/timeout padronizados.
4. **Buffer de compatibilidade**: `buf breaking` no CI contra o proto da main.
5. Aposentar o FastAPI transferindo exportação Excel para streaming RPC.
6. ~~Decidir o serviço primário~~ **Decidido (2026-09-11): .NET primário na 8000**;
   o contrato proto não mudou em nenhum cenário.
