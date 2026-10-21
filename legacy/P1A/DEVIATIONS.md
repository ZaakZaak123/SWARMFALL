# Decisions and deviations

## ADR-001 — Empty specification pack
Options: require an existing place, or create a separate reproducible local place.
Choose the latter as explicitly authorized. Originals preserved; no publish.
Python standard-library XML builder avoids the failing local Rojo shim. Generated
place contains geometry in Edit mode and embedded real scripts, not an installer.

## ADR-002 — P1A scope and budget
Full P1 documents describe 8 minutes, 70 enemies, upgrades and objects with events.
Gate 12 and the user restrict this task to P1A. Use 75 seconds, max 48, only two
enemy roles and rifle. No fake upgrade/XP/Overdrive controls. Gates are open
structural landmarks; coil/hives are future event sites, not advertised interactables.
Cap is a hypothesis, not measured mobile capacity. P1B is not implemented.

## ADR-003 — Navigation and camera
Use a shared static rectangular collision layout and one bounded flow field, with
spatial separation. No Humanoid/pathfinding per enemy. Fixed north-facing camera
(north is +Z), 50 degree pitch; horizontal cursor/aim plane. High decor is faded
locally. Server query uses current enemy state; no lag compensation in P1A.

## ADR-004 — Audio/art
Use original Part-based silhouettes and bundled rbxasset://sounds content.
No upload/marketplace dependency. Audible loading and subjective weapon feel
remain acceptance tests; these are provisional sound designs, not final gun assets.

## ADR-005 — Session boundary
One active solo owner per server. Additional Studio clients explicitly spectate;
they cannot send owner actions. This supports misuse testing without claiming coop.
Movement validation is tolerant token-budget + swept static collision, not a
production anti-cheat or a claim of zero false positives under arbitrary latency.
