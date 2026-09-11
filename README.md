# 🎯 Job Classifier — Workspace Raiz

> Plataforma pessoal de **coleta, classificação e gestão de vagas de emprego**: scrapers multi-plataforma
> (LinkedIn, Indeed, Glassdoor, Jooble, BNE), dashboard React, scoring de compatibilidade e exportação Excel —
> arquitetura **contract-first com gRPC** e **MongoDB**.

[![.NET 10](https://img.shields.io/badge/.NET-10-512BD4?logo=dotnet)](https://dotnet.microsoft.com)
[![Python 3.11](https://img.shields.io/badge/Python-3.11-3776AB?logo=python)](https://www.python.org)
[![React 19](https://img.shields.io/badge/React-19-61DAFB?logo=react)](https://react.dev)
[![gRPC](https://img.shields.io/badge/gRPC-+_gRPC--Web-244C5A?logo=data:image/svg%2Bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PGNpcmNsZSBjeD0iMTIiIGN5PSIxMiIgcj0iMTAiIGZpbGw9IiMyNDRDNUEiLz48L3N2Zz4=)](https://grpc.io)
[![MongoDB](https://img.shields.io/badge/MongoDB-Atlas-47A248?logo=mongodb)](https://www.mongodb.com/atlas)

---

## 📖 Visão geral

Este repositório é o **workspace raiz**: guarda a **fonte única de verdade dos contratos**
(`proto/job/v1/*.proto`), a configuração de codegen ([Buf](https://buf.build)), a documentação
de arquitetura/migrações e os scripts de orquestração (launcher, stop, atalho da área de trabalho).

Cada serviço vive em **repositório próprio** (tabela abaixo) e consome os mesmos contratos —
mudar a linguagem de um serviço **não quebra os demais**: o `.proto` é a fronteira.

**Fluxo principal:** o navegador (React) fala **gRPC-Web** com o serviço **.NET** (porta 8000),
que consulta o **MongoDB** e repassa operações de scraping ao microserviço **Python** (gRPC nativo, 8002).

---

## 🗂️ Repositórios

| Repo | Papel | Porta |
|---|---|---|
| **[job-classifier-dotnet](https://github.com/masilvaarcs/job-classifier-dotnet)** | ⭐ **Serviço primário** — ASP.NET Core, `job.v1.VagaService` (11 RPCs), gRPC + gRPC-Web, MongoDB.Driver | 8000 |
| **[job-classifier-python](https://github.com/masilvaarcs/job-classifier-python)** | Scraping multi-plataforma — `job.v1.ScrapingService` (grpcio) + FastAPI (Swagger/Excel) | 8002 / 8001 |
| **[job-classifier-react](https://github.com/masilvaarcs/job-classifier-react)** | Frontend — React 19 + Vite + Connect (gRPC-Web) | 5173 |
| **[job-classifier-tools](https://github.com/masilvaarcs/job-classifier-tools)** | Migração PG→MongoDB (`npm run migrate`) e Mongo local efêmero (`npm run dev:mongo`) | 57010 |
| **[job-classifier-api](https://github.com/masilvaarcs/job-classifier-api)** | ⚠️ **LEGADO** — API REST/Express original (fora do fluxo ativo) | — |

> O serviço Node/ConnectRPC que substituiu a REST foi por sua vez arquivado em
> [`_archive/job-classifier-rpc/`](./_archive/job-classifier-rpc) neste workspace (referência histórica).

---

## 🗺️ Arquitetura

![Diagrama de arquitetura do Job Classifier](ARQUITETURA.png)

- Documentação completa: [ARQUITETURA.md](ARQUITETURA.md)
- Fonte editável do diagrama: [ARQUITETURA.MMD](ARQUITETURA.MMD) (Mermaid — renderiza no GitHub, VS Code, Obsidian)

```mermaid
flowchart LR
    subgraph Browser
        UI["React + Vite :5173"]
    end
    subgraph "Serviço primário"
        VAGA["job-classifier-dotnet :8000<br/>job.v1.VagaService (gRPC-Web)"]
    end
    subgraph "Python"
        SCRAP["ScrapingService :8002 (gRPC)"]
        FAST["FastAPI :8001 (Excel)"]
    end
    DB[("MongoDB<br/>job_tracker.vagas")]
    UI -- "gRPC-Web · proxy /dotnet" --> VAGA
    UI -- "HTTP /exportar" --> FAST
    VAGA --> DB
    VAGA -- "gRPC nativo" --> SCRAP
```

---

## 🔌 Portas

| Porta | Serviço | Verificação |
|---|---|---|
| **8000** | .NET — gRPC-Web + `/healthz` (HTTP/1.1, caminho do navegador) | `GET http://localhost:8000/healthz` |
| **8003** | .NET — **gRPC nativo** (h2c/HTTP/2, para grpcurl e backends) | `grpcurl -plaintext localhost:8003 job.v1.VagaService/GetStats` |
| **8001** | Python FastAPI (Swagger/Excel) | `GET http://localhost:8001/health` |
| **8002** | Python gRPC (`ScrapingService`) | via cliente gRPC |
| **5173** | Frontend (Vite) | abrir no navegador |
| **57010** | MongoDB local dev (fallback sem Atlas) | launcher sobe automaticamente |

> **Por que 8000 e 8003 separados?** gRPC exige HTTP/2; browsers só negociam HTTP/2 com TLS (ALPN).
> Por isso o navegador usa **gRPC-Web sobre HTTP/1.1** (porta 8000) e o gRPC nativo fica na 8003
> (h2c — HTTP/2 em texto claro, sem certificado local). Decisão completa e racional em
> [job-classifier-dotnet/README.md → "Decisão de protocolos"](job-classifier-dotnet/README.md).

---

## 🚀 Quick start (com o launcher)

### Pré-requisitos
- **.NET SDK 10** · **Node 20+** · **Python 3.11+** · **Git**
- *(Opcional)* Credenciais do MongoDB Atlas no `.env` — sem elas, o launcher sobe um MongoDB local automaticamente

### Passos

```powershell
# 1. Clone o workspace e os serviços lado a lado
git clone https://github.com/masilvaarcs/job-classifier.git
cd job-classifier
git clone https://github.com/masilvaarcs/job-classifier-dotnet.git
git clone https://github.com/masilvaarcs/job-classifier-python.git
git clone https://github.com/masilvaarcs/job-classifier-react.git
git clone https://github.com/masilvaarcs/job-classifier-tools.git   # opcional (migração de dados)

# 2. Configure o banco (opcional — sem isso usa Mongo local efêmero)
#    job-classifier-dotnet/.env  →  MONGODB_URI=mongodb+srv://usuario:senha@...  +  MONGODB_DB=job_tracker

# 3. Crie o atalho da área de trabalho (uma vez) ou rode direto:
powershell -ExecutionPolicy Bypass -File .\create-shortcut.ps1
powershell -ExecutionPolicy Bypass -File .\start-job-classifier.ps1
```

O launcher: **[1/4]** resolve o MongoDB (Atlas ou local) → **[2/4]** compila/sobe o .NET (8000)
→ **[3/4]** sobe Python gRPC (8002) + FastAPI (8001) → **[4/4]** abre o frontend (5173) no navegador.
Idempotente: rodar de novo não duplica nada. Para encerrar tudo: `stop-job-classifier.ps1`.

> 📚 Passo a passo manual detalhado: [COMO_SUBIR_O_PROJETO.md](COMO_SUBIR_O_PROJETO.md)

---

## 📚 Documentação

| Documento | Conteúdo |
|---|---|
| [ARQUITETURA.md](ARQUITETURA.md) | Arquitetura atual, fluxos de dados, responsabilidades por serviço |
| [job-classifier-dotnet/README.md](job-classifier-dotnet/README.md) | Decisão de protocolos (HTTP/1.1 vs h2c, TLS/ALPN) e detalhes do serviço primário |
| [COMO_SUBIR_O_PROJETO.md](COMO_SUBIR_O_PROJETO.md) | Operação manual completa, serviço por serviço |
| [MIGRACAO_GRPC.md](MIGRACAO_GRPC.md) | Migração REST → gRPC/ConnectRPC → .NET primário (decisões e contratos) |
| [MIGRACAO_MONGODB.md](MIGRACAO_MONGODB.md) | Migração PostgreSQL → MongoDB Atlas (procedimento e status) |
| [featureArquitetura.md](featureArquitetura.md) | Estudo de viabilidade: 100% Cloudflare (híbrido gratuito) |

---

## 🔐 Segurança

- **Nenhum segredo é versionado** — `.env`, `MongoDB_Chaves/`, chaves e URIs com credenciais ficam
  fora do git (`.gitignore` da raiz e de cada serviço). Commits passam por gitleaks (hook local).
- Contratos proto mudam apenas via PR no `proto/job/v1` + `npm run proto:all` (lint + codegen).
