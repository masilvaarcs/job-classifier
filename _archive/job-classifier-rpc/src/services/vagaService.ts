// Job Classifier — Serviço de Vagas (MongoDB)
// Porta 1:1 do vagaService.ts (PostgreSQL) para o driver oficial do MongoDB.

import type { Db } from 'mongodb';
import { create } from '@bufbuild/protobuf';
import { timestampFromDate } from '@bufbuild/protobuf/wkt';
import {
  FiltrosSchema,
  ListVagasResponseSchema,
  PaginacaoSchema,
  PlataformaSchema,
  StatsSchema,
  UpdateVagaRequestSchema,
  VagaSchema,
  type Filtros,
  type ListVagasResponse,
  type Plataforma,
  type Stats,
  type UpdateVagaRequest,
  type Vaga,
} from '../gen/job/v1/vagas_pb.js';

export interface VagaDoc {
  id: number;
  titulo: string;
  empresa: string;
  localizacao: string;
  salario: string;
  modalidade: string;
  publicado: string;
  data_publicacao: Date | null;
  tipo_trabalho: string;
  descricao: string;
  link: string;
  job_id: string;
  plataforma: string;
  data_coleta: Date | null;
  created_at: Date | null;
  updated_at: Date | null;
  status_usuario: string;
  ignorada: boolean;
  pra_mim: boolean;
  score_compatibilidade: number;
  data_verificacao: Date | null;
  ativa: boolean;
  notas: string;
}

const TIPO_MAP: Record<string, string> = {
  '🟢 Remoto': 'REMOTO',
  '🟡 Híbrido': 'HIBRIDO',
  '🟠 Presencial': 'PRESENCIAL',
};

const STATUS_MAP: Record<string, string> = {
  'Pendente': 'pendente',
  'Candidatado': 'candidatado',
  'Entrevista': 'entrevista',
  'Rejeitado': 'rejeitado',
  'Contratado': 'contratado',
};

function docToVaga(d: VagaDoc): Vaga {
  return create(VagaSchema, {
    id: BigInt(d.id),
    titulo: d.titulo ?? '',
    empresa: d.empresa ?? '',
    localizacao: d.localizacao ?? '',
    salario: d.salario ?? '',
    modalidade: d.modalidade ?? '',
    publicado: d.publicado ?? '',
    dataPublicacao: d.data_publicacao ? timestampFromDate(d.data_publicacao) : undefined,
    tipoTrabalho: d.tipo_trabalho ?? '',
    descricao: d.descricao ?? '',
    link: d.link ?? '',
    jobId: d.job_id ?? '',
    plataforma: d.plataforma ?? '',
    dataColeta: d.data_coleta ? timestampFromDate(d.data_coleta) : undefined,
    createdAt: d.created_at ? timestampFromDate(d.created_at) : undefined,
    updatedAt: d.updated_at ? timestampFromDate(d.updated_at) : undefined,
    statusUsuario: d.status_usuario ?? '',
    ignorada: d.ignorada ?? false,
    praMim: d.pra_mim ?? false,
    scoreCompatibilidade: d.score_compatibilidade ?? 0,
    dataVerificacao: d.data_verificacao ? timestampFromDate(d.data_verificacao) : undefined,
    ativa: d.ativa ?? true,
    notas: d.notas ?? '',
  });
}

function buildFilter(f: Filtros | undefined): Record<string, unknown> {
  const q: Record<string, unknown> = {};

  if (!f) return q;

  if (f.dias && f.dias > 0) {
    q.data_coleta = { $gte: new Date(Date.now() - f.dias * 86_400_000) };
  }

  if (f.plataforma && f.plataforma !== 'Todas') {
    q.plataforma = f.plataforma;
  }

  if (f.tipo && f.tipo !== 'Todos') {
    q.tipo_trabalho = TIPO_MAP[f.tipo] ?? f.tipo;
  }

  if (f.status && f.status !== 'Todos') {
    q.status_usuario = STATUS_MAP[f.status] ?? f.status;
  }

  if (f.busca) {
    const rx = new RegExp(escapeRegex(f.busca), 'i');
    q.$or = [
      { titulo: rx },
      { empresa: rx },
      { localizacao: rx },
      { descricao: rx },
    ];
  }

  if (!f.ignoradas) {
    q.ignorada = false;
  }

  if (f.apenasPraMim) {
    q.pra_mim = true;
  }

  return q;
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export class VagaService {
  constructor(private db: () => Promise<Db>) {}

  private async col() {
    return (await this.db()).collection<VagaDoc>('vagas');
  }

  async listVagas(filtros: Filtros | undefined): Promise<ListVagasResponse> {
    const col = await this.col();
    const query = buildFilter(filtros);

    const page = Math.max(1, filtros?.page ?? 1);
    const perPage = Math.min(200, Math.max(1, filtros?.perPage ?? 20));

    const [total, docs] = await Promise.all([
      col.countDocuments(query),
      col
        .find(query)
        .sort({ score_compatibilidade: -1, data_coleta: -1 })
        .skip((page - 1) * perPage)
        .limit(perPage)
        .toArray(),
    ]);

    return create(ListVagasResponseSchema, {
      vagas: docs.map(docToVaga),
      paginacao: create(PaginacaoSchema, {
        page,
        perPage,
        total: BigInt(total),
        totalPages: Math.ceil(total / perPage) || 1,
      }),
    });
  }

  async updateVaga(req: UpdateVagaRequest): Promise<Vaga | null> {
    const col = await this.col();
    const set: Record<string, unknown> = { updated_at: new Date() };

    if (req.statusUsuario !== undefined) set.status_usuario = req.statusUsuario;
    if (req.notas !== undefined) set.notas = req.notas;
    if (req.ignorada !== undefined) set.ignorada = req.ignorada;
    if (req.praMim !== undefined) set.pra_mim = req.praMim;

    const doc = await col.findOneAndUpdate(
      { id: Number(req.id) },
      { $set: set },
      { returnDocument: 'after' }
    );

    return doc ? docToVaga(doc) : null;
  }

  async ignorarVaga(id: bigint): Promise<Vaga | null> {
    return this.updateVaga(create(UpdateVagaRequestSchema, { id, ignorada: true }));
  }

  async restaurarVaga(id: bigint): Promise<Vaga | null> {
    return this.updateVaga(create(UpdateVagaRequestSchema, { id, ignorada: false }));
  }

  async toggleFavoritar(id: bigint): Promise<Vaga | null> {
    const col = await this.col();
    const atual = await col.findOne({ id: Number(id) });
    if (!atual) return null;
    return this.updateVaga(create(UpdateVagaRequestSchema, { id, praMim: !atual.pra_mim }));
  }

  async getStats(): Promise<Stats> {
    const col = await this.col();

    const [porPlataforma, porTipo, porStatus, total, ultima] = await Promise.all([
      col.aggregate<{ _id: string; total: number }>([
        { $group: { _id: '$plataforma', total: { $sum: 1 } } },
      ]).toArray(),
      col.aggregate<{ _id: string; total: number }>([
        { $group: { _id: '$tipo_trabalho', total: { $sum: 1 } } },
      ]).toArray(),
      col.aggregate<{ _id: string; total: number }>([
        { $group: { _id: '$status_usuario', total: { $sum: 1 } } },
      ]).toArray(),
      col.countDocuments({}),
      col.findOne({}, { sort: { data_coleta: -1 }, projection: { data_coleta: 1 } }),
    ]);

    const toMap = (rows: Array<{ _id: string | null; total: number }>): Record<string, bigint> => {
      const m: Record<string, bigint> = {};
      for (const r of rows) m[r._id ?? ''] = BigInt(r.total);
      return m;
    };

    return create(StatsSchema, {
      totalVagas: BigInt(total),
      totalPlataformas: porPlataforma.length,
      vagasPorPlataforma: toMap(porPlataforma),
      vagasPorTipo: toMap(porTipo),
      vagasPorStatus: toMap(porStatus),
      ultimaColeta: ultima?.data_coleta?.toISOString() ?? 'N/A',
    });
  }

  async listPlataformas(): Promise<Plataforma[]> {
    const col = await this.col();
    const rows = await col
      .aggregate<{ _id: string | null; total: number; ultima: Date | null }>([
        {
          $group: {
            _id: '$plataforma',
            total: { $sum: 1 },
            ultima: { $max: '$data_coleta' },
          },
        },
        { $sort: { total: -1 } },
      ])
      .toArray();

    return rows.map((r) =>
      create(PlataformaSchema, {
        nome: r._id ?? '',
        total: BigInt(r.total),
        ultimaColeta: r.ultima?.toISOString() ?? 'N/A',
      })
    );
  }

  async recalcularScores(
    calcular: (titulo: string, descricao: string, empresa: string) => number
  ): Promise<number> {
    const col = await this.col();
    const docs = await col
      .find({}, { projection: { id: 1, titulo: 1, descricao: 1, empresa: 1 } })
      .toArray();

    const ops = docs.map((d) => ({
      updateOne: {
        filter: { id: d.id },
        update: {
          $set: {
            score_compatibilidade: calcular(d.titulo ?? '', d.descricao ?? '', d.empresa ?? ''),
            updated_at: new Date(),
          },
        },
      },
    }));

    if (ops.length > 0) {
      await col.bulkWrite(ops);
    }
    return ops.length;
  }

  async importarVagas(
    vagas: Array<{
      titulo: string;
      empresa: string;
      localizacao: string;
      salario: string;
      modalidade: string;
      publicado: string;
      dataPublicacao: string;
      tipoTrabalho: string;
      descricao: string;
      link: string;
      jobId: string;
      plataforma: string;
    }>,
    calcular: (titulo: string, descricao: string, empresa: string) => number
  ): Promise<{ importadas: number; atualizadas: number }> {
    const col = await this.col();
    let importadas = 0;
    let atualizadas = 0;

    const max = await col.find({}, { sort: { id: -1 }, limit: 1, projection: { id: 1 } }).toArray();
    let proximoId = (max[0]?.id ?? 0) + 1;

    for (const v of vagas) {
      const score = calcular(v.titulo, v.descricao ?? '', v.empresa ?? '');
      const result = await col.updateOne(
        { link: v.link },
        {
          $set: {
            titulo: v.titulo,
            empresa: v.empresa ?? '',
            localizacao: v.localizacao ?? '',
            salario: v.salario ?? '',
            modalidade: v.modalidade ?? '',
            publicado: v.publicado ?? '',
            data_publicacao: v.dataPublicacao ? new Date(v.dataPublicacao) : null,
            tipo_trabalho: v.tipoTrabalho || 'NAO IDENTIFICADO',
            descricao: v.descricao ?? '',
            updated_at: new Date(),
          },
          $setOnInsert: {
            id: proximoId++,
            link: v.link,
            job_id: v.jobId ?? '',
            plataforma: v.plataforma,
            data_coleta: new Date(),
            created_at: new Date(),
            status_usuario: 'pendente',
            ignorada: false,
            pra_mim: false,
            score_compatibilidade: score,
            data_verificacao: null,
            ativa: true,
            notas: '',
          },
        },
        { upsert: true }
      );

      if (result.upsertedCount > 0) importadas++;
      else atualizadas++;
    }

    return { importadas, atualizadas };
  }
}
