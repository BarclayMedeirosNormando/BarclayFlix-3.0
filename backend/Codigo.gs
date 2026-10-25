/**
 * BarclayFlix 3.0 — API v1
 * Google Apps Script VINCULADO à planilha (Extensões > Apps Script, dentro da planilha).
 * Todas as colunas são localizadas PELO NOME DO CABEÇALHO, nunca pela posição.
 * Colunas extras (fórmulas, observações) são ignoradas e não quebram nada.
 */

const SCHEMA = 1;
const API_VERSION = '1.0';

const SHEETS = {
  CLIENTES: 'Clientes',
  SERVIDORES: 'Servidores',
  DISPOSITIVOS: 'Dispositivos',
  ACESSOS: 'Acessos',
  ACESSOS_CLIENTE: 'AcessosCliente',
  FAVORITOS: 'Favoritos',
  VERSAO: 'Versao',
  PROGRESSO: 'Progresso',
};

// Colunas obrigatórias por aba. Se faltar alguma, a API devolve SCHEMA_ERROR
// dizendo exatamente qual aba/coluna — nada de falha silenciosa.
const REQUIRED = {
  Clientes: ['ClienteId', 'Nome'],
  Servidores: ['ServidorId', 'Apelido', 'Hosts', 'StreamFormat', 'Ativo'],
  Dispositivos: ['DeviceId', 'ClienteId', 'Status', 'ExpiraEm', 'Codigo', 'CriadoEm', 'UltimoAcesso', 'Plataforma', 'VersaoApp'],
  Acessos: ['DeviceId', 'ServidorId', 'UsuarioXtream', 'SenhaXtream'],
  AcessosCliente: ['ClienteId', 'ServidorId', 'UsuarioXtream', 'SenhaXtream'],
  Versao: ['Plataforma', 'Latest', 'MinSupported', 'UpdateUrl'],
  Progresso: ['DeviceId', 'ServidorId', 'ItemType', 'ItemId', 'PositionS', 'DurationS', 'UpdatedAt', 'ClienteId'],
  Favoritos: ['ClienteId', 'ServidorId', 'ItemType', 'ItemId', 'Nome', 'Imagem', 'AdicionadoEm'],
};

const ITEM_TYPES = ['vod', 'episode'];
const PLATFORMS = ['android', 'android_tv', 'windows'];
const LAST_SEEN_THROTTLE_MS = 10 * 60 * 1000;
const MAX_PROGRESS_ITEMS = 50;

class ApiError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const ACTIONS = {
  health: health_,
  check_device: checkDevice_,
  check_version: checkVersion_,
  save_progress: saveProgress_,
  get_favorites: getFavorites_,
  set_favorite: setFavorite_,
  get_progress: getProgress_,
  // Função embrulhada: está em outro arquivo (Telemetria.gs), que pode carregar depois deste.
  log_event: function (p) { return logEvent_(p); },
};

/* ───────────────────────── Entrada ───────────────────────── */

function doGet(e) {
  try {
    const p = (e && e.parameter) || {};
    if (p.page === 'admin') return adminPage_();
    if (p.schema && Number(p.schema) > SCHEMA) {
      throw new ApiError('UPGRADE_REQUIRED', 'Versão do app mais nova que a API.');
    }
    const fn = ACTIONS[p.action];
    if (!fn) throw new ApiError('BAD_REQUEST', 'Ação desconhecida: ' + p.action);
    return out_({ schema: SCHEMA, ok: true, data: fn(p) });
  } catch (err) {
    console.error((err && err.stack) || err);
    const known = err instanceof ApiError;
    return out_({
      schema: SCHEMA,
      ok: false,
      error: {
        code: known ? err.code : 'INTERNAL',
        message: known ? err.message : 'Erro interno',
      },
    });
  }
}

function out_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

/* ───────────────────────── Ações ───────────────────────── */

function health_() {
  // Valida a estrutura de todas as abas de uma vez: ótimo para diagnóstico.
  Object.keys(SHEETS).forEach(function (k) { getTable_(SHEETS[k]); });
  return { time: new Date().toISOString(), api: API_VERSION, sheets_ok: true };
}

function checkDevice_(p) {
  const deviceId = reqDeviceId_(p);
  const platform = PLATFORMS.indexOf(p.platform) >= 0 ? p.platform : '';
  const appVersion = str_(p.app_version);

  let disp = getTable_(SHEETS.DISPOSITIVOS);
  let row = findRow_(disp, 'DeviceId', deviceId);
  const code = activationCode_(deviceId);

  if (row < 0) {
    withLock_(function () {
      disp = getTable_(SHEETS.DISPOSITIVOS);
      if (findRow_(disp, 'DeviceId', deviceId) < 0) {
        appendObj_(disp, {
          DeviceId: deviceId,
          Status: 'nao_registrado',
          Codigo: code,
          CriadoEm: new Date().toISOString(),
          UltimoAcesso: new Date().toISOString(),
          Plataforma: platform,
          VersaoApp: appVersion,
        });
      }
    });
    return { status: 'nao_registrado', activation_code: code };
  }

  touchDevice_(disp, row, platform, appVersion);

  const r = disp.rows[row];
  let status = str_(cell_(disp, r, 'Status')).toLowerCase() || 'nao_registrado';
  const expira = parseDateEnd_(cell_(disp, r, 'ExpiraEm'));

  if (status === 'ativo' && expira && expira.getTime() < Date.now()) status = 'expirado';

  const base = {
    status: status,
    activation_code: str_(cell_(disp, r, 'Codigo')) || code,
    expira_em: expira ? Utilities.formatDate(expira, Session.getScriptTimeZone(), 'yyyy-MM-dd') : null,
  };
  if (status !== 'ativo') return base;

  // Cliente
  const clientes = getTable_(SHEETS.CLIENTES);
  const cRow = findRow_(clientes, 'ClienteId', str_(cell_(disp, r, 'ClienteId')));
  base.cliente = { nome: cRow >= 0 ? str_(cell_(clientes, clientes.rows[cRow], 'Nome')) : '' };

  // Servidores: acessos do CLIENTE (vale para todos os aparelhos dele).
  // Se o cliente não tiver nenhum, usa os acessos antigos por aparelho (Acessos).
  const clienteId = str_(cell_(disp, r, 'ClienteId'));
  const servidores = getTable_(SHEETS.SERVIDORES);
  const srvMap = {};
  servidores.rows.forEach(function (sr) {
    srvMap[str_(cell_(servidores, sr, 'ServidorId'))] = sr;
  });

  const acC = getTable_(SHEETS.ACESSOS_CLIENTE);
  let lista = acC.rows.filter(function (ar) {
    return clienteId && str_(cell_(acC, ar, 'ClienteId')) === clienteId;
  }).map(function (ar) {
    return { t: acC, r: ar };
  });
  if (!lista.length) {
    const acD = getTable_(SHEETS.ACESSOS);
    lista = acD.rows.filter(function (ar) {
      return str_(cell_(acD, ar, 'DeviceId')) === deviceId;
    }).map(function (ar) {
      return { t: acD, r: ar };
    });
  }

  base.servidores = [];
  lista.forEach(function (it) {
    const sid = str_(cell_(it.t, it.r, 'ServidorId'));
    const sr = srvMap[sid];
    if (!sr || !isYes_(cell_(servidores, sr, 'Ativo'))) return;
    const hosts = str_(cell_(servidores, sr, 'Hosts'))
      .split(';')
      .map(function (h) { return h.trim(); })
      .filter(Boolean);
    if (!hosts.length) return;
    base.servidores.push({
      id: sid,
      apelido: str_(cell_(servidores, sr, 'Apelido')),
      hosts: hosts,
      username: str_(cell_(it.t, it.r, 'UsuarioXtream')),
      password: str_(cell_(it.t, it.r, 'SenhaXtream')),
      stream_format: str_(cell_(servidores, sr, 'StreamFormat')).toLowerCase() === 'm3u8' ? 'm3u8' : 'ts',
    });
  });
  return base;
}

function checkVersion_(p) {
  const platform = str_(p.platform);
  const version = str_(p.version);
  if (PLATFORMS.indexOf(platform) < 0) throw new ApiError('BAD_REQUEST', 'platform inválida.');
  if (!version) throw new ApiError('BAD_REQUEST', 'version obrigatória.');

  const t = getTable_(SHEETS.VERSAO);
  const row = findRow_(t, 'Plataforma', platform);
  if (row < 0) return { latest: version, min_supported: version, force: false, update_url: '' };

  const r = t.rows[row];
  const latest = versionStr_(cell_(t, r, 'Latest'), 'Latest');
  const min = versionStr_(cell_(t, r, 'MinSupported'), 'MinSupported');
  return {
    latest: latest,
    min_supported: min,
    force: compareVersions_(version, min) < 0,
    update_url: str_(cell_(t, r, 'UpdateUrl')),
  };
}

// Dono do progresso/favoritos: o CLIENTE (vale para todos os aparelhos dele).
// Aparelho sem cliente cai no próprio DeviceId.
function ownerOf_(deviceId) {
  const disp = getTable_(SHEETS.DISPOSITIVOS);
  const row = findRow_(disp, 'DeviceId', deviceId);
  if (row < 0) return deviceId;
  return str_(cell_(disp, disp.rows[row], 'ClienteId')) || deviceId;
}

function saveProgress_(p) {
  const deviceId = reqDeviceId_(p);
  const servidorId = reqStr_(p, 'servidor_id');
  const itemType = reqStr_(p, 'item_type');
  const itemId = reqStr_(p, 'item_id');
  if (ITEM_TYPES.indexOf(itemType) < 0) throw new ApiError('BAD_REQUEST', 'item_type inválido.');
  const pos = reqInt_(p, 'position_s');
  const dur = reqInt_(p, 'duration_s');
  const now = new Date().toISOString();
  const owner = ownerOf_(deviceId);

  withLock_(function () {
    const t = getTable_(SHEETS.PROGRESSO);
    let found = -1;
    for (let i = 0; i < t.rows.length; i++) {
      const r = t.rows[i];
      const rowOwner = str_(cell_(t, r, 'ClienteId')) || str_(cell_(t, r, 'DeviceId'));
      if (rowOwner === owner &&
          str_(cell_(t, r, 'ServidorId')) === servidorId &&
          str_(cell_(t, r, 'ItemType')) === itemType &&
          str_(cell_(t, r, 'ItemId')) === itemId) { found = i; break; }
    }
    if (found >= 0) {
      const sheetRow = found + 2;
      t.sheet.getRange(sheetRow, t.idx.PositionS + 1).setValue(pos);
      t.sheet.getRange(sheetRow, t.idx.DurationS + 1).setValue(dur);
      t.sheet.getRange(sheetRow, t.idx.UpdatedAt + 1).setValue(now);
      t.sheet.getRange(sheetRow, t.idx.DeviceId + 1).setValue(deviceId);
      t.sheet.getRange(sheetRow, t.idx.ClienteId + 1).setValue(owner);
    } else {
      appendObj_(t, {
        DeviceId: deviceId, ClienteId: owner, ServidorId: servidorId, ItemType: itemType,
        ItemId: itemId, PositionS: pos, DurationS: dur, UpdatedAt: now,
      });
    }
  });
  return { saved_at: now };
}

function getProgress_(p) {
  const deviceId = reqDeviceId_(p);
  const servidorId = reqStr_(p, 'servidor_id');
  const owner = ownerOf_(deviceId);
  const t = getTable_(SHEETS.PROGRESSO);
  const items = [];
  t.rows.forEach(function (r) {
    const rowOwner = str_(cell_(t, r, 'ClienteId')) || str_(cell_(t, r, 'DeviceId'));
    if (rowOwner !== owner) return;
    if (str_(cell_(t, r, 'ServidorId')) !== servidorId) return;
    items.push({
      item_type: str_(cell_(t, r, 'ItemType')),
      item_id: str_(cell_(t, r, 'ItemId')),
      position_s: Number(cell_(t, r, 'PositionS')) || 0,
      duration_s: Number(cell_(t, r, 'DurationS')) || 0,
      updated_at: isoOf_(cell_(t, r, 'UpdatedAt')),
    });
  });
  items.sort(function (a, b) { return a.updated_at < b.updated_at ? 1 : -1; });
  return { items: items.slice(0, MAX_PROGRESS_ITEMS) };
}

const FAV_TYPES = ['live', 'vod', 'series'];
const MAX_FAVORITES = 300;

function getFavorites_(p) {
  const deviceId = reqDeviceId_(p);
  const servidorId = reqStr_(p, 'servidor_id');
  const owner = ownerOf_(deviceId);
  const t = getTable_(SHEETS.FAVORITOS);
  const items = [];
  t.rows.forEach(function (r) {
    if (str_(cell_(t, r, 'ClienteId')) !== owner) return;
    if (str_(cell_(t, r, 'ServidorId')) !== servidorId) return;
    items.push({
      item_type: str_(cell_(t, r, 'ItemType')),
      item_id: str_(cell_(t, r, 'ItemId')),
      name: str_(cell_(t, r, 'Nome')),
      image: str_(cell_(t, r, 'Imagem')),
      added_at: isoOf_(cell_(t, r, 'AdicionadoEm')),
    });
  });
  items.sort(function (a, b) { return a.added_at < b.added_at ? 1 : -1; });
  return { items: items.slice(0, MAX_FAVORITES) };
}

// on=1 adiciona, on=0 remove. Idempotente.
function setFavorite_(p) {
  const deviceId = reqDeviceId_(p);
  const servidorId = reqStr_(p, 'servidor_id');
  const itemType = reqStr_(p, 'item_type');
  const itemId = reqStr_(p, 'item_id');
  if (FAV_TYPES.indexOf(itemType) < 0) throw new ApiError('BAD_REQUEST', 'item_type inválido.');
  const on = str_(p.on) !== '0';
  const owner = ownerOf_(deviceId);

  withLock_(function () {
    const t = getTable_(SHEETS.FAVORITOS);
    let found = -1;
    for (let i = 0; i < t.rows.length; i++) {
      const r = t.rows[i];
      if (str_(cell_(t, r, 'ClienteId')) === owner &&
          str_(cell_(t, r, 'ServidorId')) === servidorId &&
          str_(cell_(t, r, 'ItemType')) === itemType &&
          str_(cell_(t, r, 'ItemId')) === itemId) { found = i; break; }
    }
    if (!on) {
      if (found >= 0) t.sheet.deleteRow(found + 2);
    } else if (found < 0) {
      appendObj_(t, {
        ClienteId: owner, ServidorId: servidorId, ItemType: itemType, ItemId: itemId,
        Nome: str_(p.name).slice(0, 200), Imagem: str_(p.image).slice(0, 500),
        AdicionadoEm: new Date().toISOString(),
      });
    }
  });
  return { on: on };
}

/* ───────────────────────── Helpers de planilha ───────────────────────── */

// Lê uma aba e mapeia cabeçalho -> índice. Falha alto se faltar aba/coluna.
function getTable_(name) {
  let sheet = SpreadsheetApp.getActive().getSheetByName(name);
  if (!sheet && (name === SHEETS.ACESSOS_CLIENTE || name === SHEETS.FAVORITOS)) {
    // Aba nova (acessos por cliente): criada sozinha se ainda não existir.
    sheet = SpreadsheetApp.getActive().insertSheet(name);
    sheet.getRange(1, 1, sheet.getMaxRows(), REQUIRED[name].length).setNumberFormat('@');
    sheet.getRange(1, 1, 1, REQUIRED[name].length).setValues([REQUIRED[name]]).setFontWeight('bold');
    sheet.setFrozenRows(1);
  }
  if (!sheet) throw new ApiError('SCHEMA_ERROR', 'Aba ausente: ' + name);
  const values = sheet.getDataRange().getValues();
  const headers = values[0].map(function (h) { return String(h).trim(); });
  const idx = {};
  headers.forEach(function (h, i) { if (h) idx[h] = i; });
  // Coluna nova em aba antiga: acrescenta o cabeçalho sozinho (sem perder dados).
  if (name === SHEETS.PROGRESSO && !('ClienteId' in idx)) {
    sheet.getRange(1, headers.length + 1).setValue('ClienteId').setFontWeight('bold');
    SpreadsheetApp.flush();
    return getTable_(name);
  }
  (REQUIRED[name] || []).forEach(function (h) {
    if (!(h in idx)) throw new ApiError('SCHEMA_ERROR', 'Coluna ausente na aba ' + name + ': ' + h);
  });
  return { sheet: sheet, idx: idx, width: headers.length, rows: values.slice(1) };
}

function cell_(t, row, col) { return row[t.idx[col]]; }

function findRow_(t, col, value) {
  for (let i = 0; i < t.rows.length; i++) {
    if (str_(cell_(t, t.rows[i], col)) === value) return i;
  }
  return -1;
}

function appendObj_(t, obj) {
  const row = new Array(t.width).fill('');
  Object.keys(obj).forEach(function (k) { row[t.idx[k]] = obj[k]; });
  t.sheet.appendRow(row);
}

function touchDevice_(t, row, platform, appVersion) {
  const last = Date.parse(isoOf_(cell_(t, t.rows[row], 'UltimoAcesso')));
  if (last && Date.now() - last < LAST_SEEN_THROTTLE_MS) return;
  const sr = row + 2;
  t.sheet.getRange(sr, t.idx.UltimoAcesso + 1).setValue(new Date().toISOString());
  if (platform) t.sheet.getRange(sr, t.idx.Plataforma + 1).setValue(platform);
  if (appVersion) t.sheet.getRange(sr, t.idx.VersaoApp + 1).setValue(appVersion); // coluna deve ser "Texto simples"
}

function withLock_(fn) {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) throw new ApiError('BUSY', 'Servidor ocupado, tente novamente.');
  try { fn(); } finally { lock.releaseLock(); }
}

/* ───────────────────────── Helpers gerais ───────────────────────── */

function str_(v) { return v === null || v === undefined ? '' : String(v).trim(); }

function isYes_(v) {
  const s = str_(v).toLowerCase();
  return s === 'sim' || s === 'true' || s === '1' || v === true;
}

function reqStr_(p, key) {
  const v = str_(p[key]);
  if (!v) throw new ApiError('BAD_REQUEST', 'Parâmetro obrigatório: ' + key);
  return v;
}

function reqInt_(p, key) {
  const n = parseInt(p[key], 10);
  if (isNaN(n) || n < 0) throw new ApiError('BAD_REQUEST', 'Parâmetro inválido: ' + key);
  return n;
}

function reqDeviceId_(p) {
  const id = reqStr_(p, 'device_id').toLowerCase();
  if (!/^[0-9a-f-]{8,64}$/.test(id)) throw new ApiError('BAD_REQUEST', 'device_id inválido.');
  return id;
}

function activationCode_(deviceId) {
  const hex = deviceId.replace(/-/g, '').slice(0, 8).toUpperCase();
  return hex.slice(0, 4) + '-' + hex.slice(4);
}

function isoOf_(v) {
  if (v instanceof Date) return v.toISOString();
  return str_(v);
}

// Aceita Date, 'yyyy-mm-dd' ou 'dd/mm/yyyy'. Vale até o fim do dia informado.
function parseDateEnd_(v) {
  if (!v) return null;
  if (v instanceof Date) {
    const d = new Date(v.getTime());
    d.setHours(23, 59, 59, 999);
    return d;
  }
  const s = str_(v);
  let m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return new Date(+m[1], +m[2] - 1, +m[3], 23, 59, 59, 999);
  m = s.match(/^(\d{2})\/(\d{2})\/(\d{4})/);
  if (m) return new Date(+m[3], +m[2] - 1, +m[1], 23, 59, 59, 999);
  return null;
}

// Se a planilha converteu "3.0.0" em data, avisa em vez de comparar lixo.
function versionStr_(v, col) {
  if (v instanceof Date) {
    throw new ApiError('SCHEMA_ERROR', 'Coluna ' + col + ' da aba Versao virou data. Formate a coluna como "Texto simples".');
  }
  return str_(v);
}

function compareVersions_(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const x = pa[i] || 0, y = pb[i] || 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}
