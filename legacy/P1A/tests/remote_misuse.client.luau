-- Execute in Studio CLIENT while the owner is ACTIVE. Not packaged in the game.
local net=game.ReplicatedStorage.Remotes
local before=net.Snapshot.OnClientEvent:Wait()
assert(before.phase=="ACTIVE","Start a fresh run first")
local badSequence=100000
for _,direction in {Vector3.new(0/0,0,1),Vector3.new(math.huge,0,0),Vector3.zero,Vector3.yAxis,"damage",{damage=999999}} do
	net.Input:FireServer("FIRE",before.runId,badSequence,direction)
end
net.Input:FireServer("FIRE",before.runId,badSequence,Vector3.zAxis,999999)
net.Input:FireServer("FIRE","stale-run",badSequence,Vector3.zAxis)
net.Input:FireServer("DAMAGE",before.runId,badSequence,999999)
task.wait(.3)
local after=net.Snapshot.OnClientEvent:Wait()
assert(after.ammo==before.ammo,"Invalid requests consumed ammo")
assert(after.kills==before.kills,"Invalid requests caused kills")
assert(after.debug.rejected>=before.debug.rejected+9,"Missing rejection evidence")
-- Burst valid directions: duplicate sequence permits exactly one accepted shot.
for _=1,10 do net.Input:FireServer("FIRE",before.runId,badSequence,Vector3.zAxis) end
task.wait(.3)
local duplicate=net.Snapshot.OnClientEvent:Wait()
assert(duplicate.ammo==before.ammo-1,"Duplicate sequence fired multiple shots")
-- Fresh increasing sequences cannot bypass cadence. Window is <1 second.
for i=1,300 do net.Input:FireServer("FIRE",before.runId,badSequence+i,Vector3.zAxis) end
task.wait(.3)
local burst=net.Snapshot.OnClientEvent:Wait()
assert(duplicate.ammo-burst.ammo<=2,"Burst bypassed server cadence")
return {invalidRejected=after.debug.rejected-before.debug.rejected,duplicateShots=before.ammo-duplicate.ammo,
	burstShots=duplicate.ammo-burst.ammo,rejectedTotal=burst.debug.rejected,
	note="Sequence advanced intentionally; restart Play after this destructive QA fixture"}
