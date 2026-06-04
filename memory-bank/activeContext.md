# Active Context: RZed (fork of Zed)

## Current Focus

Форк Zed в `rzed` (hvkeyn/rzed): Windows-сборка, отключён Zed Cloud, ребрендинг RZed.

### Текущая сессия
- Ребрендинг: `APP_NAME` = RZed, бинарник `rzed.exe`, иконка cyberpunk «Rz», bundle id `dev.rzed.*`
- Отключена Zed Cloud авторизация (`client::CLOUD_AUTH_ENABLED = false`, `show_sign_in: false`)
- Починена сборка под Windows (MSVC 14.44, SDK 10.0.26100, WebRTC STL, `tooling/msvc_spectre_libs`)
- Git: `origin` → `https://github.com/hvkeyn/rzed.git`, `upstream` → zed-industries/zed

## Recent Changes

- `build.ps1`, Memory Bank, патчи линковки Windows
- Очистка `target/` (incremental, deps) при нехватке места на диске

## Key Paths

| Путь | Назначение |
|---|---|
| `target/x86_64-pc-windows-msvc/debug/rzed.exe` | Debug-бинарник RZed |
| `script/update_rzed_icons.py` | Пересборка PNG/ICO из исходника |
| `crates/paths` | `APP_NAME` / каталоги данных |

## Next Steps

Собрать `rzed.exe` после очистки диска; при необходимости `git push` / синхронизация с upstream.
