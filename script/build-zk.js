const { execFileSync } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const https = require("https");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const BUILD = path.join(ROOT, "build");
const TOOLS = path.join(ROOT, "tools");
const ARTIFACTS = path.join(ROOT, "zk-artifacts");
const CIRCOM = path.join(TOOLS, "circom.exe");
const PTAU = path.join(BUILD, "pot13.ptau");
const PTAU_URL = "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_13.ptau";
const CIRCOM_URL = "https://github.com/iden3/circom/releases/download/v2.1.9/circom-windows-amd64.exe";

function download(url, dest, redirects = 0) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("http://") ? require("http") : https;
    client
      .get(url, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.resume();
          if (redirects > 5) {
            reject(new Error("重定向过多"));
            return;
          }
          const next = new URL(res.headers.location, url).toString();
          resolve(download(next, dest, redirects + 1));
          return;
        }
        if (res.statusCode !== 200) {
          res.resume();
          reject(new Error(`下载失败 ${res.statusCode} ${url}`));
          return;
        }
        const file = fs.createWriteStream(dest);
        res.pipe(file);
        file.on("finish", () => file.close(() => resolve()));
      })
      .on("error", reject);
  });
}

function run(cmd, args) {
  execFileSync(cmd, args, { cwd: ROOT, stdio: "inherit" });
}

async function main() {
  fs.mkdirSync(BUILD, { recursive: true });
  fs.mkdirSync(TOOLS, { recursive: true });
  fs.mkdirSync(ARTIFACTS, { recursive: true });
  fs.mkdirSync(path.join(ROOT, "contracts", "zk"), { recursive: true });

  if (!fs.existsSync(CIRCOM)) {
    console.log("下载 circom");
    await download(CIRCOM_URL, CIRCOM);
  }
  if (!fs.existsSync(PTAU) || fs.statSync(PTAU).size < 1000000) {
    console.log("本机生成 bn128 pot13。这不是 Hermez 公开仪式，不能用于主网。");
    const snark = path.join(ROOT, "node_modules", "snarkjs", "cli.js");
    const draft = path.join(BUILD, "pot13_0000.ptau");
    const contributed = path.join(BUILD, "pot13_0001.ptau");
    run(process.execPath, [snark, "powersoftau", "new", "bn128", "13", draft]);
    const tauEntropy = crypto.randomBytes(64).toString("hex");
    run(process.execPath, [
      snark,
      "powersoftau",
      "contribute",
      draft,
      contributed,
      "--name=local",
      `-e=${tauEntropy}`,
    ]);
    fs.rmSync(draft, { force: true });
    run(process.execPath, [snark, "powersoftau", "prepare", "phase2", contributed, PTAU]);
    fs.rmSync(contributed, { force: true });
  }

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

  const r1cs = path.join(BUILD, "shield.r1cs");
  const zkey0 = path.join(BUILD, "shield_0000.zkey");
  const zkey1 = path.join(BUILD, "shield_0001.zkey");
  const zkeyFinal = path.join(ARTIFACTS, "shield_final.zkey");
  run(process.execPath, [
    path.join(ROOT, "node_modules", "snarkjs", "cli.js"),
    "groth16",
    "setup",
    r1cs,
    PTAU,
    zkey0,
  ]);

  const entropy = crypto.randomBytes(64).toString("hex");
  run(process.execPath, [
    path.join(ROOT, "node_modules", "snarkjs", "cli.js"),
    "zkey",
    "contribute",
    zkey0,
    zkey1,
    "--name=local",
    `-e=${entropy}`,
  ]);
  fs.rmSync(zkey0, { force: true });

  let beacon = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
  try {
    const latest = await fetch("https://blockchain.info/q/latesthash");
    const text = (await latest.text()).trim();
    if (/^[0-9a-fA-F]{64}$/.test(text)) beacon = text;
  } catch {
    console.log("没有取到比特币区块哈希，使用本地 beacon");
  }
  run(process.execPath, [
    path.join(ROOT, "node_modules", "snarkjs", "cli.js"),
    "zkey",
    "beacon",
    zkey1,
    zkeyFinal,
    beacon,
    "10",
    "-n=local beacon",
  ]);
  fs.rmSync(zkey1, { force: true });

  run(process.execPath, [
    path.join(ROOT, "node_modules", "snarkjs", "cli.js"),
    "zkey",
    "verify",
    r1cs,
    PTAU,
    zkeyFinal,
  ]);

  const verifierPath = path.join(ROOT, "contracts", "zk", "Verifier.sol");
  run(process.execPath, [
    path.join(ROOT, "node_modules", "snarkjs", "cli.js"),
    "zkey",
    "export",
    "solidityverifier",
    zkeyFinal,
    verifierPath,
  ]);

  let sol = fs.readFileSync(verifierPath, "utf8");
  sol = sol.replace("contract Groth16Verifier", "contract ShieldVerifier");
  const note = `// 单方 Groth16 phase-2，仅用于测试网功能验证。
// 主网使用前必须替换本文件。中间 zkey 已在构建时删除，但构建机器仍被信任。
`;
  if (!sol.includes("仅用于测试网功能验证")) {
    sol = sol.replace("pragma solidity", `${note}pragma solidity`);
  }
  fs.writeFileSync(verifierPath, sol);

  const wasmSrc = path.join(BUILD, "shield_js", "shield.wasm");
  fs.copyFileSync(wasmSrc, path.join(ARTIFACTS, "shield.wasm"));
  console.log("ZK 构建完成");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
