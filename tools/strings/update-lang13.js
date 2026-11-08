// 第十三轮：端口检查提示文案
const fs = require('fs');

const extra = {
  'To test your ports from the internet we need them free, so your node stops for a minute or two and then starts again on its own. Remote access is unaffected — it does not use these ports.':
    '为了从互联网测试你的端口，需要这些端口空闲，所以你的节点会停止一两分钟，然后自动重新启动。远程访问不受影响——它不使用这些端口。',
  'We couldn’t test your ports from the internet': '我们无法从互联网测试你的端口',
  'Your node still works, but other nodes may not be able to reach it. SoloHost Remote Access is unaffected.':
    '你的节点仍在运行，但其他节点可能无法访问它。SoloHost 远程访问不受影响。',
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
  fs.writeFileSync(t, JSON.stringify(j, null, 2), 'utf8');
  console.log(t, '新增', added, '总', Object.keys(j.entries).length);
}
