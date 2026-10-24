// SPOREFALL icon set. Each icon is SVG markup in a 100×100 box.
//   body — drawn white, then shaded (top-lit gradient), outlined and shadowed by build.js
//   cut  — punched out of the body (holes, details)
//   hi   — optional extra highlight shapes (drawn white on top, not outlined)
// Use fill="F" for filled shapes and stroke="F" for stroked ones; build.js substitutes the paint.

const S = (d, w = 10) => `<path d="${d}" fill="none" stroke="F" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;
const P = (d) => `<path d="${d}" fill="F"/>`;
const C = (x, y, r) => `<circle cx="${x}" cy="${y}" r="${r}" fill="F"/>`;
const R = (x, y, r, w) => `<circle cx="${x}" cy="${y}" r="${r}" fill="none" stroke="F" stroke-width="${w}"/>`;
const B = (x, y, w, h, rx = 3, rot = 0) =>
	`<rect x="${x - w / 2}" y="${y - h / 2}" width="${w}" height="${h}" rx="${rx}" fill="F"${rot ? ` transform="rotate(${rot} ${x} ${y})"` : ""}/>`;

function star(cx, cy, n, r1, r2, rot = -90) {
	let d = "";
	for (let i = 0; i < n * 2; i++) {
		const a = ((rot + (i * 180) / n) * Math.PI) / 180;
		const r = i % 2 ? r2 : r1;
		d += (i ? "L" : "M") + (cx + Math.cos(a) * r).toFixed(2) + " " + (cy + Math.sin(a) * r).toFixed(2);
	}
	return d + "Z";
}

function gearPath(cx, cy, n, ro, ri, tw) {
	let d = "";
	for (let i = 0; i < n; i++) {
		const a0 = (i / n) * Math.PI * 2;
		const h = (Math.PI / n) * tw;
		const pts = [
			[a0 - h * 1.25, ri],
			[a0 - h, ro],
			[a0 + h, ro],
			[a0 + h * 1.25, ri],
		];
		for (const [a, r] of pts) {
			d += (d ? "L" : "M") + (cx + Math.cos(a) * r).toFixed(2) + " " + (cy + Math.sin(a) * r).toFixed(2);
		}
	}
	return d + "Z";
}

const rays = (cx, cy, r1, r2, n, w, off = 0) => {
	let out = "";
	for (let i = 0; i < n; i++) {
		const a = off + (i / n) * Math.PI * 2;
		out += S(`M${cx + Math.cos(a) * r1} ${cy + Math.sin(a) * r1}L${cx + Math.cos(a) * r2} ${cy + Math.sin(a) * r2}`, w);
	}
	return out;
};

const ICONS = {
	// --- weapon upgrades ---
	chain: {
		body: P("M60 4 L24 54 L46 54 L36 96 L78 40 L55 40 L68 4 Z"),
		
	},
	ricochet: {
		body: S("M10 86 L44 30 L72 64", 9) + P("M90 80 L60 76 L82 54 Z") + C(44, 30, 9),
		cut: `<circle cx="44" cy="30" r="3.5"/>`,
	},
	pierce: {
		body: R(32, 50, 14, 7) + R(60, 50, 14, 7) + S("M6 50 L80 50", 8) + P("M96 50 L74 34 L78 50 L74 66 Z"),
	},
	fire: {
		body: P(
			"M50 96 C27 96 16 80 18 62 C20 46 30 40 32 26 C40 34 42 42 42 48 C48 38 50 22 46 4 C66 16 82 38 82 62 C82 82 70 96 50 96 Z",
		),
		cut: `<path d="M50 90 C40 90 34 82 35 72 C36 64 42 60 44 52 C50 58 52 62 52 66 C56 62 58 58 58 52 C64 58 66 66 66 72 C66 84 59 90 50 90 Z"/>`,
		hi: `<path d="M50 88 C44 88 41 83 42 77 C43 72 47 70 48 65 C52 69 54 72 54 76 C57 74 58 72 58 70 C61 74 60 78 59 81 C58 86 55 88 50 88 Z" fill="F"/>`,
	},
	burst: {
		body: P(star(50, 50, 8, 46, 20, -90)) ,
		cut: `<circle cx="50" cy="50" r="9"/>`,
	},
	drop: {
		body: P("M50 6 C50 6 18 44 18 64 C18 82 32 95 50 95 C68 95 82 82 82 64 C82 44 50 6 50 6 Z"),
		cut: `<path d="M36 62 C36 54 42 46 46 41 C44 50 42 56 42 64 C42 70 44 75 48 78 C40 78 36 70 36 62 Z"/>`,
	},
	snow: {
		body:
			rays(50, 50, 0, 44, 6, 8, Math.PI / 2) +
			(() => {
				let o = "";
				for (let i = 0; i < 6; i++) {
					const a = Math.PI / 2 + (i / 6) * Math.PI * 2;
					const bx = 50 + Math.cos(a) * 28;
					const by = 50 + Math.sin(a) * 28;
					for (const s of [-1, 1]) {
						const b = a + s * 0.85;
						o += S(`M${bx} ${by}L${bx + Math.cos(b) * 12} ${by + Math.sin(b) * 12}`, 6);
					}
				}
				return o;
			})() +
			P(star(50, 50, 6, 15, 9, -90)),
	},
	fan: {
		body: P("M50 92 L10 30 C22 18 36 12 50 12 C64 12 78 18 90 30 Z"),
		cut: `<path d="M50 80 L44 24 L56 24 Z"/><path d="M50 80 L22 34 L30 28 Z"/><path d="M50 80 L78 34 L70 28 Z"/>`,
	},
	chevrons: {
		body: S("M14 18 L42 50 L14 82", 13) + S("M48 18 L76 50 L48 82", 13) + S("M80 32 L94 50 L80 68", 8),
	},
	crosshair: {
		body: R(50, 50, 30, 8) + S("M50 4 L50 28", 8) + S("M50 72 L50 96", 8) + S("M4 50 L28 50", 8) + S("M72 50 L96 50", 8) + C(50, 50, 8),
	},
	dashbolt: {
		body: S("M6 32 L34 32", 7) + S("M2 50 L28 50", 7) + S("M6 68 L34 68", 7) + P("M72 4 L42 52 L60 52 L50 96 L88 42 L68 42 L82 4 Z"),
	},
	shield: {
		body: P("M50 4 L88 18 L88 46 C88 70 72 86 50 96 C28 86 12 70 12 46 L12 18 Z"),
		cut: `<path d="M50 16 L76 26 L76 46 C76 64 66 76 50 84 C34 76 24 64 24 46 L24 26 Z"/>`,
		hi: `<path d="M50 24 L68 31 L68 46 C68 60 61 69 50 75 C39 69 32 60 32 46 L32 31 Z" fill="F"/>` ,
	},
	plus: {
		body: P("M38 8 H62 V38 H92 V62 H62 V92 H38 V62 H8 V38 H38 Z"),
	},
	battery: {
		body: `<rect x="8" y="26" width="72" height="48" rx="9" fill="F"/>` + B(86, 50, 10, 20, 3),
		cut: `<rect x="16" y="34" width="56" height="32" rx="4"/>`,
		hi: P("M50 30 L30 54 L44 54 L38 70 L60 46 L46 46 Z"),
	},
	dash: {
		body: S("M4 50 L36 50", 8) + S("M34 18 L64 50 L34 82", 13) + S("M60 18 L90 50 L60 82", 13),
	},
	sun: {
		body: C(50, 50, 21) + rays(50, 50, 30, 45, 8, 8, Math.PI / 8),
		cut: `<circle cx="50" cy="50" r="10"/>`,
	},
	evolve: {
		body: S("M18 64 L50 32 L82 64", 12) + S("M18 90 L50 58 L82 90", 12) + P(star(50, 12, 4, 12, 4, -90)),
	},
	reload: {
		body: `<path d="M78 34 A32 32 0 1 0 82 60" fill="none" stroke="F" stroke-width="10" stroke-linecap="round"/>` + P("M90 14 L88 44 L62 34 Z"),
	},
	heart: {
		body: P("M50 90 C20 68 6 52 6 34 C6 20 17 9 31 9 C40 9 46 14 50 21 C54 14 60 9 69 9 C83 9 94 20 94 34 C94 52 80 68 50 90 Z"),
	},
	skull: {
		body: P("M50 6 C26 6 12 22 12 44 C12 58 20 66 26 70 L26 86 C26 90 30 94 34 94 L66 94 C70 94 74 90 74 86 L74 70 C80 66 88 58 88 44 C88 22 74 6 50 6 Z"),
		cut: `<ellipse cx="35" cy="46" rx="10" ry="11"/><ellipse cx="65" cy="46" rx="10" ry="11"/><path d="M50 58 L44 70 L56 70 Z"/><rect x="38" y="80" width="5" height="14"/><rect x="47.5" y="80" width="5" height="14"/><rect x="57" y="80" width="5" height="14"/>`,
	},
	timer: {
		body: R(50, 56, 34, 9) + S("M50 56 L50 36", 8) + S("M50 56 L64 66", 8) + B(50, 12, 20, 9, 3) + S("M80 22 L88 30", 7),
	},
	level: {
		body: S("M16 52 L50 18 L84 52", 13) + S("M16 84 L50 50 L84 84", 13),
	},
	core: {
		body: P("M50 4 L90 50 L50 96 L10 50 Z"),
		cut: `<path d="M50 22 L74 50 L50 78 L26 50 Z"/>`,
		hi: P("M50 34 L64 50 L50 66 L36 50 Z"),
	},
	hammer: {
		body: `<g transform="rotate(-40 50 50)"><rect x="18" y="8" width="64" height="34" rx="7" fill="F"/>${B(50, 66, 13, 56, 5)}</g>`,
		cut: `<g transform="rotate(-40 50 50)"><rect x="18" y="22" width="64" height="5"/></g>`,
	},
	reactor: {
		body: R(50, 50, 30, 8) + C(50, 50, 15) + rays(50, 50, 37, 47, 6, 8, Math.PI / 6),
		cut: `<circle cx="50" cy="50" r="6"/>`,
	},
	hive: {
		body: C(50, 64, 27) + C(26, 38, 16) + C(74, 36, 18) + C(50, 18, 13),
		cut: `<circle cx="46" cy="62" r="7"/><circle cx="72" cy="36" r="6"/><circle cx="26" cy="40" r="5"/><circle cx="50" cy="18" r="4"/>`,
	},
	crown: {
		body: P("M10 30 L30 52 L50 18 L70 52 L90 30 L82 78 L18 78 Z") + B(50, 86, 66, 10, 3),
		cut: `<circle cx="50" cy="62" r="6"/><circle cx="32" cy="64" r="4"/><circle cx="68" cy="64" r="4"/>`,
	},
	elite: {
		body: P(star(50, 50, 8, 46, 30, -90)),
		cut: `<circle cx="50" cy="50" r="13"/>`,
	},
	coil: {
		body: R(50, 50, 36, 8) + P("M58 14 L32 54 L50 54 L42 86 L68 46 L50 46 Z"),
	},
	gear: {
		body: P(gearPath(50, 50, 8, 46, 34, 0.55)) + C(50, 50, 35),
		cut: `<circle cx="50" cy="50" r="14"/>`,
	},
	threat: {
		body: P("M50 6 C53 6 55 8 57 11 L94 80 C97 86 93 92 87 92 L13 92 C7 92 3 86 6 80 L43 11 C45 8 47 6 50 6 Z"),
		cut: `<rect x="44" y="32" width="12" height="32" rx="5"/><circle cx="50" cy="76" r="6.5"/>`,
	},
	pin: {
		body: P("M50 96 C50 96 16 60 16 36 C16 17 31 4 50 4 C69 4 84 17 84 36 C84 60 50 96 50 96 Z"),
		cut: `<circle cx="50" cy="36" r="13"/>`,
	},
	reroll: {
		body:
			`<path d="M80 40 A31 31 0 0 0 22 34" fill="none" stroke="F" stroke-width="10" stroke-linecap="round"/>` +
			`<path d="M20 60 A31 31 0 0 0 78 66" fill="none" stroke="F" stroke-width="10" stroke-linecap="round"/>` +
			P("M94 28 L84 54 L66 36 Z") +
			P("M6 72 L16 46 L34 64 Z"),
	},
	banish: {
		body: R(50, 50, 36, 11) + S("M25 25 L75 75", 11),
	},
	lock: {
		body: `<path d="M30 44 V32 A20 20 0 0 1 70 32 V44" fill="none" stroke="F" stroke-width="10"/>` + `<rect x="16" y="42" width="68" height="52" rx="9" fill="F"/>`,
		cut: `<circle cx="50" cy="64" r="8"/><rect x="46" y="66" width="8" height="16" rx="3"/>`,
	},
	magnet: {
		body: `<path d="M22 10 V52 A28 28 0 0 0 78 52 V10" fill="none" stroke="F" stroke-width="20"/>`,
		cut: `<rect x="8" y="20" width="84" height="5"/>`,
	},
	eye: {
		body: P("M4 50 C18 26 34 16 50 16 C66 16 82 26 96 50 C82 74 66 84 50 84 C34 84 18 74 4 50 Z"),
		cut: `<circle cx="50" cy="50" r="22"/>`,
		cut2: `<circle cx="45" cy="45" r="4"/>`,
		hi: C(50, 50, 12),
	},
	xp: {
		body: P("M50 4 L86 50 L50 96 L14 50 Z"),
		cut: `<path d="M50 26 L68 50 L50 74 L32 50 Z"/>`,
	},
	star: {
		body: P(star(50, 53, 5, 46, 20, -90)),
	},
	check: {
		body: S("M14 52 L40 78 L88 24", 14),
	},
	swords: {
		body: S("M18 18 L72 72", 9) + S("M82 18 L28 72", 9) + S("M62 84 L84 62", 9) + S("M16 62 L38 84", 9) + C(86, 86, 7) + C(14, 86, 7),
	},
	boom: {
		body: P(star(50, 50, 10, 47, 24, -90)),
		cut: P(star(50, 50, 10, 26, 14, -72)).replace('fill="F"', ""),
	},
	play: {
		body: P("M26 12 C26 8 30 6 34 8 L86 44 C90 47 90 53 86 56 L34 92 C30 94 26 92 26 88 Z"),
	},
	topdown: {
		body: `<rect x="14" y="40" width="72" height="50" rx="7" fill="none" stroke="F" stroke-width="7"/>` + S("M50 44 L50 86", 5) + S("M18 65 L82 65", 5) + S("M50 4 L50 28", 8) + S("M38 18 L50 30 L62 18", 8),
	},
	person: {
		body: C(50, 24, 17) + P("M18 92 C18 66 30 50 50 50 C70 50 82 66 82 92 Z"),
	},
	users: {
		body: C(34, 30, 15) + C(68, 30, 15) + P("M6 88 C6 66 18 52 34 52 C46 52 54 60 56 70 L56 88 Z") + P("M44 88 C44 66 54 52 68 52 C84 52 94 66 94 88 Z"),
	},
};

module.exports = ICONS;
