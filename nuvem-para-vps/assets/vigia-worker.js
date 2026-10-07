// Vigia externo num Cloudflare Worker (plano grátis).
//
// Por quê: o monitor que mora na VPS cai junto com ela. Este roda fora, a cada
// 5 minutos, e avisa depois de falhas SEGUIDAS (uma falha isolada não acorda
// ninguém) e de novo quando volta.
//
// Configurar (wrangler.toml ao lado):
//   wrangler kv namespace create ESTADO        → ponha o id no wrangler.toml
//   wrangler secret put AVISO_TIPO             → telegram | slack | discord | webhook
//   wrangler secret put AVISO_URL              → URL do webhook (slack/discord/webhook)
//   wrangler secret put TELEGRAM_TOKEN         → só se AVISO_TIPO=telegram
//   wrangler secret put TELEGRAM_CHAT          → só se AVISO_TIPO=telegram
//   wrangler secret put SAUDE_CHAVE            → opcional: exige ?chave=... no GET /saude
//   wrangler deploy
//
// Uma escrita no KV por rodada = 288 por dia, dentro do plano grátis.
// Atenção: se a zona bloqueia países, o Worker chama com o país do datacenter
// dele, e pode ser barrado pela sua própria regra.

const ALVOS = [
  { nome: "site", url: "https://exemplo.com/", ok: (s) => s >= 200 && s < 400 },
  { nome: "api", url: "https://api.exemplo.com/saude", ok: (s) => s === 200 },
];
const FALHAS_PARA_AVISAR = 2;
const TEMPO_LIMITE_MS = 15000;

async function testar(alvo) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TEMPO_LIMITE_MS);
  try {
    const r = await fetch(alvo.url, { redirect: "manual", signal: ctrl.signal, headers: { "user-agent": "vigia-externo" } });
    return { nome: alvo.nome, status: r.status, ok: alvo.ok(r.status) };
  } catch (e) {
    return { nome: alvo.nome, status: 0, ok: false };
  } finally {
    clearTimeout(t);
  }
}

async function avisar(env, texto) {
  const tipo = env.AVISO_TIPO || "webhook";
  if (tipo === "telegram") {
    return fetch(`https://api.telegram.org/bot${env.TELEGRAM_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT, text: texto }),
    });
  }
  const corpo = tipo === "discord" ? { content: texto } : { text: texto };
  return fetch(env.AVISO_URL, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(corpo) });
}

async function rodada(env) {
  const resultados = await Promise.all(ALVOS.map(testar));
  const estado = JSON.parse((await env.ESTADO.get("estado")) || '{"falhas":{},"alertado":{}}');
  const mensagens = [];
  for (const r of resultados) {
    const falhas = r.ok ? 0 : (estado.falhas[r.nome] || 0) + 1;
    estado.falhas[r.nome] = falhas;
    if (falhas >= FALHAS_PARA_AVISAR && !estado.alertado[r.nome]) {
      estado.alertado[r.nome] = true;
      mensagens.push(`🔴 ${r.nome} fora do ar (${r.status || "sem resposta"}) há ${falhas} rodadas`);
    }
    if (r.ok && estado.alertado[r.nome]) {
      estado.alertado[r.nome] = false;
      mensagens.push(`🟢 ${r.nome} voltou`);
    }
  }
  estado.ultima = new Date().toISOString();
  estado.ultimos = resultados;
  await env.ESTADO.put("estado", JSON.stringify(estado));
  if (mensagens.length) await avisar(env, mensagens.join("\n"));
  return estado;
}

export default {
  async scheduled(evento, env, ctx) {
    ctx.waitUntil(rodada(env));
  },
  // GET /saude mostra o último estado (útil para o seu monitor vigiar o vigia).
  // Público, ele conta a qualquer um quando o seu site está fora: proteja com SAUDE_CHAVE.
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === "/saude") {
      if (env.SAUDE_CHAVE && url.searchParams.get("chave") !== env.SAUDE_CHAVE) {
        return new Response("não autorizado", { status: 401 });
      }
      const estado = (await env.ESTADO.get("estado")) || "{}";
      return new Response(estado, { headers: { "content-type": "application/json" } });
    }
    return new Response("vigia externo", { status: 200 });
  },
};
