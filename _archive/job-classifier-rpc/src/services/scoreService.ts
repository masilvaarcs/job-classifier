// Job Classifier — Score de compatibilidade (porta do scoreService.ts original)
// Backend (.NET/C#) = 40 | Frontend = 20 | DB = 15 | Python = 10
// Remoto = 15 / RS = 10 | Senioridade = 5 | Máximo 100

export function calcularScore(titulo: string, descricao: string, empresa: string): number {
  let score = 0;
  const texto = `${titulo} ${descricao} ${empresa}`.toLowerCase();

  // Backend (.NET/C#/ASP.NET) = 40 pts
  if (/\b(c#|\.net|asp\.net|dotnet|web api|entity framework)\b/i.test(texto)) {
    score += 40;
  }

  // Frontend (Angular/TypeScript) = 20 pts
  if (/\b(angular|typescript|react|vue)\b/i.test(texto)) {
    score += 20;
  }

  // Banco de dados = 15 pts
  if (/\b(sql server|oracle|postgresql|mysql|postgres)\b/i.test(texto)) {
    score += 15;
  }

  // Python = 10 pts
  if (/\bpython|django|flask|fastapi\b/i.test(texto)) {
    score += 10;
  }

  // Remoto ou localização = 15 pts
  if (/remoto|remote|home office|teletrabalho/i.test(texto)) {
    score += 15;
  } else if (/\b(gravataí|porto alegre|poa|rs)\b/i.test(texto)) {
    score += 10;
  }

  // Senioridade = 5 pts
  if (/\b(sênior|senior|lead|pleno)\b/i.test(texto)) {
    score += 5;
  }

  return Math.min(score, 100);
}
