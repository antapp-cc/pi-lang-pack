// 第十二轮：容器状态枚举 + 可用性日期范围
const fs = require('fs');

const extra = {
  'running': '运行中',
  'stopped': '已停止',
  'exited': '已退出',
  'created': '已创建',
  'restarting': '重启中',
  'paused': '已暂停',
  'dead': '已失效',
  'removing': '移除中',
};

const patterns = [
  {
    pattern: '^([\\d.]+%) from (\\d{4}-\\d{2}-\\d{2}) to (\\d{4}-\\d{2}-\\d{2})$',
    replacement: '$1（从 $2 到 $3）',
  },
  {
    pattern: '^from (\\d{4}-\\d{2}-\\d{2}) to (\\d{4}-\\d{2}-\\d{2})$',
    replacement: '从 $1 到 $2',
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
