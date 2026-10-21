# 15 — DATA CONTRACTS & CONFIGURATION

> Псевдоструктуры иллюстрируют контракты. Это **не готовый Luau код** и не повод Astra пропускать типизацию, реальные тесты и аудит существующего проекта.

## 1. Идентификаторы, которые должны оставаться стабильными

```text
MAP_REACTOR_YARD
RUN_STANDARD_SOLO
W_ARC_RIFLE, W_SCATTERGUN, W_PLASMA_BEAM
EV_THUNDERLORD, EV_INFERNO_GRINDER, EV_VOID_LANCE
CORE_STORM, CORE_EMBER, CORE_VOID
EN_RUNNER, EN_STALKER, EN_SPITTER, EN_BULWARK
ELITE_BULWARK, BOSS_BROODMOTHER
OBJECT_COIL, OBJECT_GATE, OBJECT_HIVE
EVENT_HIVE_BREACH
SYN_CHAIN_RICOCHET, SYN_IGNITE_DETONATE
```

Модули upgrade: `UPG_CHAIN`, `UPG_RICOCHET`, `UPG_PIERCE`, `UPG_IGNITE`, `UPG_DETONATE`, `UPG_CORRODE`, `UPG_FREEZE`, `UPG_MULTISHOT`, `UPG_FIRERATE`, `UPG_CRIT`, `UPG_DASH_SHOCK`, `UPG_SHIELD`.

## 2. Примеры typed config (псевдо-Luau)

```lua
RunConfig = {
  id = "RUN_STANDARD_SOLO",
  levelId = "MAP_REACTOR_YARD",
  targetSeconds = 480, hardLimitSeconds = 540,
  bossStartSeconds = 420,
  starterWeaponId = "W_ARC_RIFLE",
  spawnActiveCap = 70, -- placeholder, real-device profile mandatory
  runSeed = nil, -- assigned on server
}

WeaponDefinition = {
  id = "W_ARC_RIFLE",
  shotDamage = 12, roundsPerSecond = 6, rangeStuds = 85,
  magazine = 36, reloadSeconds = 1.5,
  allowedUpgrades = {"UPG_CHAIN", "UPG_RICOCHET", "UPG_PIERCE"},
}

EvolutionRecipe = {
  id = "EV_THUNDERLORD", baseWeapon = "W_ARC_RIFLE",
  requiredUpgrades = {"UPG_CHAIN", "UPG_RICOCHET"},
  requiredCore = "CORE_STORM",
  requiresExplicitPlayerConfirmation = true,
}
```

## 3. Authoritative run state (пример интерфейса)

```text
RunState {
  runId: string, ownerUserId: number, seed: number,
  phase: "PREPARE"|"ACTIVE"|"UPGRADE"|"EVENT"|"BOSS"|"FINISHED",
  elapsedSeconds: number, playerHealth: number,
  weaponId: WeaponId, activeUpgrades: set<UpgradeId>,
  availableCores: set<CoreId>, evolutionId?: EvolutionId,
  overdriveCharge: number, aliveEnemiesById: map<EnemyId, EnemyState>,
  selectedOfferId?: string, selectedChoices?: UpgradeId[3],
  accumulatedXP: number, eventFlags: map<string,bool>,
  result?: {outcome: "VICTORY"|"DEFEAT"|"ABORT", reason:string}
}
```

При соло-паузе используйте отдельный `effectiveSimulationElapsed`: фаза не движется, враги не наносят урон, дот не тикает. Серверный wall-clock нужен отдельно для диагностики и ограничений, не должен перескакивать gameplay время.

## 4. Registry & validation

Все IDs проверять при startup: отсутствующие референсы модификаторов/ядра/модели должны логировать явную ошибку/не запускать повреждённый run. Нельзя выдавать `nil` weapon. Схемы конфигов — централизованные shared enums; сервер по ID находит собственный authoritative data. Клиент не управляет произвольными JSON/Instances от собственного имени.

## 5. Debug seeds и тестовые конфигурации

`SEED_FEEL_01`: starter, runner, первый upgrade chain. `SEED_EVOLUTION_01`: chain→ricochet→elite core→Thunderlord. `SEED_FIRE_01`: ignite + detonate и 20 целей. `SEED_BOSS_01`: полный билд, старт босса. Реальные числовые seed значения разработчик назначает в фикстурах и записывает, не притворяться, что фиксированные имена гарантируют одни и те же RNG результаты до реализации.

## 6. Version compatibility

Config registry version и save profile version не путать. При удалении upgrade из контента иметь fallback mapping/reconcile для старых профилей после P2. Все сериализуемые поля явно ограничены типами, списки capped. `RunResult` отправляется ровно один раз клиенту логически; повтор транспорта не порождает повторную выдачу.
