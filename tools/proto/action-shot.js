// 滚动到「操作」区域并截图
const fs = require('fs');
const PORT = 9337;
const OUT = 'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\docs\\screenshots\\操作区.png';

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
  await call(ws, 'Runtime.evaluate', { expression: "location.hash='#/troubleshooting'", returnByValue: true });
  await new Promise(r => setTimeout(r, 4000));
  await call(ws, 'Runtime.evaluate', {
    expression: `(function () {
      var all = document.querySelectorAll('p,u,div,span');
      for (var i = 0; i < all.length; i++) {
        if ((all[i].textContent || '').indexOf('删除所有区块链数据') >= 0) {
          all[i].scrollIntoView({ block: 'center' });
          return 'scrolled';
        }
      }
      return 'nf';
    })()`, returnByValue: true,
  });
  await new Promise(r => setTimeout(r, 1500));
  const shot = await call(ws, 'Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(OUT, Buffer.from(shot.data, 'base64'));
  console.log('截图:', OUT);
  process.exit(0);
})().catch(e => { console.error('FAIL:', e.message); process.exit(1); });
