// 端口页展开后截图
const fs = require('fs');
const PORT = 9334;
const OUT = 'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\docs\\screenshots\\端口页.png';

function send(wsUrl, method, params) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => { try { ws.close(); } catch { } reject(new Error('超时')); }, 15000);
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method, params }));
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
  await send(url, 'Runtime.evaluate', { expression: "location.hash='#/remote-access/ports'", returnByValue: true });
  await new Promise(r => setTimeout(r, 5000));
  await send(url, 'Runtime.evaluate', {
    expression: `(function () {
      var all = document.querySelectorAll('div,span,button,a');
      for (var i = 0; i < all.length; i++) {
        var t = (all[i].textContent || '').trim();
        if (t === '想自己操作？' || t === 'Prefer to do it yourself?') { all[i].click(); return 'clicked'; }
      }
      return 'not found';
    })()`, returnByValue: true,
  });
  await new Promise(r => setTimeout(r, 4000));
  const shot = await send(url, 'Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(OUT, Buffer.from(shot.data, 'base64'));
  console.log('截图:', OUT);
})().then(() => process.exit(0)).catch(e => { console.error('FAIL:', e.message); process.exit(1); });
