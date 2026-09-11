// Job Classifier — Implementação do VagaService (ConnectRPC)
import type { ConnectRouter } from '@connectrpc/connect';
import { Code, ConnectError } from '@connectrpc/connect';
import { VagaService } from './gen/job/v1/vagas_pb.js';
import { getDb } from './db/mongodb.js';
import { VagaService as VagaServiceLogic } from './services/vagaService.js';
import { calcularScore } from './services/scoreService.js';
import { getScrapingClient } from './services/scrapingClient.js';

export default function routes(router: ConnectRouter) {
  const svc = new VagaServiceLogic(getDb);

  router.service(VagaService, {
    async listVagas(req) {
      return svc.listVagas(req.filtros);
    },

    async updateVaga(req) {
      const vaga = await svc.updateVaga(req);
      if (!vaga) throw new ConnectError('not_found', Code.NotFound);
      return { vaga };
    },

    async ignorarVaga(req) {
      const vaga = await svc.ignorarVaga(req.id);
      if (!vaga) throw new ConnectError('not_found', Code.NotFound);
      return { vaga };
    },

    async restaurarVaga(req) {
      const vaga = await svc.restaurarVaga(req.id);
      if (!vaga) throw new ConnectError('not_found', Code.NotFound);
      return { vaga };
    },

    async toggleFavoritar(req) {
      const vaga = await svc.toggleFavoritar(req.id);
      if (!vaga) throw new ConnectError('not_found', Code.NotFound);
      return { vaga };
    },

    async recalcularScores() {
      const atualizadas = await svc.recalcularScores(calcularScore);
      return { vagasAtualizadas: atualizadas };
    },

    async getStats() {
      return { stats: await svc.getStats() };
    },

    async listPlataformas() {
      return { plataformas: await svc.listPlataformas() };
    },

    async startScraping(req) {
      const client = getScrapingClient();
      try {
        const resp = await client.startScraping({ plataforma: req.plataforma ?? '' });
        return {
          iniciado: resp.iniciado,
          mensagem: resp.mensagem,
          plataformas: resp.plataformas,
        };
      } catch (err) {
        throw new ConnectError(
          `Microserviço de scraping indisponível: ${(err as Error).message}`,
          Code.Unavailable
        );
      }
    },

    async getScrapingStatus() {
      const client = getScrapingClient();
      try {
        const resp = await client.getStatus({});
        return { plataformas: resp.plataformas };
      } catch (err) {
        throw new ConnectError(
          `Microserviço de scraping indisponível: ${(err as Error).message}`,
          Code.Unavailable
        );
      }
    },

    async importVagas(req) {
      const resultado = await svc.importarVagas(req.vagas, calcularScore);
      return {
        importadas: resultado.importadas,
        atualizadas: resultado.atualizadas,
      };
    },
  });
}
