// 第二轮词表补充：运行时采集到的动态标签、短词和长句
const fs = require('fs');

const targets = [
  'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\langs\\zh-CN.json',
  'C:\\Users\\Administrator\\Desktop\\Pi多语言包\\src\\Resources\\zh-CN.json',
];

const extra = {
  // 诊断/状态页标签
  'Actions': '操作',
  'Consensus': '共识',
  'Container': '容器',
  'Diagnostics': '诊断',
  'Info': '信息',
  'Not available': '不可用',
  'Other': '其他',
  'Incoming connections': '入站连接',
  'Outgoing connections': '出站连接',
  'Latest block:': '最新区块：',
  'State:': '状态：',
  'Public key:': '公钥：',
  'Consensus container:': '共识容器：',
  'Consensus container enabled:': '共识容器已启用：',
  'Consensus container enabled: Yes': '共识容器已启用：是',
  'Consensus container enabled: No': '共识容器已启用：否',
  'PortsChecker container:': '端口检查容器：',
  'Protocol version:': '协议版本：',
  'Node switch on:': '节点开关：',
  'Node switch on: Yes': '节点开关：是',
  'Node switch on: No': '节点开关：否',
  'Node installation date:': '节点安装日期：',
  'Operating system:': '操作系统：',
  'Other Pi Desktop version number:': '其他 Pi 桌面版本号：',
  'Pi Desktop version number:': 'Pi 桌面版本号：',
  'Supporting other nodes:': '支撑其他节点：',
  'Supporting other nodes: Yes': '支撑其他节点：是',
  'Supporting other nodes: No': '支撑其他节点：否',
  'Using Docker Toolbox:': '使用 Docker Toolbox：',
  'Availability (up to 90 days):': '可用性（最多 90 天）：',
  'Turn the Node On': '打开节点',
  'Node Technical Preparation': '节点技术准备',
  'Run the optional Soroban RPC service': '运行可选的 Soroban RPC 服务',
  'Run the optional blockchain API service': '运行可选的区块链 API 服务',
  'Checking Docker…': '正在检查 Docker…',
  'released on': '发布于',
  'exited': '已退出',
  'unknown': '未知',
  'Yes': '是',
  'No': '否',
  'N/A': '不适用',
  'on': '开启',
  'off': '关闭',
  // 长句（运行时是完整文本节点，源码里按行拆开提取不到）
  'You\u2019re enabled to run the Node version that contains the blockchain. By turning on the switch below, your computer will start running a Docker container that runs the consensus algorithm and enables you to observe the Pi Testnet. It will stay on until you switch it off. Switching off means your computer does not run the blockchain.':
    '你可以运行包含区块链的节点版本。打开下面的开关后，你的计算机会启动一个运行共识算法的 Docker 容器，让你能够观察 Pi 测试网。节点会一直运行，直到你关闭开关；关闭开关意味着你的计算机不再运行区块链。',
  'You\u2019re a node candidate. We have not selected the SuperNodes or Nodes that participate in the Pi Testnet yet which requires passing KYC. We will make selection soon.':
    '你已被列为节点候选。参与 Pi 测试网的超级节点或节点需要先通过 KYC，目前我们尚未完成筛选，很快会进行选择。',
  'from your computer. Please be cautious of using this action. It may take a while for you to restore your local blockchain data.':
    '从你的计算机上。请谨慎使用此操作，恢复本地区块链数据可能需要一段时间。',
  ', which is a platform for securely building and sharing applications. Docker encloses all the blockchain complexity in a \u201ccontainer\u201d that is isolated from the rest of your computer, respecting your privacy and security.':
    '，这是一个安全构建和分享应用的平台。Docker 把所有区块链复杂性封装在一个\u201c容器\u201d里，与计算机的其他部分隔离，保护你的隐私和安全。',
  'ports. We check whether they are already open, and open the rest on your router automatically. The check needs those ports free, so your node pauses for a minute or two and comes back on its own.':
    '端口。我们会检查它们是否已开放，并自动在你的路由器上开放其余的端口。检查需要这些端口空闲，所以你的节点会暂停一两分钟，然后自行恢复。',
  'The Pi blockchain requires': 'Pi 区块链需要',
  'for answers or join the node Applicants chat in the Pi App.': '寻找答案，或在 Pi 应用里加入节点申请者聊天。',
  'Pi nodes reach each other over': 'Pi 节点之间通过以下方式互相连接：',
  'Addressing node reward issue': '处理节点奖励问题',
  'Introducing notification system,': '引入通知系统，',
  'Welcome to in-app node updates. This is the first update.': '欢迎使用应用内节点更新，这是第一次更新。',
  'We are currently addressing the issue of node rewards occasionally displaying as zero. Even when you receive zero rewards, your nodes availability statistics are still being stored, and we are aiming to distribute past rewards retrospectively.':
    '我们正在处理节点奖励偶尔显示为零的问题。即使你收到零奖励，你的节点可用性统计数据仍会被记录，我们会追溯发放过去的奖励。',
  'Your Blockchain API service will temporarily stop until a new node version is released, but your node will still participate in the blockchain. No action is required from your side.':
    '你的区块链 API 服务将暂时停止，直到新版本节点发布；但这期间你的节点仍会参与区块链。你这边无需操作。',
  'Your Blockchain API will stop due to upgrade. - NO ACTION NEEDED':
    '由于升级，你的区块链 API 将停止运行。- 无需操作',
};

for (const t of targets) {
  const j = JSON.parse(fs.readFileSync(t, 'utf8'));
  let added = 0, replaced = 0;
  for (const [k, v] of Object.entries(extra)) {
    if (j.entries[k] === undefined) { j.entries[k] = v; added++; }
    else if (j.entries[k] !== v) { j.entries[k] = v; replaced++; }
  }
  j.entries = Object.fromEntries(Object.entries(j.entries).sort((a, b) => a[0].localeCompare(b[0])));
  fs.writeFileSync(t, JSON.stringify(j, null, 2), 'utf8');
  console.log(t, '新增', added, '覆盖', replaced, '总条数', Object.keys(j.entries).length);
}
