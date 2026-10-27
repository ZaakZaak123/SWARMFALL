// Prepare the approved fractured-ore icon. Preserve alpha; no painted backdrop.
// node tools/icons/xenite.js [absolute path to sharp]
const fs = require('fs');
const path = require('path');
const sharp = require(process.argv[2] || 'sharp');
const root = path.resolve(__dirname, '../..');
async function main() {
  const out = path.join(root, 'production/xenite');
  const source = sharp(path.join(out, 'icon-source.png'));
  const meta = await source.metadata();
  if (!meta.hasAlpha) throw new Error('Source must have alpha');
  const trimmed = await source.trim().toBuffer();
  const icon = await sharp(trimmed).resize(226, 226, { fit: 'inside' }).png().toBuffer();
  const png = await sharp({create:{width:256,height:256,channels:4,background:'#00000000'}})
    .composite([{input:icon,gravity:'centre'}]).png().toBuffer();
  fs.writeFileSync(path.join(out, 'icon.png'), png);
  const raw = await sharp(png).ensureAlpha().raw().toBuffer();
  let empty=0,solid=0,partial=0;
  for(let i=3;i<raw.length;i+=4) { if(raw[i]===0)empty++;else if(raw[i]>=248)solid++;else partial++; }
  if(empty<10000 || solid<10000) throw new Error('Unexpected alpha coverage');
  const build=path.join(root,'build/xenite');fs.mkdirSync(build,{recursive:true});
  fs.writeFileSync(path.join(build,'icon.rgba'),raw);
  const sizes = [128,64,32,24,20,16,14];
  const images = await Promise.all(sizes.map(async (s,i) => ({input:await sharp(png).resize(s,s).png().toBuffer(),left:20+sizes.slice(0,i).reduce((a,b)=>a+b+18,0),top:28})));
  await sharp({create:{width:560,height:185,channels:4,background:'#201728'}}).composite(images).png().toFile(path.join(out,'icon-sizes.png'));
  console.log(JSON.stringify({file:'production/xenite/icon.png',empty,solid,partial}));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
