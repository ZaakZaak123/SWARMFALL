// Renders tools/icons/icons.js into a white, tintable atlas (ImageColor3 multiplies it):
//   build/icons/atlas.png    8 columns × N rows of 128 px cells
//   build/icons/preview.png  the atlas tinted on a dark card, for review
//   prints the Luau order table for src/client/Icons.luau
// Usage: node tools/icons/build.js <path to @resvg/resvg-js>
const fs = require("fs");
const path = require("path");
const { Resvg } = require(process.argv[2] || "@resvg/resvg-js");
const ICONS = require("./icons.js");

const CELL = 128;
const COLS = 8;
const PAD = 14; // design units of margin around the 100-unit box (room for outline and shadow)
const names = Object.keys(ICONS);
const rows = Math.ceil(names.length / COLS);
const out = path.join(__dirname, "../../build/icons");
fs.mkdirSync(out, { recursive: true });

const paint = (s, p) => (s || "").replace(/="F"/g, `="${p}"`);

function cell(name, i) {
	const ic = ICONS[name];
	const x = (i % COLS) * CELL;
	const y = Math.floor(i / COLS) * CELL;
	const k = CELL / (100 + PAD * 2);
	const id = `i${i}`;
	return `
	<g transform="translate(${x} ${y}) scale(${k}) translate(${PAD} ${PAD})">
		<defs>
			<mask id="${id}m" maskUnits="userSpaceOnUse" x="-${PAD}" y="-${PAD}" width="${100 + PAD * 2}" height="${100 + PAD * 2}">
				<rect x="-${PAD}" y="-${PAD}" width="${100 + PAD * 2}" height="${100 + PAD * 2}" fill="#fff"/>
				<g fill="#000" stroke="#000">${ic.cut || ""}</g>
			</mask>
		</defs>
		<g filter="url(#fx)">
			<g mask="url(#${id}m)">
				${paint(ic.body, "url(#shade)")}
			</g>
			${paint(ic.hi, "url(#shade)")}
		</g>
	</g>`;
}

function svg(bg) {
	const W = COLS * CELL;
	const H = rows * CELL;
	return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
	<defs>
		<linearGradient id="shade" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="100">
			<stop offset="0" stop-color="#ffffff"/>
			<stop offset=".45" stop-color="#f2f2f2"/>
			<stop offset="1" stop-color="#a8a8a8"/>
		</linearGradient>
		<filter id="fx" x="-30%" y="-30%" width="160%" height="160%" color-interpolation-filters="sRGB">
			<feMorphology in="SourceAlpha" operator="dilate" radius="4.2" result="ol"/>
			<feOffset in="ol" dy="4" result="off"/>
			<feGaussianBlur in="off" stdDeviation="3" result="blur"/>
			<feComponentTransfer in="blur" result="sh"><feFuncA type="linear" slope=".65"/></feComponentTransfer>
			<feMerge><feMergeNode in="sh"/><feMergeNode in="ol"/><feMergeNode in="SourceGraphic"/></feMerge>
		</filter>
	</defs>
	${bg || ""}
	${names.map(cell).join("")}
</svg>`;
}

const render = (s) => new Resvg(s, { fitTo: { mode: "original" } }).render().asPng();
fs.writeFileSync(path.join(out, "atlas.png"), render(svg()));

// preview: each icon tinted by a palette colour on a dark tile
const tints = ["#A4FF5A", "#FFC23C", "#6CE6FF", "#FF5A7A", "#C9A2FF", "#FF8A3C", "#F4EEFF", "#7DFFB0"];
let bg = `<rect width="100%" height="100%" fill="#140F1E"/>`;
const atlas = fs.readFileSync(path.join(out, "atlas.png")).toString("base64");
let tiles = "";
names.forEach((n, i) => {
	const x = (i % COLS) * CELL;
	const y = Math.floor(i / COLS) * CELL;
	tiles += `<rect x="${x + 6}" y="${y + 6}" width="${CELL - 12}" height="${CELL - 12}" rx="18" fill="#221A33"/>`;
	tiles += `<svg x="${x}" y="${y}" width="${CELL}" height="${CELL}" viewBox="${x} ${y} ${CELL} ${CELL}">
		<filter id="t${i}" color-interpolation-filters="sRGB"><feFlood flood-color="${tints[i % tints.length]}"/><feComposite in2="SourceGraphic" operator="arithmetic" k1="1"/></filter>
		<image href="data:image/png;base64,${atlas}" width="${COLS * CELL}" height="${rows * CELL}" filter="url(#t${i})"/></svg>`;
});
fs.writeFileSync(
	path.join(out, "preview.png"),
	render(`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${COLS * CELL}" height="${rows * CELL}">${bg}${tiles}</svg>`),
);

console.log(`-- ${names.length} icons, ${COLS}×${rows}`);
console.log("local ORDER = { " + names.map((n) => `"${n}"`).join(", ") + " }");
