// 导航到疑难解答页，点击「删除所有区块链数据」触发原生 confirm（点确定会删数据，所以只弹框、截图、不确认）
const PORT = 9333;

function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.onopen = () => resolve(ws);
    ws.onerror = () => reject(new Error('ws 连接失败'));
  });
}

function evalOnce(ws, expression, timeoutMs = 8000) {
  return new Promise((resolve) => {
    const id = Math.floor(Math.random() * 1e6) + 1;
    const timer = setTimeout(() => resolve(null), timeoutMs);
    const onMsg = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.id === id) { clearTimeout(timer); ws.removeEventListener('message', onMsg); resolve(m.result); }
    };
    ws.addEventListener('message', onMsg);
    ws.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: { expression, returnByValue: true } }));
  });
}

(async () => {
  const targets = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
  const page = targets.find(t => t.type === 'page' && /index\.html/.test(t.url)) || targets.find(t => t.type === 'page');
  if (!page) throw new Error('找不到页面');
  const ws = await connect(page.webSocketDebuggerUrl);

  await evalOnce(ws, "location.hash='#/troubleshooting'", 8000);
  await new Promise(r => setTimeout(r, 5000));

  const clickExpr = `(function () {
    var all = document.querySelectorAll('u,a,span,div,p');
    for (var i = 0; i < all.length; i++) {
      var t = (all[i].textContent || '').trim();
      if (t === '删除所有区块链数据' || t === 'Remove all blockchain data') {
        all[i].click();
        return 'clicked:' + t;
      }
    }
    return 'not found';
  })()`;
  // 这个 evaluate 在 confirm 弹窗出现后不会返回，等 400ms 就够发送了
  ws.send(JSON.stringify({ id: 999, method: 'Runtime.evaluate', params: { expression: clickExpr, returnByValue: true } }));
  await new Promise(r => setTimeout(r, 500));
  console.log('confirm 已触发（不点确定）');
  process.exit(0);
})().catch(e => { console.error('FAIL:', e.message); process.exit(1); });
