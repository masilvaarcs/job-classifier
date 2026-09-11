# 🍃 Job Classifier — Migração PostgreSQL → MongoDB Atlas

> Guia operacional da migração de dados e da configuração do Atlas.
> O documento técnico da arquitetura está em [MIGRACAO_GRPC.md](MIGRACAO_GRPC.md).

> ✅ **Status (2026-09-11)**: a migração já foi **testada de ponta a ponta** com um
> MongoDB local (`npm run dev:mongo`, porta 57010) — as **4.109 vagas** foram migradas
> com todos os índices e o dashboard consumiu os dados via gRPC/Connect.
> O que falta é **só o Atlas**: criar projeto + cluster M0 na UI e preencher a
> `MONGODB_URI` no `job-classifier-rpc\.env` (passo 1 abaixo).

---

## 🔐 1. Situação atual das credenciais Atlas

**⚠️ AÇÃO NECESSÁRIA ANTES DE TUDO**: a chave de API pública/privada do Atlas
foi compartilhada em conversa. Após concluir a configuração abaixo,
**revogue-a** e crie outra:

```
Atlas UI → Organization Access Manager → API Keys → ... → Revoke
```

A chave em uso é do nível **Organização** (identidade omitida por segurança),
porém **sem o papel "Organization Project Creator"** — por isso o projeto
`job-classifier` precisa ser criado manualmente na UI (a API recusou com
`NOT_ORG_GROUP_CREATOR`). Alternativa: dê o papel à chave e eu crio tudo via API.

### O que fazer na UI do Atlas (5 minutos)

1. **Criar o projeto** `job-classifier` (ele ainda não existe na org):
   `Atlas UI → New Project → nome: job-classifier`

2. **Criar o cluster M0 (gratuito)** dentro do projeto:
   `Build a Database → M0 FREE → região: aws/us-east-1 (ou a mais próxima) → nome: job-classifier`

3. **Criar o usuário de banco** (para a aplicação e a migração):
   `Database Access → Add New Database User`
   - User: `jobclass_app`
   - Senha: gere uma forte (guarde no `.env`, nunca no git)
   - Role: `readWrite` no database `job_tracker`

4. **Liberar seu IP**:
   `Network Access → Add IP Address → Add Current IP`
   (ou `0.0.0.0/0` apenas para testes rápidos — não recomendado)

5. **Copiar a connection string**:
   `Database → Connect → Drivers → Node.js`
   Será algo como:
   ```
   mongodb+srv://jobclass_app:<senha>@job-classifier.xxxxx.mongodb.net/?retryWrites=true&w=majority
   ```

> 💡 Se você já criou o projeto/cluster em outra conta ou org, mande os dados
> (connection string + nome do banco) — o restante do processo é idêntico.

---

## 🚀 2. Rodar a migração

```powershell
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\job-classifier-rpc
Copy-Item .env.example .env
```

Preencha no `.env`:

```ini
MONGODB_URI=mongodb+srv://jobclass_app:<senha>@job-classifier.xxxxx.mongodb.net/?retryWrites=true&w=majority
MONGODB_DB=job_tracker
PG_URL=postgresql://jobclass:<senha_pg>@127.0.0.1:5432/job_tracker
```

> ✅ A senha do PostgreSQL local foi **resetada em 2026-09-11** (usuários `postgres`
> e `jobclass` compartilham a mesma senha) e está no vault do segundo cérebro:
> `02-Areas/Credenciais/KEYS_SECRETS_ID_OTHERS/PostgreSQL e MongoDB - Job Classifier.md`.
> O `jobclass` tem `SELECT` garantido em todas as tabelas de `job_tracker`.

Executar:

```powershell
npm run migrate
```

Saída esperada:

```
✅ Conectado ao PostgreSQL
📥 N vagas lidas do PostgreSQL
✅ Conectado ao MongoDB Atlas (db: job_tracker)
🔧 Índices criados (link único, id único, consultas)
   lote 1: +500 (total 500) ...
🎉 Migração concluída: X inseridas, Y atualizadas (dedup por link)
📊 Documentos na coleção 'vagas': N
```

O script é **idempotente** — rodar de novo não duplica nada (upsert por `link`).

---

## 🗃️ 3. Modelo de dados no MongoDB

Coleção **`vagas`** — documento espelha 1:1 a tabela `job_vagas`
(mesmos campos snake_case, mesmos tipos; datas como BSON Date):

```json
{
  "_id": "ObjectId(...)",
  "id": 42,                          // id numérico da aplicação (índice único)
  "titulo": "Desenvolvedor Backend...",
  "empresa": "...", "localizacao": "...", "salario": "...",
  "modalidade": "...", "publicado": "...",
  "data_publicacao": null,
  "tipo_trabalho": "REMOTO",         // REMOTO|HIBRIDO|PRESENCIAL|NAO IDENTIFICADO
  "descricao": "...",
  "link": "https://...",             // ← índice ÚNICO (chave natural, dedup)
  "job_id": "...", "plataforma": "LinkedIn",
  "data_coleta": {"$date": "..."}, "created_at": {...}, "updated_at": {...},
  "status_usuario": "pendente",      // pendente|candidatado|entrevista|rejeitado|contratado
  "ignorada": false, "pra_mim": false,
  "score_compatibilidade": 65,
  "data_verificacao": null,
  "ativa": true, "notas": ""
}
```

**Índices criados automaticamente pela migração:**

| Índice | Motivo |
|---|---|
| `{ link: 1 }` unique | dedup na importação (equivalente do PG) |
| `{ id: 1 }` unique | id da aplicação |
| `{ plataforma: 1, data_coleta: -1 }` | filtros do dashboard |
| `{ score_compatibilidade: -1, data_coleta: -1 }` | ordenação padrão da listagem |
| `{ status_usuario: 1 }`, `{ ignorada: 1 }`, `{ pra_mim: 1 }` | filtros rápidos |

---

## 🧪 3.1 MongoDB local de desenvolvimento (fallback)

Enquanto o Atlas não estiver pronto (ou para desenvolver offline):

```powershell
cd C:\__DEV__\__Projetos_2026\__FILTRA_VAGAS_2026\job-classifier\job-classifier-rpc
npm run dev:mongo        # mongod real em memória, porta 57010, dados efêmeros
```

- O **launcher** (`start-job-classifier.ps1`) faz isso automaticamente quando
  `MONGODB_URI` não está no `.env` — o projeto sobe sempre, com ou sem Atlas.
- Os dados do mongo local são **descartados ao encerrar**; repovoe com `npm run migrate`.

---

## ✅ 4. Checklist final

- [ ] Chave de API vazada **revogada** no Atlas
- [ ] Projeto + cluster M0 criados, usuário de banco e IP liberados
- [ ] `.env` do rpc preenchido (MONGODB_URI, MONGODB_DB, PG_URL)
- [ ] `npm run migrate` OK, contagens batem com o PostgreSQL
- [ ] Serviço RPC sobe e lista dados (`npm run dev` em job-classifier-rpc)
  > *Nota: o `job-classifier-rpc` foi arquivado em `_archive/` — a checagem equivalente hoje é o
  > serviço .NET primário na porta 8000 (`/healthz` + dashboard).*
- [ ] Frontend carrega vagas e permite marcar status/favoritar/ignorar
- [ ] (Opcional) Backup do dump PG antes de considerar o PostgreSQL legado

## 🔜 5. Depois da migração

> **Atualizado em 2026-09-11:** esta seção antecede a migração REST → gRPC e a promoção do .NET.
> Estado real atual: o serviço RPC (Node/ConnectRPC) **foi arquivado** em `_archive/job-classifier-rpc/`,
> o **`job-classifier-dotnet` é o serviço primário** (porta 8000, gRPC + gRPC-Web) e o REST
> (`job-classifier-api`) está **legado**. A migração de dados continua válida — aponte `PG_URL`
> e a `MONGODB_URI` para o mesmo destino via `job-classifier-tools`.

- O PostgreSQL pode permanecer no ar como backup até confiar 100% no Atlas.
- Remover `pg` das dependências do rpc quando o dump final for arquivado.
  > *Hoje: `pg` vive apenas no `job-classifier-tools` (migração) e no legado; o serviço primário usa MongoDB.*
- O `job-classifier-api` (REST/Express) pode ser desligado do launcher e,
  quando quiser, arquivado num branch `legacy-rest`.
  > *Feito diferente: ele permanece como repositório próprio marcado como LEGADO no README
> (e o RPC foi quem efetivamente foi arquivado).*
