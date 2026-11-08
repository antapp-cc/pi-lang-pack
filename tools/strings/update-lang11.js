// 第十一轮：节点状态枚举 + moment 相对时间（fromNow）
const fs = require('fs');

const extra = {
  'Synced!': '已同步',
  'Synced': '已同步',
  'Not synced': '未同步',
  'Syncing': '同步中',
  'Catching up': '追赶中',
  'Joining SCP': '加入 SCP',
  'Not connected': '未连接',
};

const patterns = [];
const addPast = (en, zh) => patterns.push({ pattern: '^' + en + '$', replacement: zh });

// moment.fromNow() 的过去时输出
addPast('a few seconds ago', '几秒前');
addPast('a minute ago', '1 分钟前');
addPast('a few minutes ago', '几分钟前');
addPast('(\\d+) minutes ago', '$1 分钟前');
addPast('an hour ago', '1 小时前');
addPast('(\\d+) hours ago', '$1 小时前');
addPast('a day ago', '1 天前');
addPast('(\\d+) days ago', '$1 天前');
addPast('a month ago', '1 个月前');
addPast('(\\d+) months ago', '$1 个月前');
addPast('a year ago', '1 年前');
addPast('(\\d+) years ago', '$1 年前');
addPast('just now', '刚刚');

// 未来时（in ...）
addPast('in a few seconds', '几秒后');
addPast('in a minute', '1 分钟后');
addPast('in (\\d+) minutes', '$1 分钟后');
addPast('in an hour', '1 小时后');
addPast('in (\\d+) hours', '$1 小时后');
addPast('in a day', '1 天后');
addPast('in (\\d+) days', '$1 天后');

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
