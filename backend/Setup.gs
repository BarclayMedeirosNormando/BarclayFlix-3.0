/**
 * BarclayFlix 3.0 — Setup da planilha (rodar UMA vez).
 * Cole este arquivo no mesmo projeto Apps Script do Codigo.gs (Arquivo > Novo > Script).
 * Depois: escolha a função "setupPlanilha" no menu e clique em Executar.
 *
 * Cria as 6 abas com os cabeçalhos exatos, congela a linha 1, formata como
 * "Texto simples" as colunas sensíveis (datas e versões), adiciona listas de
 * validação e as linhas iniciais da aba Versao. Remove a "Página1" vazia.
 * É seguro rodar de novo: não apaga dados existentes.
 */

const TEXT_COLUMNS = {
  Dispositivos: ['DeviceId', 'Codigo', 'ExpiraEm', 'CriadoEm', 'UltimoAcesso', 'VersaoApp'],
  Acessos: ['DeviceId'],
  Versao: ['Latest', 'MinSupported'],
  Progresso: ['DeviceId', 'ItemId', 'UpdatedAt'],
};

function setupPlanilha() {
  const ss = SpreadsheetApp.getActive();

  Object.keys(REQUIRED).forEach(function (name) {
    const headers = REQUIRED[name];
    const sh = ss.getSheetByName(name) || ss.insertSheet(name);
    sh.getRange(1, 1, 1, headers.length).setValues([headers]).setFontWeight('bold');
    sh.setFrozenRows(1);

    (TEXT_COLUMNS[name] || []).forEach(function (col) {
      const c = headers.indexOf(col) + 1;
      sh.getRange(2, c, sh.getMaxRows() - 1, 1).setNumberFormat('@');
    });
  });

  list_(ss, 'Servidores', 'Ativo', ['SIM', 'NAO']);
  list_(ss, 'Servidores', 'StreamFormat', ['ts', 'm3u8']);
  list_(ss, 'Dispositivos', 'Status', ['nao_registrado', 'ativo', 'bloqueado']);

  const ver = ss.getSheetByName('Versao');
  if (ver.getLastRow() < 2) {
    ver.getRange(2, 1, 3, 4).setValues([
      ['android', '3.0.0', '3.0.0', ''],
      ['android_tv', '3.0.0', '3.0.0', ''],
      ['windows', '3.0.0', '3.0.0', ''],
    ]);
  }

  const vazia = ss.getSheetByName('Página1');
  if (vazia && ss.getSheets().length > 1 && vazia.getLastRow() === 0) ss.deleteSheet(vazia);

  SpreadsheetApp.flush();
  Logger.log('Planilha configurada. Teste: ?action=health&schema=1');
}

function list_(ss, sheetName, column, values) {
  const sh = ss.getSheetByName(sheetName);
  const c = REQUIRED[sheetName].indexOf(column) + 1;
  const rule = SpreadsheetApp.newDataValidation().requireValueInList(values, true).setAllowInvalid(false).build();
  sh.getRange(2, c, sh.getMaxRows() - 1, 1).setDataValidation(rule);
}
