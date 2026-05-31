# Spec: Indicador de status na bandeja do sistema (tray)

> Status: rascunho para aprovação · Sem implementação · Linux/Ubuntu primeiro, Windows depois

## 1. Problema / motivação

O plugin hoje dispara notificações **transitórias** (popup `notify-send` + som) nos eventos
`Notification` e `Stop`. Some em 2s. Não dá pra "olhar de relance" e saber o estado do Claude.

Queremos um **indicador persistente** na área de status do Ubuntu (top bar, onde ficam relógio,
Wi-Fi, bateria) que mostre visualmente:

- **Pensando / trabalhando** → ícone de *loading* animado (spinner)
- **Terminou** → bolinha verde
- **Pedindo atenção** → estado de destaque (âmbar/pulsando)
- **Ocioso** → neutro

A regra de disparo reaproveita os mesmos gatilhos das notificações sonoras já existentes.

## 2. Objetivos

- Ícone persistente na bandeja do GNOME (Ubuntu).
- Estados visuais distintos: `thinking`, `done`, `attention`, `idle`.
- Reaproveitar os hooks/gatilhos existentes.
- **Conviver** com som + popup atuais sem quebrá-los.
- Arquitetura **plugável por plataforma**: Linux agora, Windows fácil de adicionar depois.
- Degradação graciosa: se daemon/deps faltarem, nada quebra (hook vira no-op best-effort).

## 3. Fora de escopo (por agora)

- Implementação Windows (só deixar o ponto de extensão pronto).
- macOS.
- Menu de ações ricas no ícone (mantém mínimo: talvez "Sair" / toggle).

## 4. Mudança arquitetural central

Os hooks atuais são **processos curtos, fire-and-forget**: rodam, notificam, morrem. Um ícone de
bandeja precisa de um **processo vivo e contínuo** pra se manter desenhado na top bar e animar o
spinner. Hook curto não consegue manter ícone.

→ Introduzir um **daemon de bandeja** (long-running). Os hooks deixam de "desenhar" e passam a
apenas **sinalizar estado** ao daemon via IPC. Esse é o ponto de design que estrutura toda a spec.

```
  evento Claude Code            IPC                      processo vivo
 ┌──────────────────┐   sinaliza estado    ┌───────────────────────────────┐
 │  hook (curto)     │ ───────────────────► │  tray daemon                   │
 │  notify-*.sh      │  escreve state file  │  ┌──────────────────────────┐  │
 │  + som/popup      │                      │  │ core agnóstico            │  │
 └──────────────────┘                      │  │  - lê IPC                 │  │
                                            │  │  - agrega sessões         │  │
                                            │  │  - calcula estado final   │  │
                                            │  └─────────────┬────────────┘  │
                                            │   backend plataforma           │
                                            │   (Linux AppIndicator | Win)   │
                                            └───────────────────────────────┘
                                                          │ desenha ícone
                                                          ▼
                                                   top bar do Ubuntu
```

## 5. Componentes

1. **Tray daemon** (vivo): dono do ícone, renderiza estado, escuta eventos IPC, anima spinner.
2. **Hooks** (existentes + novos): em cada evento, sinalizam estado ao daemon **e** mantêm som/popup.
3. **Canal IPC**: hooks → daemon.
4. **Backend de plataforma**: camada fina que desenha o ícone (Linux AppIndicator hoje; Windows depois).
5. **Agregador de estado**: combina estado de múltiplas sessões concorrentes em um único ícone.

## 6. Modelo de estados

### Estados
| Estado      | Visual                  | Significado                          |
|-------------|-------------------------|--------------------------------------|
| `idle`      | cinza/neutro (ou oculto)| sem sessão ativa                     |
| `thinking`  | spinner animado         | Claude processando                   |
| `attention` | bolinha âmbar (pulsa)   | esperando input/permissão do usuário |
| `done`      | bolinha verde           | tarefa concluída                     |

### Mapa evento → estado (por sessão)
| Evento Claude Code | Estado      | Hook                          | Som/popup? |
|--------------------|-------------|-------------------------------|------------|
| `UserPromptSubmit` | `thinking`  | `notify-thinking.sh` (**novo**)| **não** (só tray) |
| `Notification`     | `attention` | `notify-attention.sh`         | sim (atual)|
| `Stop`             | `done`      | `notify-done.sh`              | sim (atual)|
| `SessionEnd`*      | remove sessão| `notify-session-end.sh` (**novo, opcional**)| não |

\* `SessionEnd` (ou TTL de expiração) limpa o estado de sessões encerradas.

> Nota: `thinking` exige um sinal de **início** (`UserPromptSubmit`) que hoje não existe no plugin.
> Esse hook é **tray-only, sem som** — tocar a cada prompt seria irritante.

### Agregação multi-sessão
Várias sessões do Claude Code podem rodar juntas; o ícone é global e único. O daemon mantém estado
**por sessão** e calcula o estado final por **prioridade**:

```
attention  >  thinking  >  done  >  idle
```

Ex.: 1 sessão pedindo atenção + 2 pensando → ícone `attention`.

### Auto-limpeza
- `done` reverte para `idle` após `N` segundos (configurável; default sugerido 10s) **ou** persiste
  verde até o próximo `UserPromptSubmit`. → **decisão em aberto (§13)**.
- Sessões sem `SessionEnd` (crash) expiram por TTL no state file (ex.: 30 min sem update → some).

## 7. Backend Linux (Ubuntu)

GNOME esconde a bandeja legada (XEmbed). O caminho moderno é **StatusNotifierItem / AppIndicator**:

- Lib: **libayatana-appindicator** via PyGObject (`gi`).
- Requer a extensão do GNOME Shell **"AppIndicator and KStatusNotifierItem Support"**
  (pacote `gnome-shell-extension-appindicator`, comum no Ubuntu).
- Funciona em X11 e Wayland (via a extensão).
- **Animação do spinner**: `GLib.timeout_add(~120ms, troca_frame)` ciclando frames de ícone com
  `indicator.set_icon(...)`. Fallback: ícone estático se animação indisponível.

### Linguagem da implementação
Recomendado: **Python 3 + PyGObject** — `python3` já é dependência do `install.sh`, e PyGObject dá
acesso direto a AyatanaAppIndicator3 + GLib (loop de eventos + timers + file monitor) num pacote só.

Alternativa: **pystray** (cross-platform Linux+Windows). Tornaria o Windows quase de graça, mas a
animação/SNI no GNOME é mais limitada. Ver §13.

## 8. IPC: hooks → daemon

Opções avaliadas:

| Opção | Como | Prós | Contras |
|-------|------|------|---------|
| **A. State dir + file monitor** (recomendado) | hook escreve `<dir>/<session>.state`; daemon usa `Gio.FileMonitor`/inotify | consistente com o dir de dedup atual; sem bloqueio; estado **sobrevive** ao daemon caído | precisa varrer/expirar arquivos |
| B. Unix socket | daemon escuta, hook conecta e envia linha | limpo, baixa latência | se daemon caído, hook tem que tratar |
| C. FIFO | `echo estado > fifo` | trivial | escrita **bloqueia** se ninguém lê |
| D. D-Bus | sinal D-Bus próprio | nativo no desktop | peso/complexidade alta |

**Recomendação: opção A.** Reaproveita o padrão já usado em `lib/common.sh`
(`${XDG_RUNTIME_DIR:-/tmp}/claude-notification`). Cada sessão = um arquivo de estado:

```
${XDG_RUNTIME_DIR:-/tmp}/claude-notification/tray/<session_id>.state
```

Conteúdo sugerido (1 linha JSON): `{"state":"thinking","ts":1730000000}`. O daemon monitora o
diretório, relê os arquivos a cada mudança, recalcula a agregação e atualiza o ícone. Se o daemon
estiver desligado quando o hook dispara, o estado fica gravado e é lido no próximo start.

## 9. Ciclo de vida do daemon

- **Start**: 
  - Lazy-spawn — o primeiro hook que dispara sobe o daemon se não estiver rodando (recomendado), **e/ou**
  - Autostart XDG (`~/.config/autostart/claude-tray.desktop`) no login (opcional).
  - (Alternativa: systemd `--user` service.)
- **Instância única**: pidfile/lockfile em `$XDG_RUNTIME_DIR/claude-notification/tray.pid`.
- **Stop**: item "Sair" no menu do ícone, ou logout.
- **Crash**: hooks continuam gravando state files; ao subir de novo o daemon relê o estado atual.

## 10. Abstração de plataforma (para Windows fácil depois)

Núcleo do daemon = **agnóstico** (lê IPC, agrega, calcula estado). Backend = camada fina escolhida
em runtime por detecção de SO (reaproveita `is_wsl`, adiciona `is_windows`).

Interface do backend:
```python
class TrayBackend:
    def set_state(self, state: TrayState) -> None: ...  # IDLE|THINKING|ATTENTION|DONE
    def run(self) -> None: ...   # loop de eventos da plataforma
    def stop(self) -> None: ...
```

Layout sugerido:
```
daemon/
  core.py                       # agnóstico: IPC + agregação + estado
  backends/
    base.py                     # interface TrayBackend + enum TrayState
    linux_appindicator.py       # Ubuntu (agora)
    windows.py                  # stub/futuro
  assets/                       # ícones por estado + frames do spinner
```

**Windows depois** implementa só `base.TrayBackend`: `NotifyIcon` (System.Windows.Forms via
PowerShell/C#) ou backend Windows do pystray. Nada do core muda. Convenção de nomes de assets é
compartilhada entre backends.

## 11. Integração com os hooks existentes

- Nova função em `lib/common.sh` (ou novo `lib/tray.sh`): `signal_tray <state>` — grava o state file
  da sessão. Reaproveita o `session_id` já lido pelo dedup (refatorar pra capturar o payload uma vez).
- **`notify-thinking.sh`** (novo) em `UserPromptSubmit` → `signal_tray thinking` (sem som).
- `notify-attention.sh` → adiciona `signal_tray attention` (mantém som/popup).
- `notify-done.sh` → adiciona `signal_tray done` (mantém som/popup).
- **`notify-session-end.sh`** (novo, opcional) em `SessionEnd` → remove o state file da sessão.
- Registrar os novos hooks em `.claude-plugin/plugin.json`.
- `signal_tray` é **best-effort**: se faltar dependência ou diretório, vira no-op silencioso.

## 12. Assets de ícone

- `idle` (cinza/neutro), `attention` (âmbar), `done` (verde) — estáticos.
- `thinking` — sequência de N frames de spinner (ex.: 8–12 frames).
- Formato: SVG e/ou PNG; versões claras/escuras p/ tema do GNOME (symbolic-friendly).
- Tamanhos: 22px / 24px / 48px (HiDPI).

## 13. Dependências

Linux/Ubuntu (adicionar ao `install.sh`, mantendo o skip no WSL):
- `python3-gi`
- `gir1.2-ayatanaappindicator3-0.1`
- `gnome-shell-extension-appindicator` (+ avisar pra habilitar a extensão / relogar)

## 14. Casos de borda

- Daemon desligado no disparo → estado gravado, lido no próximo start.
- Múltiplas sessões → agregação por prioridade (§6).
- Sessão zumbi (crash, sem `SessionEnd`) → expira por TTL.
- Wayland × X11 → coberto pela extensão AppIndicator/SNI.
- Tema claro/escuro → ícones com variantes.
- Deps/daemon ausentes → som/popup atuais continuam funcionando; tray só não aparece.

## 15. Configuração

- Ligar/desligar tray independente do som.
- Timeout de auto-limpeza do `done`.
- (Volume do som já existe em `lib/common.sh`.)
- Mecanismo: variáveis de ambiente ou arquivo de config simples. Manter enxuto.

## 16. Decisões em aberto (precisam de input)

1. **Hook `UserPromptSubmit`** para detectar "pensando" — OK adicionar? (tray-only, sem som)
2. **`done`**: some sozinho após N s, ou fica verde até o próximo prompt?
3. **Prioridade de agregação** multi-sessão: confirmar `attention > thinking > done > idle`.
4. **Start do daemon**: lazy-spawn pelo hook, autostart no login, ou ambos?
5. **Implementação**: Python+PyGObject (recomendado) **ou** pystray (cross-platform, Windows quase de graça)?
6. **Menu do ícone**: incluir "Sair" / toggle habilitar?

## 17. Milestones

- **M1 — MVP Linux**: daemon + backend AppIndicator + IPC (opção A) + `signal_tray` + hook
  `notify-thinking.sh`; estados estáticos.
- **M2 — Polimento**: spinner animado, auto-limpeza, config, autostart, assets tema claro/escuro.
- **M3 — Windows**: implementar `backends/windows.py` sobre a mesma interface.
