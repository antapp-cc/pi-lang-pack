// 第七轮：端口页（RouterPortsSection）跨节点文案
const fs = require('fs');

const texts = JSON.parse(fs.readFileSync('C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\ports-texts.json', 'utf8'));
const find = (prefix) => texts.find(t => t.startsWith(prefix));
const extra = {};
const add = (key, val) => { if (key) extra[key] = val; else console.log('未找到节点:', val); };

add(find('ports (TCP) from your router'), ' 个端口（TCP）从路由器转发到这台计算机，并在防火墙上开放它们：');
add(find('Find your internal IP address'), '查找这台计算机的内网 IP 地址（Windows：');
add(find('Open your router'), '打开路由器的设置页面（通常是 192.168.0.1 或 192.168.1.1）。');
add(find('Find “Port Forwarding”'), '找到“端口转发”（有时在“高级”或“NAT”下）。');
add(find('Windows Firewall may show'), 'Windows 防火墙可能会弹出关于 Docker 的对话框，此时你需要点击“允许访问”。');

// 中英混合节点只能靠片段替换
add('setup.', '设置。');
add('Forward all', '转发所有');
add('Network).', '网络）。');

console.log('待加入:', Object.keys(extra).length);
Object.keys(extra).forEach(k => console.log('  ' + JSON.stringify(k.slice(0, 70)) + ' => ' + extra[k]));

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
