/**
 * BarclayFlix 3.0 — Telemetria de reprodução (monitor do painel).
 *
 * O app envia eventos curtos (início, abriu, falhou, caiu, travando, pulso, fim)
 * pela ação `log_event`. Aqui eles são gravados na aba "Eventos" (criada sozinha)
 * e o painel os transforma em: quem está assistindo agora, saúde dos servidores,
 * canais com problema, mais assistidos e histórico por cliente.
 *
 * Privacidade: só ids e nomes de itens. Nunca usuário, senha ou endereço do servidor.
 * Retenção: 30 dias (limpeza automática, sem precisar de gatilho).
 */

const EV_SHEET = 'Eventos';
const EV_COLS = ['Ts', 'DeviceId', 'ClienteId', 'Sessao', 'ServidorId', 'Evento', 'Tipo', 'ItemId', 'Nome', 'V1', 'V2', 'Detalhe'];
// Texto simples nas colunas de ids/nomes: evita "12:345" virar hora e "007" virar 7.
const EV_FORMATS = ['0', '@', '@', '@', '@', '@', '@', '@', '@', '0', '0', '@'];
const EV_KEEP_DAYS = 30;
const EV_MAX_ROWS = 60000;
const EV_READ_MAX = 40000;
const EV_MAX_PER_CALL = 10;
const EV_NAMES = ['start', 'ok', 'fail', 'drop', 'stall', 'hb', 'stop'];
const EV_TYPES = ['live', 'vod', 'episode'];

// Alerta de servidor: falhas+quedas / tentativas na última hora >= 20 %,
// com pelo menos 5 tentativas (poucas tentativas = estatística ruim).
const FAIL_ALERT_RATE = 0.2;
const FAIL_MIN_SAMPLE = 5;
// Reprodução sem sinal há mais que isso deixa de aparecer em "assistindo agora".
const LIVE_GRACE_MS = 4 * 60 * 1000;
const STALL_BAD = 3; // 3 travadas na mesma reprodução = "travando"

/* ───────────────────────── Recebimento (app) ───────────────────────── */

/**
 * p.e = JSON: lista de [idadeMs, sessao, servidorId, evento, tipo, itemId, nome, v1, v2, detalhe].
 * Só aparelhos ATIVOS gravam; qualquer outro é ignorado em silêncio.
 */
function logEvent_(p) {
  const deviceId = reqDeviceId_(p);
  let list;
  try { list = JSON.parse(str_(p.e)); } catch (x) { throw new ApiError('BAD_REQUEST', 'e inválido.'); }
  if (!Array.isArray(list)) throw new ApiError('BAD_REQUEST', 'e inválido.');
  list = list.slice(0, EV_MAX_PER_CALL);

  const disp = getTable_(SHEETS.DISPOSITIVOS);
  const row = findRow_(disp, 'DeviceId', deviceId);
  if (row < 0) return { accepted: 0 };
  const r = disp.rows[row];
  if (str_(cell_(disp, r, 'Status')).toLowerCase() !== 'ativo') return { accepted: 0 };
  const cliente = str_(cell_(disp, r, 'ClienteId'));

  const now = Date.now();
  const rows = [];
  list.forEach(function (ev) {
    if (!Array.isArray(ev) || ev.length < 7) return;
    const name = str_(ev[3]);
    const tipo = str_(ev[4]);
    if (EV_NAMES.indexOf(name) < 0 || EV_TYPES.indexOf(tipo) < 0) return;
    const ago = Math.max(0, Math.min(Number(ev[0]) || 0, 6 * 3600 * 1000));
    rows.push([
      now - ago,
      deviceId,
      cliente,
      str_(ev[1]).slice(0, 16),
      str_(ev[2]).slice(0, 20),
      name,
      tipo,
      str_(ev[5]).slice(0, 40),
      str_(ev[6]).slice(0, 80),
      clampNum_(ev[7]),
      clampNum_(ev[8]),
      str_(ev[9]).slice(0, 40),
    ]);
  });
  if (!rows.length) return { accepted: 0 };
  rows.sort(function (a, b) { return a[0] - b[0]; });

  withLock_(function () {
    const sh = eventosSheet_();
    const rg = sh.getRange(sh.getLastRow() + 1, 1, rows.length, EV_COLS.length);
    rg.setNumberFormats(rows.map(function () { return EV_FORMATS; }));
    rg.setValues(rows);
  });
  maybeCleanEventos_();
  return { accepted: rows.length };
}

function clampNum_(v) {
  const n = Number(v);
  if (!isFinite(n) || n < 0) return 0;
  return Math.min(Math.round(n), 10000000);
}

function eventosSheet_() {
  const ss = SpreadsheetApp.getActive();
  let sh = ss.getSheetByName(EV_SHEET);
  if (!sh) {
    sh = ss.insertSheet(EV_SHEET);
    sh.getRange(1, 1, 1, EV_COLS.length).setValues([EV_COLS]).setFontWeight('bold');
    sh.setFrozenRows(1);
  }
  return sh;
}

/** Uma vez a cada 6 h (cache) apaga eventos antigos. Também pode ser rodada à mão. */
function maybeCleanEventos_() {
  const cache = CacheService.getScriptCache();
  if (cache.get('ev_clean')) return;
  cache.put('ev_clean', '1', 6 * 3600);
  try { limparEventosAntigos(); } catch (e) { console.error((e && e.stack) || e); }
}

/** Apaga eventos com mais de 30 dias e, se passar de 60 mil linhas, os mais antigos. */
function limparEventosAntigos() {
  const sh = eventosSheet_();
  const last = sh.getLastRow();
  if (last < 2) return 0;
  const cutoff = Date.now() - EV_KEEP_DAYS * 86400000;
  const ts = sh.getRange(2, 1, last - 1, 1).getValues();
  let n = 0;
  while (n < ts.length && Number(ts[n][0]) < cutoff) n++;
  const remaining = ts.length - n;
  if (remaining > EV_MAX_ROWS) n += remaining - EV_MAX_ROWS;
  if (n > 0) withLock_(function () { sh.deleteRows(2, n); });
  return n;
}

/* ───────────────────────── Cálculo ───────────────────────── */

function readEventos_(sinceMs) {
  const sh = eventosSheet_();
  const last = sh.getLastRow();
  if (last < 2) return [];
  const n = Math.min(last - 1, EV_READ_MAX);
  const vals = sh.getRange(last - n + 1, 1, n, EV_COLS.length).getValues();
  return vals.filter(function (r) { return Number(r[0]) >= sinceMs; });
}

/** Junta os eventos de cada reprodução (aparelho + sessão) em um resumo. */
function buildPlaybacks_(rows) {
  const map = {};
  rows.forEach(function (r) {
    const ts = Number(r[0]);
    const key = str_(r[1]) + '|' + str_(r[3]);
    let s = map[key];
    if (!s) {
      s = map[key] = {
        device: str_(r[1]), cliente: str_(r[2]), servidor: str_(r[4]), tipo: str_(r[6]),
        item: str_(r[7]), nome: str_(r[8]), start: ts, last: ts,
        ok: false, fail: false, drop: false, stalled: false, stopped: false,
        watched: 0, stalls: 0, stallS: 0, openSecs: 0,
      };
    }
    if (ts < s.start) s.start = ts;
    if (ts > s.last) s.last = ts;
    const v1 = Number(r[9]) || 0;
    const v2 = Number(r[10]) || 0;
    switch (str_(r[5])) {
      case 'ok': s.ok = true; s.openSecs = v1; break;
      case 'fail': s.fail = true; break;
      case 'drop': s.drop = true; break;
      case 'stall': s.stalled = true; break;
      case 'hb':
      case 'stop':
        s.watched = Math.max(s.watched, v1);
        s.stalls = Math.max(s.stalls, v2);
        const st = /^st=(\d+)$/.exec(str_(r[11]));
        if (st) s.stallS = Math.max(s.stallS, Number(st[1]));
        if (str_(r[5]) === 'stop') s.stopped = true;
        break;
    }
  });
  return Object.keys(map).map(function (k) {
    const s = map[k];
    s.travando = s.ok && (s.stalled || s.stalls >= STALL_BAD);
    return s;
  });
}

/** Tentativas resolvidas = abriram (ok) + não abriram (fail). Taxa = (fail + drop) / tentativas. */
function statsOf_(pbs) {
  let ok = 0, fail = 0, drop = 0, trav = 0;
  pbs.forEach(function (p) {
    if (p.ok) ok++;
    if (p.fail) fail++;
    if (p.drop) drop++;
    if (p.travando) trav++;
  });
  const n = ok + fail;
  return { n: n, ok: ok, fail: fail, drop: drop, trav: trav, rate: n ? (fail + drop) / n : 0 };
}

/* ───────────────────────── Painel ───────────────────────── */

/** Tudo da aba Monitor: agora, servidores, canais com problema e mais assistidos. */
function adminMonitor(key) {
  adminAuth_(key);
  const now = Date.now();
  const pbs = buildPlaybacks_(readEventos_(now - 7 * 86400000));

  const servT = getTable_(SHEETS.SERVIDORES);
  const names = {};
  const order = [];
  servT.rows.forEach(function (r) {
    const id = str_(cell_(servT, r, 'ServidorId'));
    if (!id) return;
    names[id] = str_(cell_(servT, r, 'Apelido'));
    order.push(id);
  });
  pbs.forEach(function (p) { if (p.servidor && !(p.servidor in names)) { names[p.servidor] = p.servidor; order.push(p.servidor); } });
  const srvName = function (id) { return names[id] || id || '?'; };

  const agora = pbs.filter(function (p) {
    return !p.stopped && !p.fail && !p.drop && now - p.last <= LIVE_GRACE_MS;
  }).sort(function (a, b) { return b.start - a.start; }).map(function (p) {
    return {
      cliente: p.cliente || 'sem cliente', servidor: srvName(p.servidor), tipo: p.tipo, nome: p.nome,
      desde: p.start, estado: p.ok ? (p.travando ? 'travando' : 'assistindo') : 'abrindo', travadas: p.stalls, travadasS: p.stallS,
    };
  });

  const h1 = pbs.filter(function (p) { return p.start >= now - 3600000; });
  const h24 = pbs.filter(function (p) { return p.start >= now - 86400000; });
  const servers = order.map(function (id) {
    const a = statsOf_(h1.filter(function (p) { return p.servidor === id; }));
    const b = statsOf_(h24.filter(function (p) { return p.servidor === id; }));
    return {
      id: id, apelido: srvName(id), h1: a, h24: b,
      semDados: a.n < FAIL_MIN_SAMPLE,
      alerta: a.n >= FAIL_MIN_SAMPLE && a.rate >= FAIL_ALERT_RATE,
    };
  });

  // Canais/filmes com problema nas últimas 24 h.
  const groups = {};
  h24.forEach(function (p) {
    const k = p.servidor + '|' + p.tipo + '|' + (p.item || p.nome);
    (groups[k] = groups[k] || []).push(p);
  });
  const problemas = Object.keys(groups).map(function (k) {
    const g = groups[k];
    const st = statsOf_(g);
    return {
      servidor: srvName(g[0].servidor), tipo: g[0].tipo, nome: g[0].nome,
      tentativas: st.n, falhas: st.fail, quedas: st.drop, travadas: st.trav,
      score: st.fail + st.drop + st.trav,
    };
  }).filter(function (x) { return x.score >= 2; })
    .sort(function (a, b) { return b.score - a.score || b.tentativas - a.tentativas; })
    .slice(0, 15);

  // Mais assistidos (7 dias): por tempo assistido.
  const tops = { live: [], vod: [], episode: [] };
  const tg = {};
  pbs.forEach(function (p) {
    if (!p.ok || p.watched < 60) return;
    const k = p.tipo + '|' + (p.item || p.nome);
    const t = tg[k] = tg[k] || { tipo: p.tipo, nome: p.nome, vezes: 0, segundos: 0, clientes: {} };
    t.vezes++;
    t.segundos += p.watched;
    t.clientes[p.cliente || p.device] = true;
  });
  Object.keys(tg).forEach(function (k) {
    const t = tg[k];
    tops[t.tipo].push({ nome: t.nome, vezes: t.vezes, segundos: t.segundos, clientes: Object.keys(t.clientes).length });
  });
  Object.keys(tops).forEach(function (t) {
    tops[t].sort(function (a, b) { return b.segundos - a.segundos; });
    tops[t] = tops[t].slice(0, 10);
  });

  const cli24 = {};
  let seg24 = 0;
  h24.forEach(function (p) { cli24[p.cliente || p.device] = true; seg24 += p.ok ? p.watched : 0; });

  return {
    agora: agora,
    servers: servers,
    problemas: problemas,
    tops: tops,
    resumo: {
      assistindo: agora.length,
      reproducoes24h: h24.length,
      clientes24h: Object.keys(cli24).length,
      segundos24h: seg24,
      semDados: pbs.length === 0,
    },
    limiar: { taxa: FAIL_ALERT_RATE, minimo: FAIL_MIN_SAMPLE },
    geradoEm: now,
  };
}

/** Atividade de um cliente nos últimos 7 dias. */
function adminClientHistory(key, clienteId) {
  adminAuth_(key);
  const id = str_(clienteId);
  const now = Date.now();
  const rows = readEventos_(now - 7 * 86400000).filter(function (r) { return str_(r[2]) === id; });
  const pbs = buildPlaybacks_(rows).sort(function (a, b) { return b.start - a.start; });

  const servT = getTable_(SHEETS.SERVIDORES);
  const names = {};
  servT.rows.forEach(function (r) { names[str_(cell_(servT, r, 'ServidorId'))] = str_(cell_(servT, r, 'Apelido')); });

  let seg = 0, falhas = 0, quedas = 0;
  pbs.forEach(function (p) {
    if (p.ok) seg += p.watched;
    if (p.fail) falhas++;
    if (p.drop) quedas++;
  });
  return {
    reproducoes: pbs.length,
    segundos: seg,
    falhas: falhas,
    quedas: quedas,
    lista: pbs.slice(0, 40).map(function (p) {
      return {
        inicio: p.start, tipo: p.tipo, nome: p.nome, servidor: names[p.servidor] || p.servidor,
        segundos: p.watched, travadas: p.stalls, travadasS: p.stallS,
        resultado: p.fail ? 'falhou' : p.drop ? 'caiu' : p.ok ? (p.travando ? 'travando' : 'ok') : 'abandonou',
      };
    }),
  };
}
