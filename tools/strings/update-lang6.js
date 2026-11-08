// 第六轮：通知/公告里的服务器下发标题和正文（内容固定，整句进词表）
const fs = require('fs');

const texts = JSON.parse(fs.readFileSync('C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\runtime-texts.json', 'utf8'));

// 按 runtime-texts.json 的索引取原文，避免手抄弯引号出错
const byIndex = {
  3: '更多细节：我们正在升级区块链协议，这需要手动迁移节点上用于 API 的本地数据库。为避免中断，此过程不会自动执行——我们会提供一个专门的界面。这意味着在发布新版本节点之前，你的节点上的区块链 API 服务将很快停止运行，不过你的节点参与区块链不受影响。我们建议等待版本更新（发布后会自动更新），但如果你更快需要 API，可以在疑难解答页面选择「删除所有区块链数据」，以新协议格式重新生成数据。',
  4: 'Pi 节点 0.6.4 来了，它带来带安全隧道的 SoloHost 远程功能：无论身在何处，都能访问运行在你节点上的应用，无需在路由器上开放端口，也无需改动网络设置。',
  5: 'Pi 节点 0.6.4：带安全隧道的 SoloHost 远程来了',
  6: '请注意：旧版应用不再支持 SoloHost 远程。要使用远程访问，请从 https://minepi.com/pi-blockchain/pi-node/ 下载 Pi 节点 0.6.4，并覆盖安装当前版本。',
};

const extra = {};
for (const [idx, zh] of Object.entries(byIndex)) {
  const key = texts[Number(idx)];
  if (!key) { console.log('缺少索引', idx); continue; }
  extra[key] = zh;
}
console.log('待加入:', Object.keys(extra).length);
for (const k of Object.keys(extra)) console.log('  ' + k.slice(0, 90) + '…');

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
