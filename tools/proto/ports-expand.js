// 用真实鼠标事件点开「想自己操作？」，读取展开区域文本并截图
const fs = require('fs');
const PORT = 9334;
const SHOT = 'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\docs\\screenshots\\端口页展开.png';

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

(async () => {
  const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
  const page = targets.find(t => t.type === 'page' && /index\.html/.test(t.url)) || targets.find(t => t.type === 'page');
  const ws = await conn(page.webSocketDebuggerUrl);

  await call(ws, 'Runtime.evaluate', { expression: "location.hash='#/remote-access/ports'", returnByValue: true });
  await new Promise(r => setTimeout(r, 5000));

  const rect = await call(ws, 'Runtime.evaluate', {
    expression: `(function () {
      var all = document.querySelectorAll('div,span,button,a');
      for (var i = 0; i < all.length; i++) {
        var t = (all[i].textContent || '').trim();
        if (t === '想自己操作？') {
          all[i].scrollIntoView({ block: 'center' });
          var r = all[i].getBoundingClientRect();
          return JSON.stringify({ x: r.x + r.width / 2, y: r.y + r.height / 2 });
        }
      }
      return 'null';
    })()`, returnByValue: true,
  });
  const v = rect && rect.result && rect.result.value;
  console.log('元素坐标:', v);
  if (!v || v === 'null') throw new Error('找不到展开按钮');
  const { x, y } = JSON.parse(v);

  for (const type of ['mousePressed', 'mouseReleased']) {
    await call(ws, 'Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  }
  await new Promise(r => setTimeout(r, 3000));

  const txt = await call(ws, 'Runtime.evaluate', {
    expression: `(function () {
      var out = [];
      var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      var n;
      while (n = w.nextNode()) {
        var s = (n.nodeValue || '').replace(/\\s+/g, ' ').trim();
        if (/手动转发|Forward|端口|端口转发|internal IP|Firewall|防火墙/.test(s)) out.push(s);
      }
      return JSON.stringify(out);
    })()`, returnByValue: true,
  });
  console.log('展开后文本:', txt && txt.result && txt.result.value);

  await new Promise(r => setTimeout(r, 500));
  const shot = await call(ws, 'Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(SHOT, Buffer.from(shot.data, 'base64'));
  console.log('截图:', SHOT);
  process.exit(0);
})().catch(e => { console.error('FAIL:', e.message); process.exit(1); });
