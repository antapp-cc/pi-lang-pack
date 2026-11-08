// 打开指定路由并截图（验收用）
const fs = require('fs');
const path = require('path');

const PORT = 9339;
const OUT = 'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\docs\\screenshots';

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
  const routes = process.argv.slice(2);
  fs.mkdirSync(OUT, { recursive: true });
  for (const route of routes) {
    await send(page.webSocketDebuggerUrl, 'Runtime.evaluate', {
      expression: `location.hash='${route}'`, returnByValue: true,
    });
    await new Promise(r => setTimeout(r, 4000));
    const r = await send(page.webSocketDebuggerUrl, 'Runtime.evaluate', {
      expression: `JSON.stringify({url: location.hash, text: document.body.innerText.replace(/\\s+/g,' ').slice(0,500)})`,
      returnByValue: true,
    });
    console.log(route, '=>', r.result.value);
    const shot = await send(page.webSocketDebuggerUrl, 'Page.captureScreenshot', { format: 'png' });
    const name = route.replace(/[/#]/g, '_').replace(/^_/, '') || 'home';
    fs.writeFileSync(path.join(OUT, name + '.png'), Buffer.from(shot.data, 'base64'));
    console.log('  截图:', name + '.png');
  }
})().then(() => process.exit(0)).catch(e => { console.error('FAIL:', e.message); process.exit(1); });


