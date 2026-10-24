# SPOREFALL (ex-SWARMFALL) — рабочие правила для Claude

Владелец поручил **полностью автономную разработку** всей игры (см. `design/handoff/CLAUDE.md`). Решения по механикам, балансу, UX принимай сам, записывай в `DESIGN_DECISIONS.md`. Согласование нужно только для: платных трат, публикации в live, удаления реальных DataStore, отказа от концепции.

## С чего начинать каждую сессию

1. `PROGRESS.md` — текущий этап, что сделано, **следующий шаг**. Начинай с него.
2. `DESIGN_DECISIONS.md` — уже принятые решения (не переоткрывай их).
3. Дизайн читай **точечно** под задачу (Grep по `design/handoff/`), не целиком: документы ~1.5 МБ.
   - Видение: `design/handoff/02_GAME_SPECS/SWARMFALL_MASTER_GDD_v1.0.md` (§5 O01, §9 операции, §7 прогресс, §8 экономика).
   - Бой: `D01_COMBAT_GAMEPLAY_SPEC_v0.3.md`; операции: `D02_OPERATIONS_SPEC_v0.3.md`; прогресс/экономика: `D03_PROGRESSION_ECONOMY_SPEC_v0.3.md`.
   - Числа-кандидаты: `design/handoff/03_GAME_DATA/*.csv` (TUNABLE, меняй по тестам).

## Архитектура (кратко)

- `src/shared/` — `Defs` (контент, баланс), `Maps` (геометрия), `Ops` (операции O01–O06, C-A01), `Codec` (сеть).
- `src/server/Sim/` — чистый Luau, без Instances: `World` (забег), `Mission` (реактор и цели операций), `Combat`, `AI`, `Nav`, `Rng`. Гоняется ботом в Lune.
- `src/server/` — `Main.server` (лобби/забег/результаты, remotes), `Profile` (DataStore), `Arena` (геометрия в Workspace).
- `src/client/` — HUD, меню, FX, камера, риг, звук.
- Сервер авторитетен: клиент шлёт только намерения. Награды идемпотентны по `runId`. Ключ хранения валюты `scrap` **не переименовывать** (в UI — «Ксенит»).

## Проверки (запускать после изменений)

```
rojo build -o build/SWARMFALL.rbxlx
lune run tests/compile
lune run tests/ops_order            (быстро: данные операций)
lune run tests/profile              (быстро: инварианты профиля D03)
lune run tests/hub                  (быстро: отряды лагеря и витрина)
lune run tests/styles               (быстро: стили сборок и синергии; `run <STYLE> [weapon] [seed]` — бот O01 одним стилем)
lune run tests/ops_run O01          (бот играет O01: ~10 мин)
lune run tests/ops_run <O02..CA01>  (бот играет операцию; запускай параллельно в фоне)
lune run tests/sim_run W_ARC_RIFLE  (старый регрессионный прогон)
stylua --check src   (форматирование: только для новых/изменённых файлов)
selene src
```

Studio: MCP `roblox-studio` (execute_luau, start_stop_play, get_console_output, screen_capture с `capture_id`). Не объявляй PASS без реальной проверки — пиши `UNVERIFIED`.

## Дисциплина

- Ветка `reboot/creative` (творческий перезапуск, DD-029…), маленькие коммиты с рабочим состоянием. Новые тесты: `lune run tests/map_check`.
- После каждой вехи обнови `PROGRESS.md` (сделано / проверено / следующий шаг).
- Модели (3D-ассеты) — низкий приоритет, геймплей важнее.
