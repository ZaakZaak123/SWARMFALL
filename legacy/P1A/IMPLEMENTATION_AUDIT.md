# P0 audit — 2026-10-21

Прочитаны README, docs/01–16, assets/LEVEL01_TOPDOWN.svg и agent templates.
Исходное состояние: 23 файла production pack; нет .git, Luau, rbxl/rbxlx,
Rojo project, dependency manifest, тестов или импортированных моделей/звуков.
AGENTS.md в проекте и родительских каталогах не найден. Пользовательская игра не изменяется.

| Требование | Реальность P0 | Решение P1A |
|---|---|---|
| Reactor Yard 360×320, 5 зон, обходы | Только SVG/PNG | Собрать edit-time Parts из единого layout |
| Elevated camera, PC/touch | Нет | Local camera, WASD/default thumbstick + правый aim stick |
| W_ARC_RIFLE, server hits | Нет | Intent-only remote, authoritative ammo/raycast/damage |
| Runner/Stalker | Нет | Data simulation, flow field, client interpolated models |
| 60–90 секунд | Нет | 75 секунд + results/replay |
| Hit SFX/VFX/death | Нет | Штатные Roblox sounds, primitive silhouettes, bounded effects |
| Debug/perf | Нет | Studio-only actual count, rolling frame percentiles, sim ms |
| Studio | Установлена; MCP studios=[] при аудите | Запустить отдельный локальный place, проверить доступ |
| Build | Python 3.14; Rojo shim выдаёт os error 50 | Dependency-free Python XML builder + optional Rojo mapping |
| Phone QA | Нет подключённого устройства | Владелец выполняет реальный touch/feel/perf acceptance |

Gate P0 internal check: PASS для перехода к реализации. Путь открытия —
`build/SWARMFALL_P1A.rbxlx`, команда сборки `python tools/build.py`.
Секреты/публикация для локального Play не нужны. Studio/phone PASS не подразумевается.

Инвентарь оригиналов сохранён в MANIFEST_SHA256.txt. Новые исходники размещаются
в src/, tools/, tests/; доказательства — evidence/; артефакты — build/.
