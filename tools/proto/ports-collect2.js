// 端口页主区域说明文案采集
const fs = require('fs');
const PORT = 9334;

function send(wsUrl, expression, waitMs = 10000) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => { try { ws.close(); } catch { } resolve(null); }, waitMs);
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression, returnByValue: true } }));
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id === 1) { clearTimeout(timer); try { ws.close(); } catch { } resolve(m.result); }
    };
    ws.onerror = () => { clearTimeout(timer); reject(new Error('ws 错误')); };
  });
}

(async () => {
  const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
  const page = targets.find(t => t.type === 'page' && /index\.html/.test(t.url)) || targets.find(t => t.type === 'page');
  const url = page.webSocketDebuggerUrl;
  await send(url, "location.hash='#/remote-access/ports'");
  await new Promise(r => setTimeout(r, 6000));

  const expr = `(function () {
    var out = [];
    var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    var n;
    while (n = w.nextNode()) {
      var v = (n.nodeValue || '').replace(/\\s+/g, ' ').trim();
      if (v.length > 2 && /[A-Za-z]{3,}/.test(v)) out.push(v);
    }
    return JSON.stringify(out);
  })()`;
  const r = await send(url, expr);
  const list = JSON.parse(r.result.value || '[]');
  console.log('含英文的文本节点:', list.length);
  list.forEach(t => console.log('  ' + JSON.stringify(t)));
  fs.writeFileSync('C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\ports-texts2.json', JSON.stringify(list, null, 2), 'utf8');
})().then(() => process.exit(0)).catch(e => { console.error('FAIL:', e.message); process.exit(1); });
