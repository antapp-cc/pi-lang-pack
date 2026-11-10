// 独立参照实现：按 Electron 读 asar 的方式解析并校验，不依赖 AU3 侧任何代码。
// 用来证明 AU3 重打包出来的 asar 结构合法、integrity 没算错。
// 用法: node verify-asar.js <app.asar> [更多 asar...]
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function readHeader(buf) {
  const headerSize = buf.readUInt32LE(4);
  const jsonLen = buf.readUInt32LE(12);
  const json = buf.toString('utf8', 16, 16 + jsonLen);
  return { headerSize, jsonLen, dataStart: 8 + headerSize, json: JSON.parse(json) };
}

function walk(node, prefix, out) {
  for (const [name, val] of Object.entries(node)) {
    if (name === 'files') continue;
    const p = prefix + name;
    if (val.files) walk(val.files, p + '/', out);
    else out.push({ path: p, size: val.size, offset: Number(val.offset), integrity: val.integrity });
  }
}

function verify(file) {
  const buf = fs.readFileSync(file);
  const h = readHeader(buf);
  const files = [];
  walk(h.json.files, '', files);

  let problems = 0;
  let maxEnd = 0;
  let hashChecked = 0;
  let hashBad = 0;

  for (const f of files) {
    const end = f.offset + f.size;
    if (end > maxEnd) maxEnd = end;
    if (f.offset < 0 || f.size < 0 || end > buf.length - h.dataStart) {
      console.log(`  [越界] ${f.path} offset=${f.offset} size=${f.size} dataArea=${buf.length - h.dataStart}`);
      problems++;
      continue;
    }
    if (f.integrity && f.integrity.hash) {
      const data = buf.subarray(h.dataStart + f.offset, h.dataStart + end);
      const actual = crypto.createHash('sha256').update(data).digest('hex');
      hashChecked++;
      if (actual !== f.integrity.hash) {
        hashBad++;
        problems++;
        if (problems <= 5) console.log(`  [哈希不符] ${f.path}: 头部 ${f.integrity.hash.slice(0, 12)} 实际 ${actual.slice(0, 12)}`);
      }
    }
  }

  console.log(`  ${path.basename(file)}: ${files.length} 个文件, 数据区 ${buf.length - h.dataStart} 字节, 头部 ${h.jsonLen} 字节, integrity 校验 ${hashChecked} 个（不符 ${hashBad}）, 问题 ${problems}`);
  return { files: files.length, problems, paths: files.map((f) => f.path) };
}

const args = process.argv.slice(2);
if (args.length === 0) {
  console.log('用法: node verify-asar.js <app.asar> [更多 asar...]');
  process.exit(2);
}

let total = 0;
let results = [];
for (const f of args) {
  if (!fs.existsSync(f)) { console.log(`[跳过] 不存在: ${f}`); continue; }
  console.log(`校验 ${f}`);
  const r = verify(f);
  total += r.problems;
  results.push({ file: f, ...r });
}

// 多个包对比时，文件清单应一致（用于「注入前的包」vs「还原后的包」）
if (results.length > 1) {
  const base = results[0].paths.join('\n');
  for (let i = 1; i < results.length; i++) {
    const diff = results[i].paths.join('\n') === base;
    console.log(`文件清单一致 [${path.basename(results[0].file)}] vs [${path.basename(results[i].file)}]: ${diff ? '是' : '否'}`);
    if (!diff) total++;
  }
}

console.log(total === 0 ? '校验通过' : `发现 ${total} 个问题`);
process.exit(total === 0 ? 0 : 1);
