# System Patterns: Zed Code Editor

## System Architecture

Zed построен как монорепозиторий с workspace из ~200+ crate'ов, организованных в несколько слоёв:

```
┌─────────────────────────────────────────────────────────────┐
│                        zed (entry point)                   │
│  Собирает всё воедино: UI, editor, project, AI, ...       │
├─────────────────────────────────────────────────────────────┤
│  UI Layer          │  Features            │  AI/Agent       │
│  ─────────         │  ────────            │  ────────       │
│  workspace         │  editor              │  agent          │
│  ui/ui_input/      │  project/project_    │  agent_ui       │
│  ui_macros/ui_     │  panel               │  anthropic/     │
│  prompt            │  terminal/terminal_  │  open_ai/...    │
│  component         │  view                │  language_model │
│  theme/            │  git/git_ui/         │  context_server │
│  theme_selector    │  git_graph           │  copilot/       │
│  settings/         │  search              │  copilot_chat   │
│  settings_ui       │  vim                 │  inline_        │
│  menu/command_     │  debugger_ui         │  assistant      │
│  palette           │  tasks_ui            │  edit_prediction│
│  title_bar/        │  collab_ui           │  prompt_store   │
│  sidebar/panel     │  extensions_ui       │  web_search     │
│  picker            │  repl                │  rules_library  │
│  ...               │  markdown_preview    │  ...            │
├─────────────────────────────────────────────────────────────┤
│  Platform Layer (gpui)                                     │
│  ─────────────────                                         │
│  gpui (core)  │  gpui_macos  │  gpui_linux  │  gpui_windows│
│  gpui_macros  │  (Metal)     │  (X11/Wayland)│  (DirectX) │
│  gpui_wgpu    │  gpui_web    │  gpui_tokio  │  gpui_util  │
├─────────────────────────────────────────────────────────────┤
│  Core Services                                             │
│  ─────────────                                             │
│  language/lsp │  worktree/fs │  rpc/proto   │  client      │
│  text/rope    │  git         │  collab      │  channel     │
│  diagnostics  │  task        │  call        │  livekit_*   │
│  fuzzy/nucleo │  paths       │  net         │  http_client │
├─────────────────────────────────────────────────────────────┤
│  Infrastructure                                            │
│  ──────────────                                            │
│  db/sqlez │  util/util_macros │  settings_macros │  telemetry│
│  clock    │  collections      │  sum_tree        │  ztracing│
│  session  │  refineable       │  feature_flags   │  assets │
└─────────────────────────────────────────────────────────────┘
```

## Key Technical Decisions

### 1. Собственный UI фреймворк (GPUI)
- **Почему**: Не было подходящего нативного GPU-ускоренного UI-фреймворка на Rust
- **Модель**: Entity-Component, похожий на React, но на Rust
- **Стилизация**: Tailwind-like API (`.border_1()`, `.px_2()`, etc.)
- **Рендеринг**: Через WGPU с платформенными бэкендами (Metal/DirectX/Vulkan)

### 2. Entity-система GPUI
- `Entity<T>` — handle на состояние типа T
- `Context<T>` — контекст при обновлении Entity
- `Window` — доступ к состоянию окна (фокус, действия, инпут)
- `AsyncApp` / `AsyncWindowContext` — асинхронные контексты

### 3. Concurrency Model
- **Главный поток**: Все Entity и UI-рендеринг
- **Background spawn**: Вычислительные задачи на тредпуле
- **Task cancellation**: Задачи отменяются при дропе `Task<R>`
- **Weak entities**: `WeakEntity<T>` для предотвращения утечек памяти

### 4. Rendering Pipeline
- `Render` trait для компонентов с состоянием
- `RenderOnce` trait для stateless компонентов
- Flexbox layout через Taffy
- Стилизация через builder-паттерн (`.px_2().bg().text_blue()`)

### 5. Event System
- **Actions**: Клавиатурные события и программные действия
- **Entity events**: `cx.emit()` + `cx.subscribe()` для коммуникации между Entity
- **Notifications**: `cx.notify()` для перерисовки
- **Observers**: `cx.observe()` для отслеживания изменений других Entity

## Component Relationships

### Editor-centric Architecture
```
Workspace
  ├── Project
  │     ├── Worktree (файловая система)
  │     ├── Language Server (LSP)
  │     ├── Buffer (текстовый буфер)
  │     └── Diagnostics
  ├── Editor (отображение буфера)
  │     ├── Syntax highlighting
  │     ├── Inlay hints
  │     ├── Completions
  │     └── Code actions
  ├── Panel (панели)
  │     ├── ProjectPanel
  │     ├── TerminalPanel
  │     ├── OutinePanel
  │     ├── AgentPanel
  │     └── ...
  └── Toolbar / TitleBar
```

### AI/Agent Architecture
```
Agent Panel (agent_ui)
  ├── Agent (agent)
  │     ├── LanguageModel (language_model)
  │     ├── ContextServer (context_server)
  │     ├── WebSearch (web_search)
  │     └── Tools (acp_tools)
  ├── Providers
  │     ├── Anthropic
  │     ├── OpenAI
  │     ├── Google AI
  │     ├── DeepSeek
  │     ├── Ollama
  │     └── ...
  └── Agent Servers (agent_servers) — ACP-based
```

### Collaboration Architecture
```
Client (client)
  ├── RPC (rpc) — protobuf-сообщения
  ├── Channel (channel)
  ├── Call (call) + LiveKit (WebRTC)
  └── Collab Server (collab)
        ├── Database (db)
        ├── RPC handler
        └── Real-time sync
```

## Design Patterns

1. **Entity-Component**: Все UI-элементы — Entity с состоянием и Render
2. **Builder Pattern**: Конфигурация UI-элементов через цепочки методов
3. **Async/Spawn Pattern**: Асинхронные операции через `cx.spawn` с `WeakEntity`
4. **Observer Pattern**: `cx.observe()` / `cx.subscribe()` для реактивного обновления
5. **Command Pattern**: Actions для всех пользовательских взаимодействий
6. **Type-State Pattern**: В некоторых компонентах для гарантий на этапе компиляции

## Code Organization

- **No `mod.rs`**: Файлы модулей именуются по имени модуля
- **Library root naming**: `[lib] path = "gpui.rs"` вместо `lib.rs`
- **Crate naming conventions**:
  - `*_ui` — UI-компонент (например, `agent_ui`, `collab_ui`)
  - `*_tools` — тулзы/утилиты (например, `debugger_tools`, `acp_tools`)
  - `*_macros` — proc-макросы (например, `gpui_macros`, `ui_macros`)
  - `gpui_*` — части GPUI фреймворка
  - `*_preview` — превью-компоненты
  - `*_settings` — настройки