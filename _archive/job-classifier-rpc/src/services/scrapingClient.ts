// Job Classifier — Cliente gRPC nativo para o microserviço Python (porta 8002)
import { createGrpcTransport } from '@connectrpc/connect-node';
import { createClient } from '@connectrpc/connect';
import { ScrapingService } from '../gen/job/v1/scraping_pb.js';

let transport: ReturnType<typeof createGrpcTransport> | null = null;

function getTransport() {
  if (!transport) {
    // gRPC nativo exige HTTP/2; createGrpcTransport já configura isso
    transport = createGrpcTransport({
      baseUrl: process.env.PYTHON_GRPC_URL || 'http://127.0.0.1:8002',
    });
  }
  return transport;
}

export function getScrapingClient() {
  return createClient(ScrapingService, getTransport());
}
