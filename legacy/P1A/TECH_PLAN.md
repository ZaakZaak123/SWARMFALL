# P1A implementation plan

1. Shared Config + Layout; build embeds exact source and edit-time geometry.
2. Server owns run, ammo, cooldown, enemy state, movement checks, hits and result.
3. Client owns camera, manual input, HUD, interpolation, bounded sound/VFX.
4. Grid navigation rebuilt at 2 Hz; 10 Hz enemy simulation; no enemy Humanoid.
5. Remote validates types, finite vectors, run nonce, sequence, state and rate.
6. 75-second solo loop; later clients spectate, cannot affect owner.
7. Studio-only startup smoke suite + integration probes; offline build/nav checks.
8. Launch actual Studio; record failures honestly; stop before P1B.

P1 issue list: I01 arena/routes; I02 camera/touch; I03 fire/remote validation;
I04 spawn/steering/stalker telegraph; I05 audio/hit/death; I06 HUD/replay;
I07 real-device acceptance and ten-run stability (requires owner/device).
