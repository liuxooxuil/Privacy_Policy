const path = require("path");
const crypto = require("crypto");
const { groth16 } = require("snarkjs");
const { buildPoseidon } = require("circomlibjs");
const { ethers } = require("ethers");

const LEVELS = 16;
const FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const NULLIFIER_DOMAIN = 1n << 160n;
const WASM = path.join(__dirname, "..", "zk-artifacts", "shield.wasm");
const ZKEY = path.join(__dirname, "..", "zk-artifacts", "shield_final.zkey");

let poseidon;

async function init() {
  if (!poseidon) poseidon = await buildPoseidon();
  return poseidon;
}

function toBig(value) {
  const out = poseidon.F.toObject(value);
  return typeof out === "bigint" ? out : BigInt(out.toString());
}

function hash(inputs) {
  return toBig(poseidon(inputs.map((item) => BigInt(item))));
}

function randomSecret() {
  let secret = 0n;
  while (secret === 0n) {
    secret = BigInt(`0x${crypto.randomBytes(32).toString("hex")}`) % FIELD;
  }
  return secret;
}

function createNote(owner) {
  const secret = randomSecret();
  const ownerN = BigInt(owner);
  return { secret, owner: ownerN, commitment: hash([secret, ownerN]) };
}

function nullifierOf(secret) {
  return hash([BigInt(secret), NULLIFIER_DOMAIN]);
}

function leafOf(commitment, amount, token) {
  return hash([BigInt(commitment), BigInt(amount), BigInt(token)]);
}

function toBytes32(value) {
  return ethers.zeroPadValue(ethers.toBeHex(BigInt(value)), 32);
}

/**
 * 生成花费证明。note 是正在花的票据。
 * 输出三选一或组合：toNote（新收款承诺）、changeNote（找零）、amountOut（提到绑定地址）。
 * 有 amountOut 时，收款地址必须是 note.owner。fee 和 relayer 只在提现时使用。
 */
async function proveSpend({
  root,
  siblings,
  indices,
  note,
  amount,
  token = 0n,
  toNote = null,
  changeNote = null,
  amountOut = 0n,
  fee = 0n,
  relayer = 0n,
}) {
  await init();
  const changeAmount = changeNote ? BigInt(changeNote.amount) : 0n;
  const out = BigInt(amountOut);
  const feeN = BigInt(fee);
  const total = BigInt(amount);
  let sendAmount = 0n;
  if (toNote) {
    sendAmount = total - changeAmount - out - feeN;
    if (sendAmount <= 0n) throw new Error("转出金额不足");
  } else if (changeAmount + out + feeN !== total) {
    throw new Error("金额不守恒");
  }
  const recipient = out + feeN > 0n ? BigInt(note.owner) : 0n;
  const input = {
    root: BigInt(root).toString(),
    nullifierHash: nullifierOf(note.secret).toString(),
    newLeaf: toNote ? leafOf(toNote.commitment, sendAmount, token).toString() : "0",
    changeLeaf: changeNote ? leafOf(changeNote.commitment, changeAmount, token).toString() : "0",
    recipient: recipient.toString(),
    relayer: (out + feeN > 0n ? BigInt(relayer) : 0n).toString(),
    fee: feeN.toString(),
    amountOut: out.toString(),
    token: BigInt(token).toString(),
    secret: BigInt(note.secret).toString(),
    owner: BigInt(note.owner).toString(),
    amount: BigInt(amount).toString(),
    pathElements: [...siblings].map((item) => BigInt(item).toString()),
    pathIndices: [...indices].map((item) => BigInt(item).toString()),
    sendAmount: (toNote ? sendAmount : 0n).toString(),
    changeAmount: changeAmount.toString(),
    newCommitment: toNote ? BigInt(toNote.commitment).toString() : "0",
    changeCommitment: changeNote ? BigInt(changeNote.commitment).toString() : "0",
  };

  if (input.pathElements.length !== LEVELS || input.pathIndices.length !== LEVELS) {
    throw new Error(`Merkle 路径必须是 ${LEVELS} 层`);
  }

  const { proof, publicSignals } = await groth16.fullProve(input, WASM, ZKEY);
  const raw = await groth16.exportSolidityCallData(proof, publicSignals);
  const args = JSON.parse(`[${raw}]`);
  return {
    pA: args[0],
    pB: args[1],
    pC: args[2],
    pubSignals: args[3],
    sendAmount: toNote ? sendAmount : 0n,
  };
}

module.exports = {
  LEVELS,
  FIELD,
  NULLIFIER_DOMAIN,
  init,
  hash,
  randomSecret,
  createNote,
  nullifierOf,
  leafOf,
  toBytes32,
  proveSpend,
};
