const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  BUILD,
  TOOLS,
  ARTIFACTS,
  PTAU,
  R1CS,
  WASM,
  INITIAL_ZKEY,
  CIRCOM,
  SNARK,
  CIRCOM_URL,
  download,
  ensureHermezPtau,
} = require("./ceremony-lib");

function run(cmd, args) {
  execFileSync(cmd, args, { cwd: path.join(__dirname, ".."), stdio: "inherit" });
}

async function main() {
  fs.mkdirSync(BUILD, { recursive: true });
  fs.mkdirSync(TOOLS, { recursive: true });
  fs.mkdirSync(ARTIFACTS, { recursive: true });
  fs.mkdirSync(path.join(__dirname, "..", "contracts", "zk"), { recursive: true });

  if (!fs.existsSync(CIRCOM)) {
    console.log("下载 circom");
    await download(CIRCOM_URL, CIRCOM);
  }
  await ensureHermezPtau();

  run(CIRCOM, [
    path.join("circuits", "shield.circom"),
    "--r1cs",
    "--wasm",
    "--sym",
    "-o",
    "build",
    "-l",
    "node_modules",
  ]);
  fs.copyFileSync(WASM, path.join(ARTIFACTS, "shield.wasm"));

  console.log("生成初始 zkey。这把密钥的陷门是已知的，不能部署。");
  run(process.execPath, [SNARK, "groth16", "setup", R1CS, PTAU, INITIAL_ZKEY]);
  console.log(`初始 zkey: ${INITIAL_ZKEY}`);
  console.log("下一步请至少两名参与者在不同的机器上各执行一次：");
  console.log('  npm run ceremony:contribute -- build/shield_0000.zkey build/shield_0001.zkey --name "参与者名字"');
  console.log("本脚本不会改写 contracts/zk/Verifier.sol。");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
