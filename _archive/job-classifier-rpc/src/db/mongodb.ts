// Job Classifier — cliente MongoDB (driver oficial)
import { MongoClient, type Db } from 'mongodb';

const uri = process.env.MONGODB_URI || '';

if (!uri) {
  throw new Error(
    'MONGODB_URI não configurada. Preencha o .env do job-classifier-rpc (veja .env.example).'
  );
}

let client: MongoClient | null = null;

export async function getDb(): Promise<Db> {
  if (!client) {
    client = new MongoClient(uri, {
      serverSelectionTimeoutMS: 8000,
      appName: 'job-classifier-rpc',
    });
    await client.connect();
    console.log('✅ Conectado ao MongoDB Atlas');
  }
  return client.db(process.env.MONGODB_DB || 'job_tracker');
}

export async function closeDb(): Promise<void> {
  if (client) {
    await client.close();
    client = null;
  }
}
