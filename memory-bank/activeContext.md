# Active Context: Zed Code Editor

## Current Focus

Настройка проекта для эффективной работы агентов в Zed. Проект представляет собой форк или локальную копию репозитория Zed (директория `rzed`), с настроенными агентскими инструментами и Memory Bank.

### Текущая сессия
- Отключена Zed Cloud авторизация в rZed (`client::CLOUD_AUTH_ENABLED = false`, без автологина при старте, `show_sign_in: false`)
- Починена сборка Zed под Windows (debug, x86_64)
- Установлены: Windows SDK 10.0.26100, VS 2022 Community (MSVC 14.44 + Spectre libs)
- Патч `tooling/msvc_spectre_libs` для python-environment-tools без жёсткого требования Spectre
- Линковка WebRTC STL через `crates/zed/build.rs` (libcpmt из newest MSVC)
- Git: `origin` → `https://github.com/zed-industries/zed.git` (без fork hvkeyn); `main` rebased на актуальный upstream + 1 локальный коммит

## Recent Changes

- Создан Memory Bank в `memory-bank/` (все core-файлы)
- Задокументирована структура проекта, технологии и паттерны
- Создан `build.ps1` — скрипт полной сборки и дистрибуции Zed под Windows
- **Сборка debug успешна**: `target/x86_64-pc-windows-msvc/debug/zed.exe` (~454 MB)

## Active Decisions

1. **Memory Bank**: Принято решение создать Memory Bank с 6-ю core-файлами для сохранения контекста между сессиями
2. **Структура документации**: Описана иерархия crate'ов, ключевые архитектурные решения и паттерны

## Project Configuration (from `.zed/settings.json`)

- Язык: Rust (основной)
- Форматтеры: `auto` (prettier для JSON/Markdown/YAML/CSS/JS, rustfmt для Rust)
- Табы: пробелы
- Удаление trailing whitespace при сохранении: да
- Финальный newline: да
- LSP: rust-analyzer (proc macros: 4 процесса)
- Отладка: CodeLLDB или GDB

## Key Files & Directories

| Путь | Назначение |
|---|---|
| `.rules` | Глобальные правила для AI-агентов (Rust, GPUI, PR hygiene) |
| `.agents/skills/` | Локальные навыки агентов (gpui-test, zed-cherry-pick) |
| `.factory/` | Промпты для краш-анализа и навыки (brand-writer, humanizer) |
| `.github/workflows/` | ~40+ CI/CD workflow'ов |
| `.zed/` | Настройки редактора Zed для этого проекта |
| `crates/` | ~200+ crate'ов workspace |
| `docs/` | mdBook-документация |
| `extensions/` | Встроенные расширения (glsl, html, proto) |
| `script/` | Билд-скрипты и утилиты (более 100) |
| `tooling/` | Вспомогательные тулы (compliance, perf, xtask) |
| `assets/` | Ресурсы (шрифты, иконки, темы, звуки, keymaps, промпты) |

## Next Steps

Memory Bank создан и готов к использованию. Следующие шаги зависят от конкретных задач, которые будут поставлены.