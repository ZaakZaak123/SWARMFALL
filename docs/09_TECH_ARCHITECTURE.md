# 09 — ROBLOX / LUAU TECH ARCHITECTURE

## 1. Обязательные инженерные принципы

- Roblox server authoritative для HP, damage, спавна, RNG результатов, rewards, cooldowns, доступности эволюций. Клиент: input, камера, UI, VFX/SFX, предикция выстрела.
- Простая дата-ориентированная лёгкая симуляция обычных врагов; не заводить 70 полноценных дорогих Humanoid + pathfinding на каждый tick.
- Все модули конфигурируются через shared read-only definitions, сервер **не** доверяет клиентским копиям и повторно валидирует.
- Только стандартные Roblox/Luau и репозиторные зависимости после аудита. Rojo, Wally, TestEZ — **опциональные**, если уже приняты в проекте; не требовать стороннего платного стека для запуска.
- Поддержать Roblox Studio Play Solo и 2-client Studio test (даже если full-coop отложен), без сетевых exploit дыр.

## 2. Предлагаемая структура (адаптировать существующую, не создавать дубль)

```text
ReplicatedStorage/
  Shared/Definitions/{Weapons,Upgrades,Enemies,RunPhases}.luau
  Shared/Types.luau
  Remotes/{InputFire,InputDash,InputOverdrive,UpgradeSelect,RunSnapshot,FXBatch,RunResult}
ServerScriptService/
  Bootstrap.server.luau
  Services/{RunService,EnemyService,WeaponService,DamageService,
            UpgradeService,DirectorService,EventService,RewardService,AntiAbuseService}
  Systems/{SpatialGrid,EnemySteering,CollisionQueries,ProcBudget}
StarterPlayer/StarterPlayerScripts/
  Controllers/{InputController,CameraController,CombatVFX,HudController,
               UpgradeUIController,AudioController,QualityController}
Workspace/
  Level01/{Geometry,SpawnMarkers,Objects,NavigationHints}
ServerStorage/
  ServerOnlyTemplates/{Enemies,LevelObjects}
```

Скрипты размещаются согласно реальному структурам `.rbxl`/`.rbxlx`/Rojo после аудита; нельзя просто записать дерево папок и заявить, что Studio готова. При наличии существующей игры сначала план миграции.

## 3. Remote contracts (проверяются по типу, времени и состоянию)

- `InputFire(direction: Vector3, clientSequence: number)` — направление нормализовано, ограничен угол/темп, FireRate и состояние оружия проверены сервером. Клиент **не передаёт enemyId и нанесённый damage** как истину. Сервер raycast/shape query по collision layers, ограничение дистанции.
- `InputDash(direction: Vector3, clientSequence: number)` — проверить состояние/кулдаун/дистанцию, защититься от рывка за стену.
- `InputOverdrive(requestSequence: number)` — проверить charge=100 и `ACTIVE`.
- `UpgradeSelect(runId: string, offerId: string, upgradeId: string)` — upgradeId должен быть в текущих 3 предложениях и ещё не выбран; временный `offerId`, consume-once.
- `RunSnapshot` S→C — разреженные authoritative stats, фаза, события, прогресс; `FXBatch` S→C — события для клиентского рендера в бюджете.
- `RunResult` S→C — финальный `runId`, победа/поражение, duration, damage, rewards (P2), без повторных бонусов.

Клиентские RemoteEvents rate-limit per player and command; validate arguments and state; отказ без краша. Не отправлять по сети десятки hit-событий в секунду на каждой цели, если можно агрегировать. Стремиться к прогнозированию локальной картинки при авторитетном серверном damage.

## 4. Enemy simulation и пространственные запросы

- `SpatialGrid`: например cellSize 20 studs, update moving enemy coordinates батчами; seek/radius query O(neighbors) вместо полного поиска на каждом попадании.
- Серверный AI step initial 10Hz для простых преследователей, атаки/состояния по необходимым тикам; визуальная клиентская интерполяция между позициями. Частота — target, не догма.
- У врагов лёгкие модели/скелеты, упрощённые коллизии; навигационные hint-поля и steering вокруг уровня; pathfinding только для редких сложных случаев/босса при необходимости.
- Вражеские смерти и визуальная толпа — клиентские короткие эффекты, контролируемые LOD/cull; server-сущность вовремя удаляется и возвращается в пул.
- Для честности не превращать несуществующую декоративную толпу в дамажащих врагов. Декоративные объекты явно не интерактивны.

## 5. Damage pipeline

`RequestFire → ValidateShot → WorldQuery → DamageResolver → Armor/Status → ProcBudget → Kill/XP/Overdrive → FXBatch`. `damageEvent` содержит `sourceId, runId, targetId, baseDamage, damageType, procDepth, procTags`; `procDepth = 0` первичный, `1` вторичный, `>1` по умолчанию запрещён. Дедупликация по `eventId`/server tick, `maxTargets`, global/per-player proc budget.

**Важное исключение:** описанная в doc.04 синергия «поджог + детонация» — ровно одно допустимое вторичное событие; DOT сам не запускает новую детонацию. Все цепи конечны.

## 6. FPS/Memory/network budgets — предварительные цели, измерить

| Метрика | P1 цель |
|---|---|
| Midrange Android при плотной волне | p95 frame time ≤33.3 мс в 5-мин. тесте (эквивалент целевым ≥30 FPS по 95-му перцентилю), без длительных провалов <25 FPS; измерять реальные frametimes |
| ПК среднего класса | цель 60 FPS; не заявлять как гарантированный результат |
| Одновременные активные враги | начальная гипотеза 70 в solo, cap меняется по профилю |
| Скрипты/физика/рендер | не придумывать жёсткий миллисекундный расклад без MicroProfiler; прикладывать capture и выводы |
| Сеть | не рассылаем покадровые события каждого снаряда каждому клиенту; измерить receive/send KB/s и rate-limit |
| Стабильность | ни одной накопительной утечки по 10 перезапускам забега |

`Workspace.StreamingEnabled` стоит **оценить**, если сцена разрастётся; для компактной арены не включать вслепую и не ломать доступ к критичным моделям. Профилировать MicroProfiler на клиентах и сервере, включая mobile. У LOD есть ступени низких VFX/следов/коротких corpse decals.

## 7. DataStore/Purchases (только P2/P3)

DataStoreService `UpdateAsync`, профиль с `profileVersion`, повторная загрузка без перезаписи при ошибке, idempotent rewards; `ProcessReceipt` обработчик developer products с защитой от повторной выдачи. Не записывать клиентские результаты. После P1 разрешено только записать абстракции, но не запускать магазин.

## 8. Минимальные automated smoke tests

- Нет double-upgrade на повторный `UpgradeSelect`.
- Fire с нелегальным rate/direction не наносит урон.
- `procDepth >1` прекращается, цикл chain bounded.
- У boss reward idempotent.
- Fixed seed даёт ожидаемый offer и spawn-sequence в симулируемом тесте.
- Shutdown/abort освобождает активные враги, UI не зависает.

## 9. Delivery требования

Любое изменение оформляется списком файлов, воспроизводимой командой запуска/сборки, результатами автоматических тестов и manual Studio verification. **Если Studio реально не запускалась, написать «НЕ ПРОВЕРЕНО В STUDIO»**; не подменять проверку статическим обзором Luau. Никакой публикации Production, пользовательских транзакций или перезаписи чужих проектов без отдельного разрешения.
