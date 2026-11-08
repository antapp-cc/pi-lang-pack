// 列出源码里所有 title 文案（MUI Tooltip）中尚未翻译的
const fs = require('fs');
const m = JSON.parse(fs.readFileSync('C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\renderer.js.map', 'utf8'));
const dict = JSON.parse(fs.readFileSync('C:\\Users\\Administrator\\Desktop\\Pi多语言包\\langs\\zh-CN.json', 'utf8')).entries;

const seen = new Map();
for (let i = 0; i < m.sources.length; i++) {
  const s = m.sources[i];
  if (!s.includes('/src/')) continue;
  const c = m.sourcesContent[i] || '';
  const re = /title\s*=\s*["']([^"']{6,300})["']/g;
  let mm;
  while ((mm = re.exec(c))) {
    const t = mm[1].replace(/\s+/g, ' ').trim();
    if (!/[A-Za-z]{3,}/.test(t)) continue;
    if (dict[t] !== undefined) continue;
    if (!seen.has(t)) seen.set(t, s.split('/').pop());
  }
}
console.log('未翻译的 title 文案:', seen.size);
[...seen.entries()].sort((a, b) => b[0].length - a[0].length).forEach(([t, f]) => console.log(JSON.stringify(t) + '  <- ' + f));
