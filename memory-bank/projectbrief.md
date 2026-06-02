# Project Brief: Zed Code Editor

## Overview

Zed — высокопроизводительный, многопользовательский редактор кода от создателей Atom и Tree-sitter (Zed Industries, Inc.). Проект с открытым исходным кодом, лицензированный под AGPL/GPL/Apache 2.0.

## Core Requirements & Goals

1. **Высокая производительность**: Нативный рендеринг через собственный GPU-ускоренный UI-фреймворк (GPUI), 120fps, отзывчивость на каждое действие пользователя.
2. **Мультиплатформенность**: macOS, Linux, Windows (нативная поддержка всех трёх платформ).
3. **Коллаборативная работа**: Real-time совместное редактирование, каналы, звонки, чат — через собственный collaboration-сервер (`collab`).
4. **AI-интеграция**: Agent panel, inline assistant, поддержка множества LLM-провайдеров (Anthropic, OpenAI, Google AI, DeepSeek, Mistral, Codestral, Ollama, LM Studio, OpenRouter, X.AI, Bedrock, Copilot, OpenCode).
5. **Расширяемость**: Система расширений (extensions) с поддержкой языков, тем, LSP, formatter'ов.
6. **Эргономичность**: Vim mode, командная палитра, мультибуферы, сниппеты, настраиваемые keybindings.

## Project Scope

- ~200+ crates в workspace
- Собственный GPU UI-фреймворк (GPUI)
- Собственный collaboration-сервер
- Богатая AI/Agent экосистема
- Система расширений (WASM-based)
- CLI-инструменты
- Документация (mdBook-based)

## Source of Truth

- Репозиторий: `github.com/zed-industries/zed`
- Сайт: `zed.dev`
- Документация: `zed.dev/docs`