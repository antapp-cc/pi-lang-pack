// 第五轮：运行时完整长句（跨行拼接的段落）
const fs = require('fs');

const texts = JSON.parse(fs.readFileSync('C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\runtime-texts.json', 'utf8'));
const byIndex = {
  2: 'Docker 在你的系统中作为一个后台任务运行，称为“daemon”。请启动 Docker Desktop 并等待它提示正在运行，这样你的计算机才能运行 Pi 节点。',
  3: '按以下步骤安装所需的软件包，并完成技术准备要求，让你的计算机可以运行节点。所有节点申请者都应完成这些步骤，参与测试与校准期，作为节点或超级节点筛选流程的一部分。',
  6: 'Pi 桌面通过 Docker 测试你的端口，因此检查开始前 Docker Desktop 必须正在运行。请启动它，等待它提示正在运行后，再重新检查。',
  10: 'SoloHost 处于早期测试阶段。随着产品不断改进，体验和功能可能会有较大变化。',
  11: '在任何已登录 Pi 的设备上使用本地应用。SoloHost 让你的计算机充当自己的服务器，因此你可以在桌面上本地运行应用，并通过 Pi 浏览器在移动设备上远程访问——用 Pi 登录后即可。只需连接一次 Pi 账户，然后在手机或其他设备上打开 Pi 浏览器，无需单独登录或逐个应用配置。',
};

const extra = {};
for (const [idx, zh] of Object.entries(byIndex)) {
  const key = texts[Number(idx)];
  if (!key) { console.log('缺少索引', idx); continue; }
  extra[key] = zh;
}
console.log('待加入长句:', Object.keys(extra).length);

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
