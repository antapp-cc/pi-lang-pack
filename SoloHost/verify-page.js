// 校验 SoloHost 页面：从 docker-compose.yml 里抽出内嵌 HTML，检查
// 1) <script> 里的 JS 语法；2) 中英两套 i18n 的 key 完全一致；
// 3) HTML 里每个 data-i18n 的 key 都在 i18n 里。
const fs = require('fs');
const vm = require('vm');

const yml = fs.readFileSync(process.argv[2], 'utf8');
const start = yml.indexOf("cat > /usr/share/nginx/html/index.html <<'EOF'");
if (start < 0) { console.log('[FAIL] 找不到内嵌 HTML 的 heredoc 起点'); process.exit(1); }
const bodyStart = yml.indexOf('\n', start) + 1;
const end = yml.indexOf('\n        EOF', bodyStart);
if (end < 0) { console.log('[FAIL] 找不到 heredoc 结束标记'); process.exit(1); }
const html = yml.slice(bodyStart, end);

let fail = 0;
const ok = (cond, what) => { console.log((cond ? '[OK]   ' : '[FAIL] ') + what); if (!cond) fail++; };

ok(html.includes('<!doctype html>'), '抽到完整 HTML（' + html.length + ' 字符）');

// 1) script 语法
const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
ok(!!scriptMatch, '找到内联 script');
if (scriptMatch) {
  try {
    new vm.Script(scriptMatch[1]);
    ok(true, 'JS 语法检查通过');
  } catch (e) {
    ok(false, 'JS 语法错误: ' + e.message);
  }

  // 2) i18n 两套 key
  const js = scriptMatch[1];
  const zhBlock = js.slice(js.indexOf('zh: {'), js.indexOf('en: {'));
  const enBlock = js.slice(js.indexOf('en: {'), js.indexOf('];', js.indexOf('en: {')) >= 0 ? js.indexOf('};', js.indexOf('en: {')) : js.length);
  const keyOf = (block) => new Set([...block.matchAll(/^\s{18}(\w+):/gm)].map((m) => m[1]));
  const zhKeys = keyOf(zhBlock);
  const enKeys = keyOf(enBlock);
  ok(zhKeys.size > 15, 'zh i18n 键数量 ' + zhKeys.size);
  const missingInEn = [...zhKeys].filter((k) => !enKeys.has(k));
  const missingInZh = [...enKeys].filter((k) => !zhKeys.has(k));
  ok(missingInEn.length === 0, 'en 缺失的 key: ' + (missingInEn.join(', ') || '无'));
  ok(missingInZh.length === 0, 'zh 缺失的 key: ' + (missingInZh.join(', ') || '无'));

  // 3) HTML 的 data-i18n 是否都有对应 key
  const used = new Set([...html.matchAll(/data-i18n="([^"]+)"/g)].map((m) => m[1]));
  const notDefined = [...used].filter((k) => !zhKeys.has(k));
  ok(notDefined.length === 0, 'data-i18n 都有定义: ' + (notDefined.join(', ') || '无'));
  // 这些 key 由 JS 动态取用（t("...")），本来就不出现在 data-i18n 上
  const dynamicKeys = new Set(['loading', 'loadFail', 'appVersion', 'langVersionText', 'updateTimeText', 'toastLang', 'sizeUnknown']);
  const unused = [...zhKeys].filter((k) => !dynamicKeys.has(k) && !used.has(k));
  ok(unused.length === 0, '没有多余的 i18n key: ' + (unused.join(', ') || '无'));
}

// 4) 关键新内容确实进去了
ok(html.includes('1.4MB') || html.includes('1.4 MB'), '页面提到 1.4MB 体积');
ok(html.includes('641'), '页面提到 641 条词条');
ok(html.includes('0.6.4'), '页面提到 Pi Network 0.6.4');
ok(!html.includes('下载 Pi 多语言包</a>'), '旧下载文案已替换');
ok(html.includes('app.size'), '页面会读清单的 app.size 显示体积');

// 5) CSP 放行了清单域名
ok(html.includes('raw.githubusercontent.com') && html.includes('cdn.jsdelivr.net'), 'CSP/请求地址含两个清单域名');

console.log(fail === 0 ? '全部通过' : '失败 ' + fail + ' 项');
process.exit(fail === 0 ? 0 : 1);
