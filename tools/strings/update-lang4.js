// 第四轮：端口页剩余长句
const fs = require('fs');

const extra = {
  'By accessing or using SoloHost, you acknowledge that your use of SoloHost is subject to, and you agree to be bound by, the SoloHost':
    '访问或使用 SoloHost，即表示你确认你的使用受 SoloHost 的约束，并同意受其约束：',
  "Install Docker, then open your node's ports so other Pi nodes can reach this computer from outside your home network. Remote access does not need any of these ports.":
    '安装 Docker，然后开放节点端口，让其他 Pi 节点能从家庭网络外部访问这台计算机。远程访问不需要这些端口。',
  "Open your node's ports": '开放节点端口',
};

const targets = [
  'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\langs\\zh-CN.json',
  'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\src\\Resources\\zh-CN.json',
  process.env.APPDATA + '\\PiLang\\langs\\zh-CN.json',
];
for (const t of targets) {
  if (!fs.existsSync(t)) { console.log('跳过:', t); continue; }
  const j = JSON.parse(fs.readFileSync(t, 'utf8'));
  for (const [k, v] of Object.entries(extra)) j.entries[k] = v;
  j.entries = Object.fromEntries(Object.entries(j.entries).sort((a, b) => a[0].localeCompare(b[0])));
  fs.writeFileSync(t, JSON.stringify(j, null, 2), 'utf8');
  console.log(t, '总', Object.keys(j.entries).length);
}
