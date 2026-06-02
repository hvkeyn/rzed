# Progress: Zed Code Editor

## What Works (состояние проекта в целом)

### Core
- [x] GPU-ускоренный UI-фреймворк (GPUI)
- [x] Редактор с подсветкой синтаксиса (Tree-sitter)
- [x] LSP-интеграция
- [x] Встроенный терминал
- [x] Командная палитра
- [x] Vim mode
- [x] Файловый менеджер (Project Panel)
- [x] Поиск по проекту
- [x] Мультибуферы
- [x] Git-интеграция
- [x] Темы (включая импорт из VS Code)
- [x] Сниппеты

### Collaboration
- [x] Коллаборативное редактирование
- [x] Каналы и чат
- [x] Аудио/видео звонки (LiveKit)
- [x] Шаринг проектов
- [x] Remote development (remote_server)

### AI / Agent
- [x] Agent Panel (чат с LLM)
- [x] Inline Assistant
- [x] Интеграция с Anthropic, OpenAI, Google AI, DeepSeek, Mistral, Codestral
- [x] Локальные модели (Ollama, LM Studio)
- [x] OpenRouter, X.AI, Bedrock, Copilot, OpenCode
- [x] Context Servers (MCP)
- [x] Web Search
- [x] Edit Prediction
- [x] Agent Servers (ACP)
- [x] `/rules` и `.rules` для AI-инструкций
- [x] Prompt Store

### Расширения
- [x] WASM-based расширения (wasm32-wasip2)
- [x] Расширения для языков, тем, LSP
- [x] Extension Marketplace
- [x] Slash Commands в расширениях

### Платформы
- [x] macOS (основная)
- [x] Linux (X11 и Wayland)
- [x] Windows

### Инфраструктура
- [x] CI/CD (GitHub Actions, ~40+ workflow'ов)
- [x] Документация (mdBook + docs_preprocessor)
- [x] Автообновление
- [x] Crash reporting (Sentry)
- [x] Телеметрия

## Known Issues / Active Work

- Web-версия: в разработке, не готова
- Некоторые платформенные особенности в процессе доработки

## Build & Distribution

- [x] `build.ps1` — скрипт автоматической сборки и дистрибуции под Windows
- [x] Debug-сборка `zed.exe` + `cli.exe` + `auto_update_helper.exe` (x86_64-pc-windows-msvc)
- Требования для Windows-сборки: VS 2022 с MSVC **14.44+**, SDK **10.0.26100**, Spectre-mitigated libs, ~40+ ГБ на диске

## Current Status (Memory Bank)

- [x] projectbrief.md — создан
- [x] productContext.md — создан
- [x] activeContext.md — создан
- [x] systemPatterns.md — создан
- [x] techContext.md — создан
- [x] progress.md — создан