// 第八轮：开放节点端口页面的说明段（跨节点 + 混合节点）
const fs = require('fs');

const extra = {
  'Set up your connection yourself by forwarding these ports in your router. Follow the steps below, then check your connection. You can also':
    '在路由器上转发这些端口，自己完成连接设置。按下面的步骤操作，然后检查连接。你也可以',
  'start the setup check': '开始设置检查',
  // 混合节点（含已翻的「Pi 桌面」）只能用片段
  'at any time to let': '随时让',
  'try automatically.': '自动尝试。',
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
