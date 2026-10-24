# BarclayFlix 3.0 — Contrato da API v1

Backend inicial: Planilha Google + Apps Script (`Codigo.gs`).
O app só conhece este contrato; trocar para Supabase depois não deve exigir mudança no Flutter.

## Transporte

- Todas as chamadas são **GET** em `.../exec?action=<acao>&...` (POST no Apps Script responde 302 e complica o cliente HTTP).
- Sempre enviar `schema=1` e, quando existir, `app_version`.
- Timeout sugerido no app: 15 s (cold start do Apps Script pode levar alguns segundos). Retry: 2 tentativas com 2 s de intervalo, apenas para `NetworkError`/`Timeout`.

## Envelope

```json
{ "schema": 1, "ok": true,  "data": { } }
{ "schema": 1, "ok": false, "error": { "code": "BAD_REQUEST", "message": "..." } }
```

Estados normais (ex.: dispositivo ainda não registrado) são `ok: true`. `ok: false` é só para erro de verdade.

### Códigos de erro

| code | Significado | Ação no app |
|---|---|---|
| `BAD_REQUEST` | Parâmetro ausente/inválido | Bug do app; mostrar erro técnico |
| `SCHEMA_ERROR` | Aba/coluna ausente na planilha | Erro de administração; mostrar mensagem |
| `UPGRADE_REQUIRED` | App mais novo que a API | Pedir atualização do backend/app |
| `BUSY` | Lock ocupado | Retry |
| `INTERNAL` | Erro inesperado | Retry, depois erro genérico |

No app, além disso, existem `NetworkError`, `Timeout` e `BadPayload` (JSON inválido), tratados como tipos distintos em `ApiResult<T>`.

## Ações

### `health`
`?action=health&schema=1`
```json
{ "time": "2026-10-23T21:00:00Z", "api": "1.0", "sheets_ok": true }
```
Valida todas as abas e colunas. Rode sempre depois de mexer na planilha.

### `check_device`
`?action=check_device&schema=1&device_id=<uuid>&platform=android_tv&app_version=3.0.0`

`platform`: `android` | `android_tv` | `windows`.

Não registrado (cria a linha na aba Dispositivos automaticamente):
```json
{ "status": "nao_registrado", "activation_code": "A3F9-21CD" }
```
Ativo:
```json
{
  "status": "ativo",
  "activation_code": "A3F9-21CD",
  "expira_em": "2026-12-01",
  "cliente": { "nome": "Fulano" },
  "servidores": [
    {
      "id": "s1", "apelido": "TVPLAY",
      "hosts": ["http://tvplypro.xyz", "http://outro-dns.xyz:8080"],
      "username": "x", "password": "y",
      "stream_format": "ts"
    }
  ]
}
```
`status`: `ativo` | `nao_registrado` | `bloqueado` | `expirado`. Fora de `ativo`, só vêm `status`, `activation_code` e `expira_em`.
`expirado` é calculado pela data (vale até o fim do dia de `ExpiraEm`).

### `check_version`
`?action=check_version&schema=1&platform=android&version=3.0.0`
```json
{ "latest": "3.1.0", "min_supported": "3.0.0", "force": false, "update_url": "https://..." }
```
`force` = `version < min_supported`.

### `save_progress`
`?action=save_progress&schema=1&device_id=<uuid>&servidor_id=s1&item_type=vod|episode&item_id=1234&position_s=1830&duration_s=5400`
```json
{ "saved_at": "2026-10-23T21:00:00.000Z" }
```
Upsert por (device, servidor, tipo, item). No app: salvar a cada ~30 s e ao pausar/sair, nunca a cada segundo.

### `get_progress`
`?action=get_progress&schema=1&device_id=<uuid>&servidor_id=s1`
```json
{ "items": [ { "item_type": "vod", "item_id": "1234", "position_s": 1830, "duration_s": 5400, "updated_at": "..." } ] }
```
Mais recentes primeiro, máximo 50.

## Estrutura da planilha

Cabeçalho na linha 1, nomes **exatos**. Colunas extras são permitidas (ex.: `NomeCliente` com fórmula).

| Aba | Colunas |
|---|---|
| **Clientes** | `ClienteId`, `Nome` |
| **Servidores** | `ServidorId`, `Apelido`, `Hosts`, `StreamFormat`, `Ativo` |
| **Dispositivos** | `DeviceId`, `ClienteId`, `Status`, `ExpiraEm`, `Codigo`, `CriadoEm`, `UltimoAcesso`, `Plataforma`, `VersaoApp` |
| **Acessos** | `DeviceId`, `ServidorId`, `UsuarioXtream`, `SenhaXtream` |
| **Versao** | `Plataforma`, `Latest`, `MinSupported`, `UpdateUrl` |
| **Progresso** | `DeviceId`, `ServidorId`, `ItemType`, `ItemId`, `PositionS`, `DurationS`, `UpdatedAt` |

Regras de preenchimento:
- `Hosts`: vários DNS separados por **ponto e vírgula** (`;`), nunca vírgula (locale pt-BR).
- `StreamFormat`: `ts` ou `m3u8`. `Ativo`: `SIM` ou `NAO`.
- `Status` (Dispositivos): `ativo` ou `bloqueado`. Dispositivo novo nasce `nao_registrado`; para ativar, preencha `ClienteId`, `ExpiraEm` e mude `Status` para `ativo`, e crie as linhas em **Acessos**.
- `ExpiraEm`: `aaaa-mm-dd` (formato recomendado) ou `dd/mm/aaaa`.
- **Formate como "Texto simples"** as colunas: `Latest`, `MinSupported`, `VersaoApp`, `UpdatedAt`, `CriadoEm`, `UltimoAcesso`, `ExpiraEm`. Isso evita versões como `3.0.0` virarem data.
- `DeviceId` sempre minúsculo.

## Publicação (Apps Script)

1. Na planilha: Extensões > Apps Script. Cole `Codigo.gs`.
2. Configurações do projeto: fuso `America/Sao_Paulo`.
3. Implantar > Nova implantação > App da Web: executar como **Eu**, acesso **Qualquer pessoa**.
4. Toda mudança no código exige **Gerenciar implantações > Editar > Nova versão**, senão a URL continua servindo o código antigo.
5. Teste: abrir `.../exec?action=health&schema=1` no navegador e conferir `sheets_ok: true`.

## Segurança (limites desta fase)

- O `device_id` (UUID) funciona como credencial do dispositivo; as credenciais Xtream só são devolvidas para dispositivos `ativo`.
- Não registre `device_id` nem respostas completas em logs do app.
- A migração para Supabase deve adicionar RLS e funções (RPC) mantendo este mesmo contrato.
