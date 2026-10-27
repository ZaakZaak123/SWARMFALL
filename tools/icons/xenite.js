// The xenite emblem (DD-095): the currency's own full-colour mark, not a tinted atlas cell.
// Three shards out of one cleft (a tall hexagonal spire flanked by two leaning shards), cut facets in
// four pinks, a dark ink outline and a white four-point heart glowing in the spire.
//   build/icons/xenite.png        256 px, for every UI use (scaled down to 14 px in prices)
//   build/icons/xenite_card.png   the emblem on a dark tile, for review
// Usage: node tools/icons/xenite.js <path to @resvg/resvg-js>
const fs = require("fs");
const path = require("path");
const { Resvg } = require(process.argv[2] || "@resvg/resvg-js");

const INK = "#1B0F26";
const P = { hi: "#FFD3F0", light: "#FF8FDA", mid: "#FF56C6", dark: "#C42490", deep: "#7A1260" };

// One shard: a hexagonal prism with a pointed tip seen from the front, cut into a lit left facet, a
// mid face and a shaded right facet. w half-width, h body height, t tip height, at (x, y) its base.
function shard(x, y, w, h, t, rot) {
	const top = y - h;
	const tip = top - t;
	const ix = w * 0.38; // the inner ridges
	const L = `${x - w},${top} ${x - ix},${top - t * 0.55} ${x - ix},${y + w * 0.3} ${x - w},${y}`;
	const M = `${x - ix},${top - t * 0.55} ${x},${tip} ${x + ix},${top - t * 0.55} ${x + ix},${y + w * 0.3} ${x},${y + w * 0.45} ${x - ix},${y + w * 0.3}`;
	const R = `${x + ix},${top - t * 0.55} ${x + w},${top} ${x + w},${y} ${x + ix},${y + w * 0.3}`;
	const tipL = `${x - w},${top} ${x},${tip} ${x - ix},${top - t * 0.55}`;
	const tipR = `${x + w},${top} ${x},${tip} ${x + ix},${top - t * 0.55}`;
	const outline = `${x - w},${top} ${x},${tip} ${x + w},${top} ${x + w},${y} ${x},${y + w * 0.45} ${x - w},${y}`;
	return `<g transform="rotate(${rot} ${x} ${y})">
		<polygon points="${outline}" fill="${INK}" stroke="${INK}" stroke-width="11" stroke-linejoin="round"/>
		<polygon points="${L}" fill="${P.light}"/>
		<polygon points="${M}" fill="url(#face)"/>
		<polygon points="${R}" fill="${P.dark}"/>
		<polygon points="${tipL}" fill="${P.hi}"/>
		<polygon points="${tipR}" fill="${P.mid}"/>
		<polyline points="${x - ix},${top - t * 0.55} ${x - ix},${y + w * 0.3}" stroke="${P.hi}" stroke-width="1.6" opacity=".8"/>
		<polyline points="${x - w + 2.2},${top + 2} ${x - w + 2.2},${y - 3}" stroke="#fff" stroke-width="2.2" stroke-linecap="round" opacity=".55"/>
	</g>`;
}

function emblem() {
	return `
	<defs>
		<linearGradient id="face" x1="0" y1="0" x2="0" y2="1">
			<stop offset="0" stop-color="${P.light}"/>
			<stop offset=".55" stop-color="${P.mid}"/>
			<stop offset="1" stop-color="${P.dark}"/>
		</linearGradient>
		<radialGradient id="halo" cx=".5" cy=".5" r=".5">
			<stop offset="0" stop-color="#FF7AD6" stop-opacity=".55"/>
			<stop offset="1" stop-color="#FF7AD6" stop-opacity="0"/>
		</radialGradient>
		<radialGradient id="heart" cx=".5" cy=".5" r=".5">
			<stop offset="0" stop-color="#fff" stop-opacity="1"/>
			<stop offset=".35" stop-color="#FFE3F6" stop-opacity=".9"/>
			<stop offset="1" stop-color="#FF56C6" stop-opacity="0"/>
		</radialGradient>
		<filter id="drop" x="-30%" y="-30%" width="160%" height="160%">
			<feOffset in="SourceAlpha" dy="3" result="o"/>
			<feGaussianBlur in="o" stdDeviation="2.4" result="b"/>
			<feComponentTransfer in="b" result="s"><feFuncA type="linear" slope=".55"/></feComponentTransfer>
			<feMerge><feMergeNode in="s"/><feMergeNode in="SourceGraphic"/></feMerge>
		</filter>
	</defs>
	<circle cx="50" cy="52" r="44" fill="url(#halo)"/>
	<g filter="url(#drop)">
		${shard(27, 86, 12, 27, 12, -27)}
		${shard(73, 86, 12, 27, 12, 27)}
		${shard(50, 84, 15.5, 48, 17, 0)}
		<!-- the cleft they grow from -->
		<path d="M24 86 Q50 99 76 86 L72 93 Q50 103 28 93 Z" fill="${INK}" stroke="${INK}" stroke-width="5" stroke-linejoin="round"/>
		<path d="M30 89 Q50 97 70 89" stroke="#3A2148" stroke-width="2.4" fill="none" stroke-linecap="round"/>
	</g>
	<!-- the heart: a four-point star with a glow -->
	<circle cx="50" cy="55" r="15" fill="url(#heart)"/>
	<path d="M50 41 Q52 53 61 55 Q52 57 50 69 Q48 57 39 55 Q48 53 50 41 Z" fill="#fff"/>
	<circle cx="50" cy="55" r="2.6" fill="#fff"/>`;
}

const out = path.join(__dirname, "../../build/icons");
fs.mkdirSync(out, { recursive: true });
const svg = (size, bg) =>
	`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="-4 -4 108 108">${bg || ""}${emblem()}</svg>`;
const render = (s) => new Resvg(s, { fitTo: { mode: "original" } }).render().asPng();
fs.writeFileSync(path.join(out, "xenite.png"), render(svg(256)));
// review card: big, medium and price-sized on the HUD's ink
const big = fs.readFileSync(path.join(out, "xenite.png")).toString("base64");
const img = (x, y, s) => `<image href="data:image/png;base64,${big}" x="${x}" y="${y}" width="${s}" height="${s}"/>`;
const card = `<svg xmlns="http://www.w3.org/2000/svg" width="560" height="300">
	<rect width="560" height="300" fill="#140F1E"/>
	${img(10, 20, 256)}${img(290, 60, 96)}${img(410, 92, 40)}${img(470, 102, 20)}${img(505, 106, 14)}
</svg>`;
fs.writeFileSync(path.join(out, "xenite_card.png"), render(card));
console.log("build/icons/xenite.png");
