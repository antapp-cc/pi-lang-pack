// 第九轮：疑难解答页「操作」段落（与 confirm 同源的文字，但页面节点是混合的）
const fs = require('fs');

const extra = {
  'from your computer. Please be cautious of using this action. It may take a while for you to restore your local blockchain data.':
    '从你的计算机上。请谨慎使用此操作。恢复本地区块链数据可能需要一段时间。',
  'from your computer. Please be cautious of using this action.':
    '从你的计算机上。请谨慎使用此操作。',
};

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
  j.entries = Object.fromEntries(Object.entries(j.entries).sort((a, b) => a[0].localeCompare(b[0])));
  fs.writeFileSync(t, JSON.stringify(j, null, 2), 'utf8');
  console.log(t, '新增', added, '总', Object.keys(j.entries).length);
}
