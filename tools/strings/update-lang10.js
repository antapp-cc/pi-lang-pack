// 第十轮：节点同步状态（动态数字 + 后端消息，用 patterns 正则处理）
const fs = require('fs');

const extra = {
  'Local block number:': '本地区块号：',
  'Latest block number:': '最新区块号：',
  'block number:': '区块号：',
};

const patterns = [
  {
    pattern: '^Your computer is syncing with the blockchain \\(it may take hours\\)$',
    replacement: '你的计算机正在与区块链同步（可能需要几个小时）',
  },
  {
    pattern: '^Your computer is syncing with the blockchain \\(it may take hours\\) Catching up to ledger (\\d+): downloading ledger files (\\d+)/(\\d+) \\((\\d+)%\\)$',
    replacement: '你的计算机正在与区块链同步（可能需要几个小时）正在追赶账本 $1：下载账本文件 $2/$3（已完成 $4%）',
  },
  {
    pattern: '^Your computer is syncing with the blockchain \\(it may take hours\\) Catching up to ledger (\\d+): Download & apply checkpoints: num checkpoints left to apply:(\\d+) \\((\\d+)% done\\)$',
    replacement: '你的计算机正在与区块链同步（可能需要几个小时）正在追赶账本 $1：下载并应用检查点，剩余待应用检查点：$2（已完成 $3%）',
  },
  {
    pattern: '^Your computer is syncing with the blockchain \\(it may take hours\\) Catching up to ledger (\\d+): (Applying buckets.*)$',
    replacement: '你的计算机正在与区块链同步（可能需要几个小时）正在追赶账本 $1：$2',
  },
  {
    pattern: '^Your computer is syncing with the blockchain \\(it may take hours\\) Catching up to ledger (\\d+): (.*)$',
    replacement: '你的计算机正在与区块链同步（可能需要几个小时）正在追赶账本 $1：$2',
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
  console.log(t, '新增词条', added, '新增正则', pAdded, '总', Object.keys(j.entries).length);
}
