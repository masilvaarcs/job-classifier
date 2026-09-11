// Job Classifier — Servidor ConnectRPC (substitui a API REST Express)
import 'dotenv/config';
import { createServer } from 'node:http';
import { connectNodeAdapter } from '@connectrpc/connect-node';
import routes from './routes.js';
import { getDb } from './db/mongodb.js';

const PORT = Number(process.env.PORT || 8000);

async function main() {
  // Valida a conexão com o MongoDB na inicialização
  const db = await getDb();
  console.log(`📦 Banco MongoDB: ${db.databaseName}`);

  const adapter = connectNodeAdapter({ routes });

  const httpServer = createServer((req, res) => {
    // GET /healthz — liveness para o launcher e monitoramento
    if (req.method === 'GET' && (req.url === '/healthz' || req.url?.startsWith('/healthz?'))) {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok' }));
      return;
    }
    // Todo o resto vai para o adapter Connect (gRPC / Connect / gRPC-Web)
    adapter(req, res);
  });

  httpServer.listen(PORT, () => {
    console.log(`🚀 Job Classifier RPC (ConnectRPC + gRPC + gRPC-Web) em http://localhost:${PORT}`);
    console.log(`   Healthcheck: http://localhost:${PORT}/healthz`);
    console.log('   Contrato: proto/job/v1/vagas.proto (service job.v1.VagaService)');
  });

  const shutdown = async () => {
    console.log('\nEncerrando...');
    httpServer.close();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error('❌ Falha ao iniciar o servidor RPC:', err);
  process.exit(1);
});
