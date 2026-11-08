// 点击「手动设置」→ 采集说明段 → 截图
const fs = require('fs');
const PORT = 9335;
const SHOT = 'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\docs\\screenshots\\手动设置说明.png';

function conn(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.onopen = () => resolve(ws);
    ws.onerror = () => reject(new Error('ws error'));
  });
}
let msgId = 0;
function call(ws, method, params) {
  return new Promise((resolve, reject) => {
    const id = ++msgId;
    const timer = setTimeout(() => reject(new Error('timeout ' + method)), 15000);
    const onMsg = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id === id) { clearTimeout(timer); ws.removeEventListener('message', onMsg); resolve(m.result); }
    };
    ws.addEventListener('message', onMsg);
    ws.send(JSON.stringify({ id, method, params }));
  });
}
async function clickText(ws, text) {
  const r = await call(ws, 'Runtime.evaluate', {
    expression: `(function () {
      var all = document.querySelectorAll('button,div,span,a');
      for (var i = 0; i < all.length; i++) {
        var t = (all[i].textContent || '').trim();
        if (t === ${JSON.stringify(text)}) {
          all[i].scrollIntoView({ block: 'center' });
          var b = all[i].getBoundingClientRect();
          return JSON.stringify({ x: b.x + b.width / 2, y: b.y + b.height / 2 });
        }
      }
      return 'null';
    })()`, returnByValue: true,
  });
  const v = r && r.result && r.result.value;
  if (!v || v === 'null') throw new Error('找不到: ' + text);
  const { x, y } = JSON.parse(v);
  for (const type of ['mousePressed', 'mouseReleased']) {
    await call(ws, 'Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  }
  return { x, y };
}

(async () => {
  const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
  const page = targets.find(t => t.type === 'page' && /index\.html/.test(t.url)) || targets.find(t => t.type === 'page');
  const ws = await conn(page.webSocketDebuggerUrl);

  await call(ws, 'Runtime.evaluate', { expression: "location.hash='#/remote-access/ports'", returnByValue: true });
  await new Promise(r => setTimeout(r, 5000));

  console.log('点击「手动设置」:', JSON.stringify(await clickText(ws, '手动设置')));
  await new Promise(r => setTimeout(r, 2500));

  const txt = await call(ws, 'Runtime.evaluate', {
    expression: `(function () {
      var out = [];
      var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      var n;
      while (n = w.nextNode()) {
        var s = (n.nodeValue || '').replace(/\\s+/g, ' ').trim();
        if (s.length > 2 && /[A-Za-z]{3,}/.test(s)) out.push(s);
      }
      return JSON.stringify(out);
    })()`, returnByValue: true,
  });
  const list = JSON.parse(txt.result.value || '[]');
  console.log('含英文文本节点:', list.length);
  list.forEach(t => console.log('  ' + JSON.stringify(t)));

  await new Promise(r => setTimeout(r, 500));
  const shot = await call(ws, 'Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(SHOT, Buffer.from(shot.data, 'base64'));
  console.log('截图:', SHOT);
  process.exit(0);
})().catch(e => { console.error('FAIL:', e.message); process.exit(1); });
