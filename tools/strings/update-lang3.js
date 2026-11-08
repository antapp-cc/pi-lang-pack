// 第三轮：按运行时未命中清单补长句和动态片段（精确键取自 runtime-miss.json）
const fs = require('fs');

const missFile = 'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\runtime-miss.json';
const miss = JSON.parse(fs.readFileSync(missFile, 'utf8'));

// 键必须与未命中文本逐字一致
const map = {
  'BETA': '测试版',
  'Diagnostics Info': '诊断信息',
  'Disclaimer:': '免责声明：',
  'Installed, not running': '已安装，未运行',
  'Network passphrase:': '网络口令：',
  'Node core configuration': '节点核心配置',
  'Peer port:': '对等节点端口：',
  'Private by design.': '设计上保护隐私。',
  'Why turn this on?': '为什么要打开？',
  'loading...': '加载中…',
  'If you have questions completing these steps, visit the': '如果你在完成这些步骤时有疑问，请访问',
  'for answers, browse the port forwarding guides other Pioneers have written for common routers, or join the node Applicants chat in the Pi App.':
    '寻找答案，浏览其他先驱为常见路由器编写的端口转发指南，或在 Pi 应用中加入节点申请者聊天。',
  'for answers, or join the node Applicants chat in the Pi App.': '寻找答案，或在 Pi 应用中加入节点申请者聊天。',
  'Remote access lets you use the apps running on your node when you\u2019re away from your home network. It creates one secure link tied to your Pi account and identity, so you can open your apps from your mobile devices privately.':
    '远程访问让你在离开家庭网络时，使用运行在节点上的应用。它会创建一条与你的 Pi 账户和身份绑定的安全链路，让你能在移动设备上私密地打开自己的应用。',
  'Remote access runs a small gateway in Docker. Start Docker Desktop \u2014 this page notices within a few seconds and continues on its own.':
    '远程访问会在 Docker 中运行一个小型网关。请启动 Docker Desktop——本页面会在几秒内检测到并自动继续。',
  'Your apps still run locally on your own machine while you access them remotely, without exposing them to the internet. Signing in to Pi Browser only authenticates the device you\u2019re connecting from, and makes sure it is you who accesses your own machine.':
    '你的应用仍然运行在本机，只是你可以远程访问它们，而无需把它们暴露到互联网。登录 Pi 浏览器只会验证你连接时使用的设备，确保访问你自己机器的人是你。',
};

// 兼容运行时可能用的直引号版本
const alt = {
  "Remote access lets you use the apps running on your node when you're away from your home network. It creates one secure link tied to your Pi account and identity, so you can open your apps from your mobile devices privately.":
    '远程访问让你在离开家庭网络时，使用运行在节点上的应用。它会创建一条与你的 Pi 账户和身份绑定的安全链路，让你能在移动设备上私密地打开自己的应用。',
  "Remote access runs a small gateway in Docker. Start Docker Desktop — this page notices within a few seconds and continues on its own.":
    '远程访问会在 Docker 中运行一个小型网关。请启动 Docker Desktop——本页面会在几秒内检测到并自动继续。',
  "Your apps still run locally on your own machine while you access them remotely, without exposing them to the internet. Signing in to Pi Browser only authenticates the device you're connecting from, and makes sure it is you who accesses your own machine.":
    '你的应用仍然运行在本机，只是你可以远程访问它们，而无需把它们暴露到互联网。登录 Pi 浏览器只会验证你连接时使用的设备，确保访问你自己机器的人是你。',
};

const all = { ...map, ...alt };
const unmatched = miss.filter(m => !all[m] && !/^(Docker|SoloHost|GCMIM7NG5|WINDOWS)/.test(m));
console.log('未命中中本次可翻译:', miss.filter(m => all[m]).length, '/', miss.length);
if (unmatched.length) console.log('未覆盖:', unmatched);

const targets = [
  'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\langs\\zh-CN.json',
  'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\src\\Resources\\zh-CN.json',
  process.env.APPDATA + '\\PiLang\\langs\\zh-CN.json',
];
for (const t of targets) {
  if (!fs.existsSync(t)) { console.log('跳过(不存在):', t); continue; }
  const j = JSON.parse(fs.readFileSync(t, 'utf8'));
  let added = 0;
  for (const [k, v] of Object.entries(all)) {
    if (j.entries[k] === undefined) { j.entries[k] = v; added++; }
    else if (j.entries[k] !== v) { j.entries[k] = v; added++; }
  }
  j.entries = Object.fromEntries(Object.entries(j.entries).sort((a, b) => a[0].localeCompare(b[0])));
  fs.writeFileSync(t, JSON.stringify(j, null, 2), 'utf8');
  console.log(t, '更新', added, '条，总', Object.keys(j.entries).length);
}
