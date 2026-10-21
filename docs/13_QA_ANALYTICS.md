# 13 — QA, PLAYTEST & ANALYTICS

## 1. Главный исследовательский вопрос

**«Хочется ли сделать второй забег?»** Внутриигровые FPS и pass tests нужны, но не равны увлекательности. Независимые 10–15 участников — начальный сигнал, а не статистическая валидация D1/D7.

## 2. Playtest формат

Участник без контекста и разработческих подсказок играет два сценария: 1) первый заход до завершения; 2) при желании запускает второй. Интервью после: «когда стало интересно/скучно?», «какое улучшение действительно изменило бой?», «что убило?», «хочешь ещё раз и почему?». Фиксировать наблюдения, а не внушённые ответы.

## 3. Instrumentation P1 (в dev/telemetry без личных данных)

| Event | Поля | Применение |
|---|---|---|
| `run_start` | sessionId, runId, deviceClass, buildVersion, seed | воронка |
| `first_shot` | elapsed, weaponId | time-to-action |
| `first_kill` | elapsed | first fun |
| `upgrade_offer` | elapsed, offerId, 3 upgrade IDs | качество RNG |
| `upgrade_choice` | elapsed, upgradeId, offeredIds | предпочтения |
| `elite_kill` | elapsed, eliteId | pacing |
| `weapon_evolved` | elapsed, evolutionId | достижение power spike |
| `hive_event_result` | completedNests, elapsed | цель внутри рана |
| `boss_start/boss_end` | elapsed, bossHp/killCause | сложность |
| `run_end` | result, elapsed, lastHp, deathCause, kills, damage, build | исход |
| `replay_clicked` | elapsedSinceEnd | непосредственная заинтересованность |
| `perf_sample` | platform, elapsed, avgFps/p95FrameMs, enemyCount, vfxLevel | оптимизация |

Точные telemetry API/хранилище Astra выбирает после аудита без внешних аналитических платных сервисов по умолчанию. Не сохранять IP, device identifiers или другие ненужные персональные данные.

## 4. Основные гипотезы и targets

| Метрика | Первичный критерий |
|---|---|
| Время до первого выстрела | ≤15с для большинства новых пользователей |
| Время до первого убийства | ≤30с |
| Время до первого meaningful upgrade | ≤60с |
| Попытка добровольного replay после первого завершения | ≥60% в закрытом слепом тесте, порог гипотеза |
| Длина победного прохождения | 7:30–8:30 типично; hard cap 9:00 |
| Процент проигрышей на boss | измерить, скорректировать по feedback, не фиксировать искусственную целевую долю |
| D1/D7 retention, DAU, ARPDAU | **только после публичных данных**, не выдумывать |

## 5. Функциональная матрица

- **Game flow:** escape/pause, повторная смерть, disconnect/reconnect, death during modal, replay, boss death в один кадр с player death (серверная детерминированная precedence rule: boss death → victory, если сервер обработал смерть босса прежде player-death; зафиксировать event order).
- **Combat:** hit through wall, burst from client, cooldown hacks, attack outside map, multihit collision, negative health, damage after death, chain cycles.
- **Upgrades:** menu opened twice, selection stale offer, 2 simultaneous selection events, missing recipe key, inactive menu, RF spam.
- **Enemies:** 100 spawn points, path blockage after gate, `NoTarget` under interruption, 10 sequential runs no instance leaks.
- **Visual/mobile:** bad aspect, obstruction, frame drops, screen shake, dash at edge, boss telegraph under low graphics, UI close during shooting.
- **Network:** packet jitter/lag test with simulated latency if feasible, untrusted client, server overload, listener cleanup.

## 6. Repro steps / bug report

Каждая ошибка: build hash, actual platform, screenshot/video, runSeed, time into run, expected, actual, severity, repro, root-cause hypothesis and verified fix. Не объявлять perf improvements без identical-device before/after measurement.

## 7. Visual acceptance

Видеозапись с **реального телефона**, 60–90с: старт, стрельба, гибель толпы, upgrade, эволюция, босс, HUD. Скриншоты игровой камеры, а не только Studio Scene View. Отдельно low VFX доказательство читаемости.
