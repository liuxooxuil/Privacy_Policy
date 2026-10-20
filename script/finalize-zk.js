const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  ROOT,
  ARTIFACTS,
  PTAU,
  R1CS,
  WASM,
  FINAL_ZKEY,
  TRANSCRIPT,
  VERIFIER,
  SNARK,
  PTAU_BLAKE2B,
  ensureHermezPtau,
  readZkeyContributions,
  policyErrors,
} = require("./ceremony-lib");

function fail(message) {
  console.error(message);
  process.exit(1);
}

function argValue(args, name) {
  const inline = args.find((arg) => arg.startsWith(`${name}=`));
  if (inline) return inline.slice(name.length + 1);
  const index = args.indexOf(name);
  if (index >= 0) return args[index + 1] || "";
  return "";
}

function run(args) {
  execFileSync(process.execPath, [SNARK, ...args], { cwd: ROOT, stdio: "inherit" });
}

async function main() {
  const args = process.argv.slice(2);
  const zkey = argValue(args, "--zkey");
  const beacon = argValue(args, "--beacon").trim().toLowerCase();
  const inspect = args.includes("--inspect");
  if (!zkey) fail("用法: npm run ceremony:finalize -- --zkey <最后一把人类贡献.zkey> --beacon <64位十六进制>");
  if (!fs.existsSync(zkey)) fail(`找不到 ${zkey}`);

  const current = await readZkeyContributions(zkey);
  if (inspect) {
    console.log(JSON.stringify(current, null, 2));
    const embedded = [...current.contributions].reverse().find((item) => item.type === "beacon");
    const expected = beacon || (embedded ? embedded.beaconHash : "");
    const errors = expected ? policyErrors(current.contributions, expected) : ["这把 zkey 没有 beacon"];
    if (errors.length) {
      for (const error of errors) console.error(error);
      process.exit(1);
    }
    return;
  }
  if (!/^[0-9a-f]{64}$/.test(beacon)) fail("beacon 必须是 32 字节十六进制，并且要来自最后一次人类贡献公开之后才出现的比特币区块");

  await ensureHermezPtau();
  if (!fs.existsSync(R1CS)) fail("缺少 build/shield.r1cs。先运行 npm run build:zk");

  fs.mkdirSync(ARTIFACTS, { recursive: true });
  if (current.contributions.some((item) => item.type === "beacon")) {
    fail("这把 zkey 已经包含 beacon。请把加 beacon 之前的最后一把人类贡献传给 --zkey");
  }
  const previewErrors = policyErrors(
    current.contributions.concat([
      { type: "beacon", name: "bitcoin beacon", beaconHash: beacon, numIterationsExp: 10 },
    ]),
    beacon
  );
  if (previewErrors.length) fail(previewErrors.join("\n"));

  const stamped = path.join(path.dirname(R1CS), "shield_beacon.zkey");
  run(["zkey", "beacon", zkey, stamped, beacon, "10", "-n=bitcoin beacon"]);
  const finalContributions = await readZkeyContributions(stamped);
  const errors = policyErrors(finalContributions.contributions, beacon);
  if (errors.length) {
    fs.rmSync(stamped, { force: true });
    fail(errors.join("\n"));
  }

  run(["zkey", "verify", R1CS, PTAU, stamped]);
  run(["zkey", "export", "solidityverifier", stamped, VERIFIER]);
  run(["zkey", "export", "verificationkey", stamped, path.join(ARTIFACTS, "verification_key.json")]);
  fs.copyFileSync(stamped, FINAL_ZKEY);

  let sol = fs.readFileSync(VERIFIER, "utf8");
  sol = sol.replace("contract Groth16Verifier", "contract ShieldVerifier");
  const names = finalContributions.contributions
    .filter((item) => item.type === "human")
    .map((item) => item.name)
    .join(", ");
  const note = `// 由 script/finalize-zk.js 导出。phase-1 是 Hermez powersOfTau28_hez_final_13.ptau。
// 人类贡献: ${names}
// beacon: ${beacon}
// 部署前核对 zk-artifacts/ceremony.json。旧的 PrivacyFactory 不会改用这把密钥。
`;
  sol = sol.replace(/\/\/ 由 script\/finalize-zk\.js[\s\S]*?pragma solidity/, note + "pragma solidity");
  if (!sol.includes("由 script/finalize-zk.js")) {
    sol = sol.replace("pragma solidity", `${note}pragma solidity`);
  }
  fs.writeFileSync(VERIFIER, sol);
  if (fs.existsSync(WASM)) fs.copyFileSync(WASM, path.join(ARTIFACTS, "shield.wasm"));

  const transcript = {
    phase1: "powersOfTau28_hez_final_13.ptau",
    phase1Blake2b: PTAU_BLAKE2B,
    circuitHash: finalContributions.csHash,
    beacon,
    beaconIterationsExp: 10,
    contributions: finalContributions.contributions,
  };
  fs.writeFileSync(TRANSCRIPT, `${JSON.stringify(transcript, null, 2)}\n`);
  console.log(`已导出 ${VERIFIER}`);
  console.log(`仪式记录 ${TRANSCRIPT}`);
  console.log("请部署新的 ShieldVerifier 和新的 PrivacyFactory。已部署的工厂仍使用旧验证器。");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
