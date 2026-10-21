--!strict
export type Enemy = {
	id: number, kind: string, pos: Vector3, hp: number, state: string,
	untilTime: number, cooldown: number, aim: Vector3, stagger: number,
}
export type Snapshot = {
	runId: string, phase: string, elapsed: number, remaining: number,
	hp: number, ammo: number, reload: number, kills: number, activeEnemyCount: number,
	enemies: {{any}}, owner: number?, result: string?, dash: number,
}
return {}
