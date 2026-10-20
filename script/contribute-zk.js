const { spawnSync } = require("child_process");
const fs = require("fs");
const { SNARK } = require("./ceremony-lib");

function fail(message) {
  console.error(message);
  process.exit(1);
}

const args = process.argv.slice(2);
if (args.some((arg) => arg === "-e" || arg === "--entropy" || arg.startsWith("-e=") || arg.startsWith("--entropy="))) {
  fail("不要用 -e 传入熵。随机数会留在命令行历史里。直接运行，按 snarkjs 的提示输入。");
}

let name = "";
const positional = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--name" || args[i] === "-n") {
    name = args[i + 1] || "";
    i += 1;
  } else if (args[i].startsWith("--name=")) {
    name = args[i].slice("--name=".length);
  } else {
    positional.push(args[i]);
  }
}

if (positional.length !== 2 || !name.trim()) {
  fail('用法: npm run ceremony:contribute -- <上一把.zkey> <新的.zkey> --name "参与者名字"');
}
if (name.trim().toLowerCase() === "local") fail("贡献名不能使用 local");
if (!fs.existsSync(positional[0])) fail(`找不到 ${positional[0]}`);
console.log("请在参与者自己的机器上输入熵。不要把第二份贡献做在已经生成过上一份贡献的机器上。");

const child = spawnSync(
  process.execPath,
  [SNARK, "zkey", "contribute", positional[0], positional[1], "--name", name.trim()],
  { stdio: "inherit" }
);
process.exit(child.status === null ? 1 : child.status);
