# BarclayFlix 3.0

Player IPTV multiplataforma em Flutter, feito do zero: **Android**, **Android TV** e **Windows**.
Consome a API Xtream Codes dos servidores do cliente e usa um backend próprio (Planilha Google + Apps Script) para ativação por código de dispositivo, controle de versão e sincronização de "continuar assistindo".

> Status: fase inicial. Backend e contrato da API definidos; app Flutter ainda não criado.

## Estrutura

```
BarclayFlix3/
├── backend/    Apps Script (Codigo.gs = API v1, Setup.gs = monta a planilha)
├── docs/       Contrato da API, mockups, decisões
├── app/        Projeto Flutter (a criar)
└── scripts/    Build e execução em desenvolvimento (a criar)
```

## Decisões de arquitetura

- **Player:** `media_kit` (+ `media_kit_video`, `media_kit_safe_init`).
- **Estado:** Provider. Rede em Services, interface em Screens/Widgets.
- **Ativação:** código do dispositivo (8 primeiros hex do UUID, ex.: `A3F9-21CD`), sem usuário e senha no app.
- **Backend:** Planilha + Apps Script agora, Supabase depois, **mantendo o mesmo contrato** (ver `docs/contrato-api-v1.md`).
- **Erros tipados:** `ApiResult<T>` com sucesso, erro da API, rede, timeout e payload inválido, cada um com tela própria.
- **Configuração que falha alto:** o app valida a URL da API na inicialização e mostra erro claro se faltar.
- **D-Pad desde o início:** kit de foco compartilhado (grupos, grade 2D, `FocusNode` estável) validado na TV real.
- **Imagens:** sem `cached_network_image` (quebra no Windows); widget próprio com `cacheWidth`/`cacheHeight`.
- **Android TV TCL:** roda em 32 bits, então o APK precisa de `armeabi-v7a`.
- **Conexões:** muitos painéis limitam a 1 conexão simultânea; o player nunca abre dois streams ao mesmo tempo.

## Backend (Planilha + Apps Script)

1. Abra a planilha `BarclayFlix3.0`, vá em Extensões > Apps Script.
2. Cole `backend/Codigo.gs` e, em outro arquivo, `backend/Setup.gs`.
3. Execute `setupPlanilha` uma vez (cria abas, cabeçalhos e validações).
4. Implantar > App da Web, executar como **Eu**, acesso **Qualquer pessoa**.
5. Teste `.../exec?action=health&schema=1` e confira `sheets_ok: true`.

Toda alteração no script exige **Gerenciar implantações > Nova versão**.
Detalhes completos em [`docs/contrato-api-v1.md`](docs/contrato-api-v1.md).

## Configuração local (não versionada)

A URL do Apps Script **não** entra no código. Ela vem de `app/config.local.json` (ignorado pelo Git), passado ao Flutter com `--dart-define-from-file`:

```json
{ "API_URL": "https://script.google.com/macros/s/SEU_ID/exec" }
```

Modelo versionado: `app/config.example.json`.

## Segurança

Este repositório é público. Nunca versionar: `key.properties`, keystores (`*.jks`), credenciais Xtream, URL do Apps Script, `device_id` reais. O `.gitignore` já cobre os padrões comuns, mas confira o `git status` antes de cada commit.

## Fluxo de trabalho

- `main` protegida: mudanças entram por branch, revisão e validação em dispositivo real (TCL Google TV) antes do merge.
- Mockup aprovado antes de implementar qualquer mudança visual.
- `git push` só depois de revisão manual.
