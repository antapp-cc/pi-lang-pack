// 遍历各页面，采集未命中的英文文本（注入脚本里的 stats.samples）
const path = require('path');
const fs = require('fs');
const PORT = 9333;

async function waitTarget(timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/json`);
      const targets = await res.json();
      const page = targets.find(t => t.type === 'page' && /index\.html/.test(t.url)) ||
        targets.find(t => t.type === 'page');
      if (page && page.webSocketDebuggerUrl) return page;
    } catch (e) { }
    await new Promise(r => setTimeout(r, 1000));
  }
  throw new Error('CDP target 未出现');
}

function send(wsUrl, method, params) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => { try { ws.close(); } catch { } reject(new Error('ws 超时')); }, 20000);
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method, params }));
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id === 1) { clearTimeout(timer); try { ws.close(); } catch { } resolve(m.result); }
    };
    ws.onerror = () => { clearTimeout(timer); reject(new Error('ws 错误')); };
  });
}

(async () => {
  const page = await waitTarget(60000);
  const routes = ['#/', '#/node-switch', '#/troubleshooting', '#/setup-check', '#/peers',
    '#/notifications', '#/node-configuration', '#/node-apps', '#/app-studio',
    '#/remote-access', '#/remote-access/ports'];
  const all = new Set();
  for (const route of routes) {
    await send(page.webSocketDebuggerUrl, 'Runtime.evaluate', { expression: `location.hash='${route}'`, returnByValue: true });
    await new Promise(r => setTimeout(r, 3500));
    const r = await send(page.webSocketDebuggerUrl, 'Runtime.evaluate', {
      expression: `JSON.stringify((window.__piLangStats && window.__piLangStats.samples) || [])`,
      returnByValue: true,
    });
    try {
      const samples = JSON.parse(r.result.value || '[]');
      for (const s of samples) all.add(s);
    } catch (e) { }
    console.log(route, 'samples:', all.size);
  }
  const out = 'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\runtime-miss.json';
  fs.writeFileSync(out, JSON.stringify([...all].sort(), null, 2), 'utf8');
  console.log('\n未命中数量:', all.size);
  console.log('写入:', out);
  [...all].sort().forEach(s => console.log(' ', s));
})().then(() => process.exit(0)).catch(e => { console.error('FAIL:', e.message); process.exit(1); });
