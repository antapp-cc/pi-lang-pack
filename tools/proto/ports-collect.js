// 打开端口页 → 展开「想自己操作？」→ 采集完整英文文本节点
const fs = require('fs');
const PORT = 9334;

function send(wsUrl, expression, waitMs = 8000) {
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

async function main() {
  const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
  const page = targets.find(t => t.type === 'page' && /index\.html/.test(t.url)) || targets.find(t => t.type === 'page');
  if (!page) throw new Error('找不到页面');
  const url = page.webSocketDebuggerUrl;

  await send(url, "location.hash='#/remote-access/ports'");
  await new Promise(r => setTimeout(r, 5000));

  // 展开「想自己操作？」
  const click = await send(url, `(function () {
    var all = document.querySelectorAll('div,span,button,a');
    for (var i = 0; i < all.length; i++) {
      var t = (all[i].textContent || '').trim();
      if (t === '想自己操作？' || t === 'Prefer to do it yourself?') { all[i].click(); return 'clicked'; }
    }
    return 'not found';
  })()`);
  console.log('展开结果:', JSON.stringify(click && click.result && click.result.value));
  await new Promise(r => setTimeout(r, 4000));

  const expr = `(function () {
    var out = [];
    function walk(n) {
      if (!n) return;
      if (n.nodeType === 3) {
        var v = (n.nodeValue || '').replace(/\\s+/g, ' ').trim();
        if (v.length > 2 && /[A-Za-z]{3,}/.test(v)) out.push(v);
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
    return JSON.stringify(out);
  })()`;
  const r = await send(url, expr);
  const list = JSON.parse(r.result.value || '[]');
  console.log('含英文的文本节点:', list.length);
  list.forEach(t => console.log('  ' + JSON.stringify(t)));
  fs.writeFileSync('C:\\Users\\Administrator\\Desktop\\Pi多语言包\\tools\\strings\\ports-texts.json',
    JSON.stringify(list, null, 2), 'utf8');
}

main().then(() => process.exit(0)).catch(e => { console.error('FAIL:', e.message); process.exit(1); });

