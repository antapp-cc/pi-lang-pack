// 采集页面上所有未翻译的英文文本节点（完整句子，用于补词表）
const fs = require('fs');
const PORT = 9334;

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

function send(wsUrl, expression) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => { try { ws.close(); } catch { } reject(new Error('ws 超时')); }, 25000);
    ws.onopen = () => ws.send(JSON.stringify({
      id: 1, method: 'Runtime.evaluate', params: { expression, returnByValue: true },
    }));
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id === 1) { clearTimeout(timer); try { ws.close(); } catch { } resolve(m.result); }
    };
    ws.onerror = () => { clearTimeout(timer); reject(new Error('ws 错误')); };
  });
}

const collectExpr = `(function () {
  var out = {};
  function walk(n) {
    if (!n) return;
    if (n.nodeType === 3) {
      var v = (n.nodeValue || '').replace(/\\s+/g, ' ').trim();
      if (v.length > 2 && /[A-Za-z]{3,}/.test(v) && !/[\\u4e00-\\u9fa5]/.test(v)) out[v] = 1;
      return;
    }
    if (n.nodeType === 1) {
      var nm = n.nodeName;
      if (nm === 'STYLE' || nm === 'SCRIPT' || nm === 'NOSCRIPT') return;
      var ks = n.childNodes;
      for (var i = 0; i < ks.length; i++) walk(ks[i]);
    }
  }
  walk(document.body);
  return JSON.stringify(Object.keys(out));
})()`;

(async () => {
  const page = await waitTarget(60000);
  const routes = ['#/', '#/node-switch', '#/troubleshooting', '#/setup-check', '#/peers',
    '#/notifications', '#/node-configuration', '#/node-apps', '#/app-studio',
    '#/remote-access', '#/remote-access/ports'];
  const all = new Set();
  for (const route of routes) {
    await send(page.webSocketDebuggerUrl, `location.hash='${route}'`).catch(() => { });
    await new Promise(r => setTimeout(r, 4000));
    try {
      const r = await send(page.webSocketDebuggerUrl, collectExpr);
      const list = JSON.parse(r.result.value || '[]');
      for (const t of list) all.add(t);
    } catch (e) { console.log(route, '采集失败:', e.message); }
    console.log(route, '累计:', all.size);
  }
  const out = 'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\runtime-texts.json';
  fs.writeFileSync(out, JSON.stringify([...all].sort(), null, 2), 'utf8');
  console.log('\n总计未翻译文本节点:', all.size, '写入', out);
  [...all].sort().forEach(t => console.log('  ' + (t.length > 160 ? t.slice(0, 160) + '…' : t)));
})().then(() => process.exit(0)).catch(e => { console.error('FAIL:', e.message); process.exit(1); });

