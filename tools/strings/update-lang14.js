// 第十四轮：入站连接 tooltip（条件表达式里的字面量 + 动态文案）
const fs = require('fs');

const extra = {
  'Make sure your port configuration is correct': '请确认你的端口配置正确',
};

const patterns = [
  {
    pattern: '^Currently supporting (\\d+) other nodes$',
    replacement: '当前支撑 $1 个其他节点',
  },
];

const targets = [
  'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\langs\\zh-CN.json',
  'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\src\\Resources\\zh-CN.json',
  process.env.APPDATA + '\\PiLang\\langs\\zh-CN.json',
];
for (const t of targets) {
  if (!fs.existsSync(t)) { console.log('跳过:', t); continue; }
  const j = JSON.parse(fs.readFileSync(t, 'utf8'));
  let added = 0;
  for (const [k, v] of Object.entries(extra)) {
    if (j.entries[k] === undefined) { j.entries[k] = v; added++; }
  }
  const existing = new Set((j.patterns || []).map(p => p.pattern));
  let pAdded = 0;
  for (const p of patterns) {
    if (!existing.has(p.pattern)) { j.patterns.push(p); pAdded++; }
  }
  fs.writeFileSync(t, JSON.stringify(j, null, 2), 'utf8');
  console.log(t, '新增词条', added, '新增正则', pAdded, '总词条', Object.keys(j.entries).length, '总正则', j.patterns.length);
}
