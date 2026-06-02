# Technical Context: Zed Code Editor

## Technologies Used

### Язык программирования
- **Rust** (edition 2024) — основной язык проекта
- Rust toolchain: **1.95.0** (строго зафиксирован в `rust-toolchain.toml`)

### Ключевые технологические решения

| Технология | Назначение |
|---|---|
| **GPUI** | Собственный GPU-ускоренный UI-фреймворк (подобен React, но нативный) |
| **Tree-sitter** | Инкрементальный парсинг кода (создатель — основатель Zed) |
| **WGPU** | Кроссплатформенный GPU-рендеринг (через `gpui_wgpu`) |
| **WebRTC / LiveKit** | Аудио/видео звонки для коллаборации |
| **SQLite (heed/libsqlite3)** | Локальная БД для настроек, кеша, телеметрии |
| **Prost/Protobuf** | RPC-коммуникация с коллаборационным сервером |
| **WASM (wasm32-wasip2)** | Песочница для расширений |
| **mdBook** | Генерация документации |

### Платформенные бэкенды GPUI
- `gpui_macos` — macOS (Metal)
- `gpui_linux` — Linux (X11/Wayland через WGPU)
- `gpui_windows` — Windows (DirectX через WGPU)
- `gpui_web` — Web (WASM, экспериментально)

### Интегрированные LLM-провайдеры
- Anthropic, OpenAI, Google AI, DeepSeek, Mistral, Codestral
- Ollama, LM Studio, OpenRouter, X.AI, Bedrock, Copilot, OpenCode

### Инструменты разработки

| Инструмент | Назначение |
|---|---|
| `cargo` / `rustc` | Сборка |
| `rust-analyzer` | LSP для Rust |
| `rustfmt` (edition 2024) | Форматирование кода |
| `clippy` | Линтинг (с кастомным `clippy.toml`) |
| `nextest` | Запуск тестов |
| `prettier` | Форматирование Markdown/JSON/YAML |

### Инфраструктура
- Docker Compose (MinIO blob store + LiveKit server)
- Procfile для локального запуска сервисов
- GitHub Actions (CI/CD, ~40+ workflows)
- Cloudflare (документация)
- Sentry (crash reporting)

## Development Setup

### Локальный запуск
```sh
# Зависимости
./script/install-linux  # или install.sh / bootstrap

# Сборка и запуск
cargo run -p zed

# Сборка отдельного крейта
cargo build -p gpui
```

### Локальные сервисы (для коллаборации)
```sh
# БД
./script/reset_db
# LiveKit + MinIO
docker compose up
# Сервер коллаборации
cargo run -p collab serve all
```

### Scripts (./script/)
- `./script/clippy` — линтинг (всегда использовать вместо `cargo clippy`)
- `./script/cargo` — обёртка над cargo
- `./script/bundle-*` — сборка под разные платформы
- `./script/linux`, `./script/freebsd` — платформенные скрипты
- `./script/randomized-test-ci` — рандомизированные тесты
- `./script/sentry-fetch` — получение крешей из Sentry

## Technical Constraints

1. **Однопоточный UI**: Вся работа с Entity и UI рендеринг — на главном потоке. Фоновые задачи — через `cx.background_spawn`.
2. **Нельзя блокировать главный поток**: Запрещён `std::process::Command` — использовать `smol::process::Command`.
3. **Без unwrap()**: Все ошибки должны быть обработаны через `?` или `log_err()`.
4. **No mod.rs**: Файлы модулей называются как сам модуль (`src/gpui.rs`, а не `src/gpui/mod.rs`).
5. **Edition 2024**: Rust и rustfmt используют edition 2024.
6. **Платформенный код**: Изолирован в `gpui_linux`, `gpui_macos`, `gpui_windows`.
7. **WASM-расширения**: Компилируются в `wasm32-wasip2`.
8. **Remote server**: Компилируется в `x86_64-unknown-linux-musl`.

## Dependencies (ключевые)

- **UI**: `gpui` (собственный), `accesskit` (accessibility), `cocoa` (macOS)
- **Async runtime**: `async-std`/`smol` + `tokio` (через `gpui_tokio`)
- **RPC**: `prost` (protobuf), `rpc` (собственный)
- **Работа с данными**: `serde`, `heed` (LMDB), `libsqlite3-sys`, `sum_tree` (собственный)
- **Парсинг**: `tree-sitter`, `pulldown-cmark` (Markdown)
- **Сеть**: `reqwest`, `http_client` (собственный), `tungstenite` (WebSocket)
- **Медиа**: `livekit`, `libwebrtc`, `rodio` (аудио), `image`
- **Терминал**: `alacritty_terminal` (форк), `portable-pty`
- **Git**: `git2`, `ignore`