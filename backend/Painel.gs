/**
 * BarclayFlix 3.0 — Painel de administração (abre no navegador do celular).
 * Mesmo projeto Apps Script do Codigo.gs. A página é servida em:
 *   <URL do /exec>?page=admin
 * A chave de administrador fica em Propriedades do script (ADMIN_KEY), NUNCA no código.
 * Rode UMA vez a função "gerarChaveAdmin" e leia a chave em Execuções > Registro.
 */

const ADMIN_MAX_FAILS = 5;
const ADMIN_LOCK_SECONDS = 15 * 60;

function adminPage_() {
  return HtmlService.createHtmlOutputFromFile('PainelPagina')
    .setTitle('BarclayFlix Admin')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

/** Rode uma vez no editor. A chave aparece no Registro de execução. */
function gerarChaveAdmin() {
  const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let key = '';
  for (let i = 0; i < 24; i++) key += chars.charAt(Math.floor(Math.random() * chars.length));
  PropertiesService.getScriptProperties().setProperty('ADMIN_KEY', key);
  Logger.log('CHAVE DE ADMINISTRADOR (guarde): ' + key);
}

function adminAuth_(key) {
  const cache = CacheService.getScriptCache();
  const fails = Number(cache.get('admin_fails') || 0);
  if (fails >= ADMIN_MAX_FAILS) throw new Error('Muitas tentativas. Aguarde 15 minutos.');
  const real = PropertiesService.getScriptProperties().getProperty('ADMIN_KEY');
  if (!real) throw new Error('Chave ainda não gerada. Rode gerarChaveAdmin no editor.');
  const given = String(key || '');
  let diff = given.length === real.length ? 0 : 1;
  for (let i = 0; i < real.length; i++) diff |= (given.charCodeAt(i) || 0) ^ real.charCodeAt(i);
  if (diff !== 0) {
    cache.put('admin_fails', String(fails + 1), ADMIN_LOCK_SECONDS);
    throw new Error('Chave inválida.');
  }
  cache.remove('admin_fails');
}

function adminDevices_() {
  const disp = getTable_(SHEETS.DISPOSITIVOS);
  const tz = Session.getScriptTimeZone();
  return disp.rows.map(function (r) {
    const id = str_(cell_(disp, r, 'DeviceId'));
    if (!id) return null;
    let status = str_(cell_(disp, r, 'Status')).toLowerCase() || 'nao_registrado';
    const exp = parseDateEnd_(cell_(disp, r, 'ExpiraEm'));
    if (status === 'ativo' && exp && exp.getTime() < Date.now()) status = 'expirado';
    return {
      id: id,
      clienteId: str_(cell_(disp, r, 'ClienteId')),
      status: status,
      expira: exp ? Utilities.formatDate(exp, tz, 'yyyy-MM-dd') : '',
      codigo: str_(cell_(disp, r, 'Codigo')),
      ultimo: isoOf_(cell_(disp, r, 'UltimoAcesso')),
      plataforma: str_(cell_(disp, r, 'Plataforma')),
      versao: str_(cell_(disp, r, 'VersaoApp')),
    };
  }).filter(Boolean);
}

/** Clientes (com seus aparelhos), aparelhos pendentes e servidores. Sem senhas. */
function adminList(key) {
  adminAuth_(key);
  const servidores = getTable_(SHEETS.SERVIDORES);
  const srvName = {};
  const servers = servidores.rows.map(function (r) {
    const id = str_(cell_(servidores, r, 'ServidorId'));
    const apelido = str_(cell_(servidores, r, 'Apelido'));
    srvName[id] = apelido;
    return {
      id: id,
      apelido: apelido,
      ativo: isYes_(cell_(servidores, r, 'Ativo')),
      hosts: str_(cell_(servidores, r, 'Hosts')).split(';').map(function (h) { return h.trim(); }).filter(Boolean),
      format: str_(cell_(servidores, r, 'StreamFormat')).toLowerCase() === 'm3u8' ? 'm3u8' : 'ts',
    };
  }).filter(function (s) { return s.id; });

  const ac = getTable_(SHEETS.ACESSOS_CLIENTE);
  const srvByClient = {};
  ac.rows.forEach(function (r) {
    const c = str_(cell_(ac, r, 'ClienteId'));
    if (!c) return;
    (srvByClient[c] = srvByClient[c] || []).push(srvName[str_(cell_(ac, r, 'ServidorId'))] || str_(cell_(ac, r, 'ServidorId')));
  });

  const devices = adminDevices_();
  devices.sort(function (a, b) { return a.ultimo < b.ultimo ? 1 : -1; });

  const clientesT = getTable_(SHEETS.CLIENTES);
  const ids = {};
  clientesT.rows.forEach(function (r) { const id = str_(cell_(clientesT, r, 'ClienteId')); if (id) ids[id] = true; });
  devices.forEach(function (d) { if (d.clienteId) ids[d.clienteId] = true; });

  const clients = Object.keys(ids).map(function (id) {
    const mine = devices.filter(function (d) { return d.clienteId === id && d.status !== 'nao_registrado'; });
    const exps = mine.map(function (d) { return d.expira; }).filter(Boolean).sort();
    let status = 'sem_aparelho';
    if (mine.length) {
      status = mine.some(function (d) { return d.status === 'ativo'; }) ? 'ativo'
        : mine.some(function (d) { return d.status === 'expirado'; }) ? 'expirado' : 'bloqueado';
    }
    return {
      id: id,
      status: status,
      expira: exps.length ? exps[exps.length - 1] : '',
      servidores: srvByClient[id] || [],
      aparelhos: mine,
    };
  });
  clients.sort(function (a, b) { return a.id.toLowerCase() < b.id.toLowerCase() ? -1 : 1; });

  const pendentes = devices.filter(function (d) { return d.status === 'nao_registrado' || !d.clienteId; });
  return { clients: clients, pendentes: pendentes, servers: servers };
}

/** Acessos (com senha) de um cliente, para edição. */
function adminGetClient(key, clienteId) {
  adminAuth_(key);
  const id = str_(clienteId);
  const t = getTable_(SHEETS.ACESSOS_CLIENTE);
  const out = [];
  t.rows.forEach(function (r) {
    if (str_(cell_(t, r, 'ClienteId')) !== id) return;
    out.push({
      servidorId: str_(cell_(t, r, 'ServidorId')),
      user: str_(cell_(t, r, 'UsuarioXtream')),
      pass: str_(cell_(t, r, 'SenhaXtream')),
    });
  });
  return out;
}

function withAdminLock_(fn) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) throw new Error('Planilha ocupada, tente de novo.');
  try { return fn(); } finally { lock.releaseLock(); }
}

/**
 * Cadastra/atualiza um cliente e libera seus aparelhos.
 * payload: { nome, expira ('yyyy-mm-dd'), acessos:[{servidorId,user,pass}], deviceIds:[...] }
 * O nome é o identificador: salvar com o mesmo nome atualiza o cliente existente.
 */
function adminSaveClient(key, payload) {
  adminAuth_(key);
  const nome = str_(payload.nome);
  const expira = str_(payload.expira);
  if (!nome) throw new Error('Informe o nome do cliente.');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(expira)) throw new Error('Informe a validade.');
  const acessos = (payload.acessos || []).filter(function (a) { return a.servidorId && a.user && a.pass; });
  if (!acessos.length) throw new Error('Marque ao menos um servidor com usuário e senha.');
  const deviceIds = (payload.deviceIds || []).map(function (d) { return String(d).toLowerCase(); });

  return withAdminLock_(function () {
    const clientes = getTable_(SHEETS.CLIENTES);
    if (findRow_(clientes, 'ClienteId', nome) < 0) appendObj_(clientes, { ClienteId: nome, Nome: nome });

    const ac = getTable_(SHEETS.ACESSOS_CLIENTE);
    for (let i = ac.rows.length - 1; i >= 0; i--) {
      if (str_(cell_(ac, ac.rows[i], 'ClienteId')) === nome) ac.sheet.deleteRow(i + 2);
    }
    const ac2 = getTable_(SHEETS.ACESSOS_CLIENTE);
    acessos.forEach(function (a) {
      appendObj_(ac2, { ClienteId: nome, ServidorId: str_(a.servidorId), UsuarioXtream: str_(a.user), SenhaXtream: str_(a.pass) });
    });

    // Aparelhos marcados -> vinculados e ativos (os que o cliente já tinha continuam).
    // Só sai da lista quem foi desmarcado de propósito (removeIds): volta para "novos".
    const removeIds = (payload.removeIds || []).map(function (d) { return String(d).toLowerCase(); });
    const disp = getTable_(SHEETS.DISPOSITIVOS);
    disp.rows.forEach(function (r, i) {
      const id = str_(cell_(disp, r, 'DeviceId'));
      const sr = i + 2;
      if (deviceIds.indexOf(id) >= 0) {
        disp.sheet.getRange(sr, disp.idx.ClienteId + 1).setValue(nome);
        disp.sheet.getRange(sr, disp.idx.Status + 1).setValue('ativo');
        disp.sheet.getRange(sr, disp.idx.ExpiraEm + 1).setValue(expira);
      } else if (removeIds.indexOf(id) >= 0 && str_(cell_(disp, r, 'ClienteId')) === nome) {
        disp.sheet.getRange(sr, disp.idx.ClienteId + 1).setValue('');
        disp.sheet.getRange(sr, disp.idx.Status + 1).setValue('nao_registrado');
        disp.sheet.getRange(sr, disp.idx.ExpiraEm + 1).setValue('');
      } else if (str_(cell_(disp, r, 'ClienteId')) === nome &&
                 str_(cell_(disp, r, 'Status')).toLowerCase() !== 'nao_registrado') {
        // Outros aparelhos do mesmo cliente: só acompanham a nova validade.
        disp.sheet.getRange(sr, disp.idx.ExpiraEm + 1).setValue(expira);
      }
    });
    SpreadsheetApp.flush();
    return { ok: true };
  });
}

/** status: 'ativo' | 'bloqueado' — vale para todos os aparelhos do cliente. */
function adminSetClientStatus(key, clienteId, status) {
  adminAuth_(key);
  if (status !== 'ativo' && status !== 'bloqueado') throw new Error('Status inválido.');
  return withAdminLock_(function () {
    const disp = getTable_(SHEETS.DISPOSITIVOS);
    let n = 0;
    disp.rows.forEach(function (r, i) {
      if (str_(cell_(disp, r, 'ClienteId')) !== str_(clienteId)) return;
      if (str_(cell_(disp, r, 'Status')).toLowerCase() === 'nao_registrado') return;
      disp.sheet.getRange(i + 2, disp.idx.Status + 1).setValue(status);
      n++;
    });
    return { aparelhos: n };
  });
}

/** Soma dias à validade do cliente (a partir de hoje se já venceu), em todos os aparelhos. */
function adminRenewClient(key, clienteId, days) {
  adminAuth_(key);
  const n = Math.max(1, Math.min(3650, parseInt(days, 10) || 30));
  return withAdminLock_(function () {
    const disp = getTable_(SHEETS.DISPOSITIVOS);
    const rows = [];
    let maxExp = null;
    disp.rows.forEach(function (r, i) {
      if (str_(cell_(disp, r, 'ClienteId')) !== str_(clienteId)) return;
      if (str_(cell_(disp, r, 'Status')).toLowerCase() === 'nao_registrado') return;
      rows.push(i + 2);
      const e = parseDateEnd_(cell_(disp, r, 'ExpiraEm'));
      if (e && (!maxExp || e > maxExp)) maxExp = e;
    });
    if (!rows.length) throw new Error('Cliente sem aparelhos liberados.');
    const base = maxExp && maxExp.getTime() > Date.now() ? new Date(maxExp.getTime()) : new Date();
    base.setDate(base.getDate() + n);
    const novo = Utilities.formatDate(base, Session.getScriptTimeZone(), 'yyyy-MM-dd');
    rows.forEach(function (sr) {
      disp.sheet.getRange(sr, disp.idx.ExpiraEm + 1).setValue(novo);
      disp.sheet.getRange(sr, disp.idx.Status + 1).setValue('ativo');
    });
    return { expira: novo };
  });
}

/**
 * Rode UMA vez (opcional): copia os acessos antigos por aparelho para o cliente
 * dono do aparelho, quando o cliente ainda não tem acessos próprios.
 */
function migrarAcessosParaClientes() {
  const disp = getTable_(SHEETS.DISPOSITIVOS);
  const old = getTable_(SHEETS.ACESSOS);
  const ac = getTable_(SHEETS.ACESSOS_CLIENTE);
  const have = {};
  ac.rows.forEach(function (r) { have[str_(cell_(ac, r, 'ClienteId'))] = true; });
  let n = 0;
  disp.rows.forEach(function (r) {
    const dev = str_(cell_(disp, r, 'DeviceId'));
    const cli = str_(cell_(disp, r, 'ClienteId'));
    if (!dev || !cli || have[cli]) return;
    const t = getTable_(SHEETS.ACESSOS_CLIENTE);
    old.rows.forEach(function (a) {
      if (str_(cell_(old, a, 'DeviceId')) !== dev) return;
      appendObj_(t, { ClienteId: cli, ServidorId: str_(cell_(old, a, 'ServidorId')), UsuarioXtream: str_(cell_(old, a, 'UsuarioXtream')), SenhaXtream: str_(cell_(old, a, 'SenhaXtream')) });
      n++;
    });
    have[cli] = true;
  });
  Logger.log('Acessos copiados: ' + n);
}

/**
 * Cadastra ou edita um servidor (DNS). payload: { id (vazio = novo), apelido,
 * hosts: ['http://dns1:8080', 'http://dns2'], format: 'ts'|'m3u8', ativo: true|false }.
 * Vários hosts = o app tenta um depois do outro (backup).
 */
function adminSaveServer(key, payload) {
  adminAuth_(key);
  const apelido = str_(payload.apelido);
  if (!apelido) throw new Error('Informe o nome do servidor.');
  const hosts = (payload.hosts || []).map(function (h) { return str_(h).replace(/\/+$/, ''); }).filter(Boolean);
  if (!hosts.length) throw new Error('Informe ao menos um DNS.');
  hosts.forEach(function (h) {
    if (!/^https?:\/\/[^\s;]+$/i.test(h)) throw new Error('DNS inválido (use http:// ou https://): ' + h);
  });
  const format = payload.format === 'm3u8' ? 'm3u8' : 'ts';
  const ativo = payload.ativo === false ? 'NAO' : 'SIM';

  return withAdminLock_(function () {
    const t = getTable_(SHEETS.SERVIDORES);
    let id = str_(payload.id);
    const joined = hosts.join(';');
    if (id) {
      const row = findRow_(t, 'ServidorId', id);
      if (row < 0) throw new Error('Servidor não encontrado.');
      const sr = row + 2;
      t.sheet.getRange(sr, t.idx.Apelido + 1).setValue(apelido);
      t.sheet.getRange(sr, t.idx.Hosts + 1).setValue(joined);
      t.sheet.getRange(sr, t.idx.StreamFormat + 1).setValue(format);
      t.sheet.getRange(sr, t.idx.Ativo + 1).setValue(ativo);
    } else {
      let max = 0;
      t.rows.forEach(function (r) {
        const m = str_(cell_(t, r, 'ServidorId')).match(/^S(\d+)$/i);
        if (m) max = Math.max(max, Number(m[1]));
      });
      id = 'S' + (max + 1);
      appendObj_(t, { ServidorId: id, Apelido: apelido, Hosts: joined, StreamFormat: format, Ativo: ativo });
    }
    SpreadsheetApp.flush();
    return { id: id };
  });
}
