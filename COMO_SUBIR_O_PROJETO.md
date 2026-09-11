# 🚀 Job Classifier — Como subir o projeto manualmente

> Guia passo a passo para colocar todos os serviços no ar **manualmente**, sem usar o atalho da área de trabalho.
>
> 📌 **Arquitetura atual: gRPC/ConnectRPC + MongoDB Atlas.**
> Detalhes técnicos: [MIGRACAO_GRPC.md](MIGRACAO_GRPC.md) · [MIGRACAO_MONGODB.md](MIGRACAO_MONGODB.md)
> A antiga API REST (`job-classifier-api`) foi substituída pelo serviço RPC e não é mais necessária.

---

## 📋 Visão geral

O projeto é composto por **4 serviços** (mais o MongoDB):

| Serviço | Pasta | Tecnologia | Porta |
|---|---|---|---|
| **Serviço RPC (.NET, primário)** | `job-classifier-dotnet` | ASP.NET Core + Grpc.AspNetCore | **8000** (gRPC-Web) + **8003** (gRPC nativo h2c) |
| **Microserviço Python (HTTP)** | `job-classifier-python` | Python + FastAPI (Swagger/Excel) | **8001** |
| **Microserviço Python (gRPC)** | `job-classifier-python` | Python + grpcio (ScrapingService) | **8002** |
| **Frontend** | `job-classifier-react` | React 19 + Vite + TypeScript | **5173** |
| **Banco de dados** | — | MongoDB Atlas (cloud, M0) ou local dev | 57010 |

> 🗄️ O serviço Node (`job-classifier-rpc`) foi arquivado em `_archive\job-classifier-rpc`
> após a promoção do .NET a serviço primário. Ferramentas de migração ficam em
> `job-classifier-tools` (`npm run migrate`, `npm run dev:mongo`).

**URLs quando tudo estiver no ar:**

- Frontend: http://localhost:5173
- Serviço RPC .NET: http://localhost:8000 (gRPC-Web + `/healthz`) e **gRPC nativo na 8003** (h2c — ex.: `grpcurl -plaintext localhost:8003 job.v1.VagaService/GetStats`)
- Python HTTP (docs Swagger): http://localhost:8001/docs
- Python gRPC: porta 8002 (serviço `job.v1.ScrapingService`)

**Ordem de inicialização recomendada:** MongoDB → .NET (8000) → Python gRPC (8002) → Python HTTP (8001) → Frontend.
(O frontend fala gRPC-Web com o .NET; o .NET repassa scraping ao Python.)

---

## ✅ Pré-requisitos (verificação única)

Abra um **PowerShell** e confira se as ferramentas estão instaladas:

```powershell
node --version    # esperado: v20+ (projeto usa v24)
npm --version     # esperado: 10+
python --version  # esperado: 3.11+
```

> 💡 Os comandos abaixo assumem que você está na raiz do projeto:
>
> ```powershell
> cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier
> ```

---

## 1️⃣ MongoDB Atlas (banco de dados)

O banco é **cloud** (Atlas M0 gratuito) — não precisa subir nada local.

**Configuração (primeira vez):** veja o passo a passo completo em
[MIGRACAO_MONGODB.md](MIGRACAO_MONGODB.md) (projeto → cluster → usuário → IP).

A conexão é configurada no `.env` do serviço RPC:

```
MONGODB_URI=mongodb+srv://usuario:senha@job-classifier.xxxxx.mongodb.net/?retryWrites=true&w=majority
MONGODB_DB=job_tracker
```

> 💡 **Sem Atlas ainda?** Não é bloqueio: o **atalho da área de trabalho** detecta
> a ausência da `MONGODB_URI` e sobe automaticamente um **MongoDB local de
> desenvolvimento** (porta 57010, dados efêmeros). Para repovoá-lo, rode
> `npm run migrate` em `job-classifier-rpc` (veja [MIGRACAO_MONGODB.md](MIGRACAO_MONGODB.md),
> seção 3.1). Ao configurar o Atlas, basta preencher a URI no `.env` — nada mais muda.

**Migração de dados (primeira vez):**

```powershell
cd job-classifier-rpc
npm run migrate
```

---

## 2️⃣ Código protobuf (codegen)

Os contratos gRPC vivem em `proto/job/v1/`. O código TypeScript/Python é
gerado a partir deles — rode na raiz (o launcher faz isso automaticamente):

```powershell
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier
npm install        # primeira vez apenas
npm run proto:all  # buf lint + buf generate (TS)
```

Para os stubs Python:

```powershell
cd job-classifier-python
.\venv\Scripts\python.exe -m grpc_tools.protoc -I ..\proto `
  --python_out=src\gen --grpc_python_out=src\gen job/v1/vagas.proto job/v1/scraping.proto
```

---

## 3️⃣ Serviço .NET gRPC (porta 8000) — **primário**

Abra um **terminal**:

```powershell
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\job-classifier-dotnet
```

**Primeira vez apenas** — compilar:

```powershell
dotnet build
```

**Configuração (opcional):** crie `job-classifier-dotnet\.env` com
`MONGODB_URI=mongodb+srv://...` para usar o Atlas. Sem isso, o launcher usa o
MongoDB local automaticamente.

**Subir o servidor (modo desenvolvimento):**

```powershell
# na raiz do projeto (resolve o MongoDB sozinho):
powershell -ExecutionPolicy Bypass -File run-dotnet-dev.ps1

# ou direto na pasta:
dotnet run
```

**Como saber que subiu:** o console mostra o log do ASP.NET Core e o healthcheck responde:

> 🔎 Healthcheck: `http://localhost:8000/healthz` → `{"status":"ok","service":"job-classifier-dotnet"}`

> 📦 O serviço Node anterior (`job-classifier-rpc`) foi **arquivado** em
> `_archive\job-classifier-rpc` — o .NET é a implementação primária do contrato
> `job.v1.VagaService`. Detalhes: `job-classifier-dotnet\README.md`.

---

## 4️⃣ Microserviço Python (portas 8001 e 8002)

Abra um **novo terminal**:

```powershell
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\job-classifier-python
```

**Primeira vez apenas** — venv e dependências:

```powershell
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
```

**gRPC (ScrapingService, porta 8002):**

```powershell
.\venv\Scripts\python.exe -m src.grpc_server
```

**HTTP FastAPI (Swagger/Excel, porta 8001):**

```powershell
.\venv\Scripts\python.exe -m uvicorn src.main:app --reload --port 8001
```

**Como saber que subiu:** gRPC imprime `🔧 Job Classifier gRPC ... em http://0.0.0.0:8002`; HTTP responde em http://localhost:8001/health

---

## 5️⃣ Frontend React (porta 5173)

Abra um **terceiro terminal**:

```powershell
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\job-classifier-react
```

**Primeira vez apenas:**

```powershell
npm install
```

**Subir o servidor de desenvolvimento:**

```powershell
npm run dev
```

**Como saber que subiu:** o Vite imprime `Local: http://localhost:5173/`.

**Abrir no navegador:** acesse **http://localhost:5173** 🎉

> O Vite proxya `/rpc` → `http://127.0.0.1:8000` (ConnectRPC) e `/exportar` →
> `http://127.0.0.1:8001` (Excel via FastAPI) — sem CORS em desenvolvimento.

---

## 🛑 Como parar tudo

- Nos terminais onde cada serviço roda, pressione **Ctrl + C** (às vezes duas vezes) e confirme com `S`/`Y` se perguntar.
- Fechar a janela do terminal também encerra o serviço.
- Ou, na raiz do projeto:

```powershell
powershell -ExecutionPolicy Bypass -File stop-job-classifier.ps1
```

---

## 🔁 Resumo rápido (copiar e colar)

Em 3 terminais (MongoDB local é iniciado pelo launcher quando necessário;
para migração, veja `job-classifier-tools`):

```powershell
# Terminal 1 — Serviço .NET gRPC (8000)
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\job-classifier-dotnet
dotnet run

# Terminal 2 — Python gRPC (8002) + HTTP (8001)
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\job-classifier-python
.\venv\Scripts\python.exe -m src.grpc_server
.\venv\Scripts\python.exe -m uvicorn src.main:app --reload --port 8001

# Terminal 3 — Frontend (5173)
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\job-classifier-react
npm run dev
```

Depois abra **http://localhost:5173** no navegador.

---

## 🩺 Diagnóstico de problemas

**Verificar quais portas estão ocupadas:**

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object { $_.LocalPort -in 5173, 8000, 8001, 8002, 57010 } |
  Select-Object LocalPort, OwningProcess
```

**Descobrir qual processo usa uma porta:**

```powershell
Get-Process -Id (Get-NetTCPConnection -LocalPort 8000 -State Listen).OwningProcess
```

**Encerrar um processo que travou a porta (ex.: 8000):**

```powershell
Stop-Process -Id (Get-NetTCPConnection -LocalPort 8000 -State Listen).OwningProcess -Force
```

### Problemas comuns

| Sintoma | Causa provável | Solução |
|---|---|---|
| RPC não sobe: "MONGODB_URI não configurada" | `.env` ausente ou vazio em `job-classifier-rpc` | Copie `.env.example` → `.env` e preencha `MONGODB_URI` |
| RPC sobe mas listagem falha (timeout Atlas) | IP não liberado no Network Access ou cluster pausado | Libere o IP / verifique o cluster no Atlas |
| Frontend carrega mas sem dados | Serviço RPC fora do ar na porta 8000 | Suba o RPC e recarregue a página |
| Scraping dispara erro "scraping indisponível" | Python gRPC (8002) parado | Suba `.\venv\Scripts\python.exe -m src.grpc_server` |
| Frontend carrega mas sem dados (antigo /api) | Cache do browser com build REST antigo | Hard refresh (Ctrl+Shift+R) |
| `npm run dev` falha com módulo não encontrado | `node_modules` ausente ou desatualizado | Rode `npm install` na pasta do serviço |
| Porta 8000/8001/8002/5173 já em uso | Instância anterior ainda rodando | `powershell -File stop-job-classifier.ps1` |
| `python` abre a Microsoft Store | Alias do Windows à frente do Python real | Use `.\venv\Scripts\python.exe` diretamente ou ajuste o PATH |
| Erro de tipo ao compilar após editar .proto | Código gerado desatualizado | Rode `npm run proto:all` na raiz |

---

## ⚡ Atalho automático

Se quiser pular tudo isso: dê dois cliques no atalho **Job Classifier** da área de trabalho (ou rode `powershell -File start-job-classifier.ps1` na raiz). Ele faz exatamente os passos acima e abre o navegador automaticamente.
