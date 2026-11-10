const fs = require('fs');
const y = fs.readFileSync('docker-compose.yml', 'utf8');
const s = y.indexOf("cat > /usr/share/nginx/html/index.html <<'EOF'");
const b = y.indexOf('\n', s) + 1;
const e = y.indexOf('\n        EOF', b);
if (s < 0 || b < 0 || e < 0) { console.error('提取失败'); process.exit(1); }
const html = y.slice(b, e);
fs.writeFileSync('preview/index.html', html, 'utf8');
console.log('已提取 preview/index.html，' + html.length + ' 字符');
