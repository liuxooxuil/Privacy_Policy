const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");
const { readBinFile } = require("@iden3/binfileutils");

const ROOT = path.join(__dirname, "..");
const BUILD = path.join(ROOT, "build");
const TOOLS = path.join(ROOT, "tools");
const ARTIFACTS = path.join(ROOT, "zk-artifacts");
const PTAU = path.join(BUILD, "pot13.ptau");
const R1CS = path.join(BUILD, "shield.r1cs");
const WASM = path.join(BUILD, "shield_js", "shield.wasm");
const INITIAL_ZKEY = path.join(BUILD, "shield_0000.zkey");
const FINAL_ZKEY = path.join(ARTIFACTS, "shield_final.zkey");
const TRANSCRIPT = path.join(ARTIFACTS, "ceremony.json");
const VERIFIER = path.join(ROOT, "contracts", "zk", "Verifier.sol");
const CIRCOM = path.join(TOOLS, "circom.exe");
const SNARK = path.join(ROOT, "node_modules", "snarkjs", "cli.js");

const PTAU_URL = "https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_13.ptau";
const PTAU_BLAKE2B =
  "58efc8bf2834d04768a3d7ffcd8e1e23d461561729beaac4e3e7a47829a1c9066d5320241e124a1a8e8aa6c75be0ba66f65bc8239a0542ed38e11276f6fdb4d9";
const CIRCOM_URL = "https://github.com/iden3/circom/releases/download/v2.1.9/circom-windows-amd64.exe";
const MIN_HUMAN_CONTRIBUTIONS = 2;
const MIN_BEACON_EXP = 10;
const BANNED_BEACONS = new Set(["0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"]);

function blake2bFile(file) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("blake2b512");
    fs.createReadStream(file)
      .on("error", reject)
      .pipe(hash)
      .on("error", reject)
      .on("finish", () => resolve(hash.digest("hex")));
  });
}

function download(url, dest, redirects = 0) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("http://") ? http : https;
    client
      .get(url, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.resume();
          if (redirects > 5) {
            reject(new Error("重定向过多"));
            return;
          }
          resolve(download(new URL(res.headers.location, url).toString(), dest, redirects + 1));
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

async function ensureHermezPtau() {
  fs.mkdirSync(BUILD, { recursive: true });
  if (fs.existsSync(PTAU)) {
    const actual = await blake2bFile(PTAU);
    if (actual === PTAU_BLAKE2B) return;
    console.log("现有 pot13 不是 Hermez 公开文件，删除后重新下载");
    fs.rmSync(PTAU, { force: true });
  }
  const partial = `${PTAU}.partial`;
  fs.rmSync(partial, { force: true });
  console.log("下载 Hermez powersOfTau28_hez_final_13.ptau");
  await download(PTAU_URL, partial);
  const actual = await blake2bFile(partial);
  if (actual !== PTAU_BLAKE2B) {
    fs.rmSync(partial, { force: true });
    throw new Error(`pot13 blake2b 不一致:\n${actual}`);
  }
  fs.renameSync(partial, PTAU);
}

function parseParams(buf) {
  const out = {};
  let offset = 0;
  let lastType = 0;
  while (offset < buf.length) {
    const type = buf[offset];
    offset += 1;
    if (type <= lastType) throw new Error("贡献参数没有按类型排序");
    lastType = type;
    if (type === 1) {
      const len = buf[offset];
      offset += 1;
      out.name = buf.subarray(offset, offset + len).toString("utf8");
      offset += len;
    } else if (type === 2) {
      out.numIterationsExp = buf[offset];
      offset += 1;
    } else if (type === 3) {
      const len = buf[offset];
      offset += 1;
      out.beaconHash = buf.subarray(offset, offset + len).toString("hex");
      offset += len;
    } else {
      throw new Error(`无法识别的贡献参数 ${type}`);
    }
  }
  return out;
}

async function readZkeyContributions(zkeyPath) {
  const { fd, sections } = await readBinFile(zkeyPath, "zkey", 1, 1 << 25, 1 << 23);
  try {
    if (!sections[2] || !sections[10]) throw new Error(`${zkeyPath} 不是带贡献记录的 Groth16 zkey`);
    fd.pos = sections[2][0].p;
    const n8q = await fd.readULE32();
    const g1 = n8q * 2;
    const g2 = n8q * 4;

    const section = sections[10][0];
    fd.pos = section.p;
    const csHash = Buffer.from(await fd.read(64)).toString("hex");
    const count = await fd.readULE32();
    if (count > 1000) throw new Error("贡献数量异常，zkey 解析失败");
    const contributions = [];
    for (let i = 0; i < count; i++) {
      await fd.read(g1 * 3 + g2);
      const transcript = Buffer.from(await fd.read(64)).toString("hex");
      const type = await fd.readULE32();
      const paramLength = await fd.readULE32();
      const params = Buffer.from(await fd.read(paramLength));
      const parsed = parseParams(params);
      contributions.push({
        index: i + 1,
        type: type === 1 ? "beacon" : "human",
        name: parsed.name || "",
        transcript,
        beaconHash: parsed.beaconHash || "",
        numIterationsExp: parsed.numIterationsExp ?? null,
      });
    }
    if (fd.pos !== section.p + section.size) throw new Error("zkey 贡献段长度对不上");
    return { csHash, contributions };
  } finally {
    await fd.close();
  }
}

function policyErrors(contributions, beaconHex) {
  const errors = [];
  const humans = contributions.filter((item) => item.type === "human");
  const beacons = contributions.filter((item) => item.type === "beacon");
  if (humans.length < MIN_HUMAN_CONTRIBUTIONS) {
    errors.push(`人类贡献只有 ${humans.length} 份，至少需要 ${MIN_HUMAN_CONTRIBUTIONS} 名参与者`);
  }
  const names = humans.map((item) => item.name.trim());
  if (names.some((name) => name.length === 0)) errors.push("每个人类贡献都要有名字");
  if (names.some((name) => name.toLowerCase() === "local")) errors.push("贡献名不能使用 local");
  const lowered = names.map((name) => name.toLowerCase());
  if (new Set(lowered).size !== lowered.length) errors.push("人类贡献的名字必须彼此不同");
  if (beacons.length !== 1) errors.push("最终 zkey 必须正好有一次 beacon 贡献");
  const last = contributions[contributions.length - 1];
  if (!last || last.type !== "beacon") errors.push("beacon 必须是最后一次贡献");
  if (last && last.type === "beacon") {
    const expected = beaconHex.toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(expected)) errors.push("beacon 必须是 32 字节十六进制");
    if (last.beaconHash !== expected) errors.push("zkey 里的 beacon 与参数不一致");
    if (BANNED_BEACONS.has(last.beaconHash)) errors.push("beacon 是公开常量，不能用于主网密钥");
    if (last.numIterationsExp === null || last.numIterationsExp < MIN_BEACON_EXP) {
      errors.push(`beacon 迭代指数至少是 ${MIN_BEACON_EXP}`);
    }
  }
  const beaconAt = contributions.findIndex((item) => item.type === "beacon");
  if (beaconAt >= 0 && contributions.slice(0, beaconAt).some((item) => item.type !== "human")) {
    errors.push("beacon 之前只能是人类贡献");
  }
  return errors;
}

module.exports = {
  ROOT,
  BUILD,
  TOOLS,
  ARTIFACTS,
  PTAU,
  R1CS,
  WASM,
  INITIAL_ZKEY,
  FINAL_ZKEY,
  TRANSCRIPT,
  VERIFIER,
  CIRCOM,
  SNARK,
  PTAU_URL,
  PTAU_BLAKE2B,
  CIRCOM_URL,
  MIN_HUMAN_CONTRIBUTIONS,
  blake2bFile,
  download,
  ensureHermezPtau,
  readZkeyContributions,
  policyErrors,
};
