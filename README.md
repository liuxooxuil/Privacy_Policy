# BNB Smart Chain 隐私协议与隐匿转账 — 使用文档

本仓库包含三个独立合约，部署在 **BNB Smart Chain（币安智能链）**：

| 文件 | 合约 | 作用 |
|------|------|------|
| `Privacy_Policy.sol` | `PrivacyPolicy` | 链上隐私协议登记、版本与用户确认 |
| `PrivacyTransfer.sol` | `PrivacyTransfer` | 资金锁在同一个合约里，存款和合约内划转不出现收款地址 |
| `contracts/PrivacyFactory.sol` | `PrivacyFactory` | 零知识池。存款和合约内划转不出现收款地址，花费时看不出是哪一张票据 |

`PrivacyPolicy` 与 `PrivacyTransfer` 无依赖，可分别部署。零知识池要按下面的顺序部署四个合约。`PrivacyTransfer` 不是零知识合约，secret 会出现在花费交易里。

- 主网 Chain ID：`56`（[BscScan](https://bscscan.com)）
- 测试网 Chain ID：`97`（[BscScan Testnet](https://testnet.bscscan.com)）
- 编译器：Solidity `0.8.20` 或更高
- Optimizer：建议开启，runs = `200`

---

## 0. 零知识隐藏转账 PrivacyFactory

收款人自己生成 `secret`，链下算出承诺，只把承诺交给付款人：

```text
commitment = Poseidon(secret, 收款人地址)
```

付款人把 BNB 或 BEP20 存进池子。同一代币的存款进同一棵 Merkle 树。花费者提交 Groth16 证明，证明自己知道某张未花费票据的 `secret`，但不指出是哪一张。`secret` 不上链。

| 操作 | 收款钱包 | 金额 | 花的是哪张票据 |
|------|----------|------|----------------|
| `deposit` / `depositToken` | 不出现 | 公开 | 新叶子公开 |
| `stealthTransfer` | 不出现 | 不公开 | 不公开 |
| `withdraw` | 出现，且必须是承诺里绑定的地址 | 公开 | 不公开 |
| `spend` | 只有提现那一部分出现 | 只有提出的部分公开 | 不公开 |

仍然公开：存款人 `tx.from`、存款金额、提现收款地址和提现金额。某个金额如果池子里只有一笔，外界仍可能凭金额把存入和提现对上。把钱拆成池子里常见的面额再提现，匿名集会更大。

每个 `secret` 只能花一次。承诺绑错地址或 `secret` 丢失，没有管理员可以找回。树深 16，最多 65536 张叶子。承诺一旦出现在内存池，别人可以抢先存一笔占住它，你的存款会失败。

`newIndex` 或 `changeIndex` 等于 `2^32 - 1` 时，表示这一侧没有新叶子。

当前仓库里的 `contracts/zk/Verifier.sol` 来自本机仪式，**只能做功能测试**。掌握仪式随机数的人可以伪造证明。主网放真实资金前，要用公开 phase-1 和多方 phase-2 重新生成验证合约。

### 0.1 部署

编译器 `0.8.20`，Optimizer runs = `200`，EVM `shanghai`。网络必须是 BSC 主网 56 或测试网 97。

按顺序部署，后一个的构造参数填前一个的地址：

1. `contracts/zk/Hash2.sol` 里的 `Hash2`
2. `contracts/zk/Hash3.sol` 里的 `Hash3`
3. `contracts/zk/Verifier.sol` 里的 `ShieldVerifier`
4. `contracts/PrivacyFactory.sol` 里的 `PrivacyFactory(hash2, hash3, verifier)`

Remix 需要把 `contracts/` 和 `contracts/zk/` 一起放进工程。`PoseidonT3.sol`、`PoseidonT4.sol` 要和 `Hash2`、`Hash3` 在同一目录。

证明在浏览器或 Node 里生成，用仓库里的 `sdk/privacy.js`、`zk-artifacts/shield.wasm` 和 `zk-artifacts/shield_final.zkey`。重新生成密钥：

```text
npm install
node script/build-zk.js
```

### 0.2 收款人生成承诺

```js
const { init, createNote, toBytes32, proveSpend } = require("./sdk/privacy");

await init();
const note = createNote(recipientAddress);
// note.secret      只留给自己
// note.commitment  发给付款人
// toBytes32(note.commitment) 是存款参数
```

`Poseidon` 和 `keccak256(secret, address)` 不是同一个值。旧的 `computeCommitment` 算出来的承诺不能存进这个池子。

### 0.3 存款

```js
await factory.deposit(toBytes32(note.commitment), { value: ethers.parseEther("0.1") });

await token.approve(factoryAddress, amount);
await factory.depositToken(tokenAddress, amount, toBytes32(note.commitment));
```

扣费代币按池子实际收到的数量记账。`Deposited` 事件给出 `leafIndex`、`amount` 和 `leaf`。收款人用自己的 `commitment` 过滤这个事件。事件里没有收款地址。

不要向工厂直接转 BNB。

### 0.4 提现

必须提到承诺里的那个地址。交易可以由别人发，gas 可以由别人付。

```js
const proof = await factory.proofOf(leafIndex);
const args = await proveSpend({
  root: proof.root,
  siblings: proof.siblings,
  indices: proof.indices,
  note,
  amount,
  token: 0n, // BEP20 填代币地址的 BigInt
  amountOut: amount,
  fee: 0n,
  relayer: 0n,
});
await factory.withdraw(args.pA, args.pB, args.pC, args.pubSignals);
```

`fee > 0` 时，`relayer` 填代付地址，费用从票据里扣，币种和票据相同。

### 0.5 合约内划转和部分提出

全额划给下一手：下一手先用自己的地址做 `createNote`，只把 `commitment` 给你。

```js
const args = await proveSpend({
  root: proof.root,
  siblings: proof.siblings,
  indices: proof.indices,
  note,
  amount,
  toNote: { commitment: nextCommitment },
});
await factory.stealthTransfer(args.pA, args.pB, args.pC, args.pubSignals);
```

部分划转时，自己再生成一张找零票据，并写上找零金额：

```js
const change = createNote(myAddress);
change.amount = changeAmount;
```

`proveSpend` 里同时传入 `toNote` 和 `changeNote`。事件 `StealthTransferred` 里的 `newIndex` 是对方的叶子，`changeIndex` 是找零叶子。没有钱包地址，也没有金额。对方用约定好的金额计算自己的叶子，对上 `newLeaf`。

既要提出一部分、又要把剩下的留在池子里，用 `spend`，传入 `changeNote` 和 `amountOut`。`withdraw` 不允许找零，`stealthTransfer` 不允许提现。

同一笔证明如果因为新的存款改变了树根而还没上链，原来的 `root` 仍然有效，不需要重算。`nullifier` 用过之后，第二笔会失败。

### 0.6 工厂接口

```json
[
  "function LEVELS() view returns (uint256)",
  "function nextIndex() view returns (uint256)",
  "function currentRoot() view returns (uint256)",
  "function computeLeaf(uint256 commitment, uint256 amount, uint256 token) view returns (uint256)",
  "function proofOf(uint256 leafIndex) view returns (uint256 root, uint256[16] siblings, uint256[16] indices)",
  "function deposit(bytes32 commitment) payable",
  "function depositToken(address token, uint256 amount, bytes32 commitment)",
  "function withdraw(uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256[9] pubSignals)",
  "function stealthTransfer(uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256[9] pubSignals)",
  "function spend(uint256[2] pA, uint256[2][2] pB, uint256[2] pC, uint256[9] pubSignals)",
  "event Deposited(uint256 indexed commitment, uint256 indexed token, uint256 amount, uint32 leafIndex, uint256 leaf)",
  "event StealthTransferred(uint256 indexed nullifier, uint256 indexed token, uint256 newLeaf, uint256 changeLeaf, uint32 newIndex, uint32 changeIndex)",
  "event Withdrawn(uint256 indexed nullifier, uint256 indexed token, address indexed recipient, uint256 amountOut, uint256 fee)"
]
```

`pubSignals` 的顺序是：`root`、`nullifier`、`newLeaf`、`changeLeaf`、`recipient`、`relayer`、`fee`、`amountOut`、`token`。不要手改这 9 个数，改一个证明就失效。

---

## 1. 非零知识隐匿转账能做什么、不能做什么

下面第 2 节到第 8 节讲的是 `PrivacyTransfer.sol`。它只保证存款和合约内划转的 calldata 里没有收款地址。花费时 `secret` 会原样出现在交易里，存入和提出可以通过同一个承诺对上。需要零知识隐藏时，用第 0 节的池子。

`PrivacyTransfer` 把资金锁进合约，用「承诺哈希」记账，而不是用钱包地址记账。

| 操作 | 收款钱包是否出现在这笔交易里 |
|------|------------------------------|
| `deposit` / `depositToken` 存款 | 否，只有 `commitment` |
| `stealthTransfer` 合约内划转 | 否，只有承诺哈希 |
| `withdraw` / `withdrawWithSig` 提现 | 是（资金打进钱包时无法避免） |

**仍然公开可见：**

- 存款交易的 `tx.from`（付 gas 的账户）
- 金额
- 提现交易的发起者和内部转账的收款地址

这不是混币器，也不能抹去付款人。丢失 `secret` 则资金无法取出，合约没有管理员、不能代为找回。

---

## 2. 用 Remix 部署

### 2.1 准备钱包

1. 安装 [MetaMask](https://metamask.io/)
2. 添加 BSC 网络：

| 字段 | 主网 | 测试网 |
|------|------|--------|
| 网络名称 | BNB Smart Chain | BSC Testnet |
| RPC | `https://bsc-dataseed.binance.org` | `https://data-seed-prebsc-1-s1.binance.org:8545` |
| Chain ID | `56` | `97` |
| 符号 | BNB | tBNB |
| 浏览器 | `https://bscscan.com` | `https://testnet.bscscan.com` |

3. 测试网领水：https://testnet.bnbchain.org/faucet-smart

### 2.2 编译

1. 打开 [Remix](https://remix.ethereum.org)
2. 将 `Privacy_Policy.sol`、`PrivacyTransfer.sol` 上传到 Remix
3. Compiler 选 `0.8.20` 或以上
4. 勾选 **Enable optimization**，runs 填 `200`
5. Compile

### 2.3 部署 PrivacyTransfer（隐匿转账）

1. 左侧 **Deploy & Run**
2. Environment 选 **Injected Provider - MetaMask**
3. 合约选 `PrivacyTransfer`
4. 无构造参数，直接 Deploy
5. 在区块浏览器验证源码，方便他人审计

部署后把合约地址保存下来，下文记为 `PRIVACY_TRANSFER`。

### 2.4 部署 PrivacyPolicy（隐私协议，可选）

构造参数：

| 参数 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `_projectName` | string | 项目名称 | `Example DApp` |
| `_operatorName` | string | 运营主体 | `XX 科技有限公司` |
| `_contactEmail` | string | 隐私事务邮箱 | `privacy@example.com` |
| `_website` | string | 官网（含 https） | `https://example.com` |
| `_contentHash` | bytes32 | 完整协议正文的 keccak256 | 见下方 |
| `_documentURI` | string | 完整协议托管地址 | `ipfs://bafy...` 或 HTTPS |

计算 `_contentHash`（ethers v6）：

```js
const hash = ethers.keccak256(ethers.toUtf8Bytes(完整协议文本));
```

部署前请把 `Privacy_Policy.sol` 顶部注释里的 `【项目名称】`、联系方式和生效日期改成实际信息。本模板不构成法律意见，上线前应由律师审阅。

---

## 3. 隐匿转账：推荐流程

核心公式：

```text
commitment = keccak256(abi.encodePacked(secret, 收款人地址))
```

- `secret`：收款人自己生成的 32 字节随机数，**不要发给付款人，不要发到链上**（提现时才会用）
- `commitment`：可以安全发给付款人，付款人拿它去存款

ethers v6 计算：

```js
import { ethers } from "ethers";

const secret = ethers.hexlify(ethers.randomBytes(32));
const commitment = ethers.solidityPackedKeccak256(
  ["bytes32", "address"],
  [secret, recipientAddress]
);
```

也可以在 Remix 里调用只读方法 `computeCommitment(secret, recipientAddress)` 得到同样结果。请先保存 `secret`，丢失无法提现。

### 3.1 场景 A：付款人转给指定收款人（收款地址不上链）

```
收款人 ──生成 secret + commitment──► 把 commitment 发给付款人
付款人 ──deposit(commitment)──────► 合约记账（链上看不到收款地址）
收款人 ──withdraw(secret)─────────► 资金进入收款钱包（此时地址可见）
```

**收款人**

```js
const secret = ethers.hexlify(ethers.randomBytes(32));
const commitment = ethers.solidityPackedKeccak256(
  ["bytes32", "address"],
  [secret, await signer.getAddress()]
);
// 把 commitment 通过加密聊天发给付款人
// 本地妥善保存 secret
```

**付款人存 BNB**

```js
const contract = new ethers.Contract(PRIVACY_TRANSFER, abi, signer);

await contract.deposit(commitment, {
  value: ethers.parseEther("0.1"),
});
```

**付款人存 BEP20**

```js
const token = new ethers.Contract(TOKEN, erc20Abi, signer);
const amount = ethers.parseUnits("100", 18);

await (await token.approve(PRIVACY_TRANSFER, amount)).wait();
await contract.depositToken(TOKEN, amount, commitment);
```

BscScan 上这笔存款只能看到：付款人 → 本合约，以及一个 32 字节承诺。看不到收款钱包。

**确认到账（任何人可查）**

```js
const [token, amount] = await contract.noteOf(commitment);
// token === ethers.ZeroAddress 表示 BNB
// amount > 0 表示承诺下有余额
```

**收款人提现**

必须用承诺所绑定的那个钱包调用。`recipient` 填 `ethers.ZeroAddress` 则打给自己：

```js
await contract.withdraw(secret, ethers.ZeroAddress);
// 或指定另一地址收款（发起交易的仍是绑定钱包）：
await contract.withdraw(secret, "0x收款或自己的地址");
```

### 3.2 场景 B：合约内再转给下一个人（仍然不出现地址）

对方先按 3.1 的方法生成 **自己的** `newSecret` 和 `newCommitment`，把 `newCommitment` 给你。

你用**当前票据的 secret**，并且必须用绑定的钱包调用：

```js
// 全额转出，找零承诺填 32 字节全 0
await contract.stealthTransfer(
  secret,
  newCommitment,
  amount,
  ethers.ZeroHash
);
```

部分转出时必须同时准备一张「找零承诺」（绑定你自己）：

```js
const changeSecret = ethers.hexlify(ethers.randomBytes(32));
const changeCommitment = ethers.solidityPackedKeccak256(
  ["bytes32", "address"],
  [changeSecret, await signer.getAddress()]
);

await contract.stealthTransfer(
  secret,              // 当前票据密钥
  newCommitment,       // 对方的承诺
  sendAmount,          // 转出金额
  changeCommitment     // 剩余金额进入这张新票据
);
```

划转后：

- 旧 `commitment` 作废（`spent` 为 true）
- 对方用 `newSecret` 提现或再次划转
- 你自己的剩余资金用 `changeSecret` 控制

### 3.3 场景 C：收款人没有 BNB 付 gas（代付提现）

收款人链下签名，代付人提交 `withdrawWithSig`。

签名消息（与合约一致）：

```text
inner  = keccak256(abi.encode(
           secret, recipient, relayerFee, relayer, deadline,
           本合约地址, chainId
         ))
digest = keccak256("\x19Ethereum Signed Message:\n32" || inner)
```

ethers v6 示例：

```js
const recipient = await ownerSigner.getAddress();
const relayerFee = 0n;
const relayer = ethers.ZeroAddress;
const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

const inner = ethers.keccak256(
  ethers.AbiCoder.defaultAbiCoder().encode(
    [
      "bytes32",
      "address",
      "uint256",
      "address",
      "uint256",
      "address",
      "uint256",
    ],
    [
      secret,
      recipient,
      relayerFee,
      relayer,
      deadline,
      PRIVACY_TRANSFER,
      56, // 测试网改 97
    ]
  )
);

const signature = await ownerSigner.signMessage(ethers.getBytes(inner));
const { v, r, s } = ethers.Signature.from(signature);

await contract.connect(relayerSigner).withdrawWithSig(
  secret,
  recipient,     // owner，必须与承诺绑定地址一致
  recipient,     // 资金打入地址
  relayerFee,
  relayer,
  deadline,
  v,
  r,
  s
);
```

`relayerFee > 0` 时，费用从票据余额中扣，付给 `relayer`，代币种类与票据相同（BNB 票据付 BNB，USDT 票据付 USDT）。

---

## 4. 隐私协议合约用法

部署后常用方法：

```js
const policy = new ethers.Contract(PRIVACY_POLICY, policyAbi, signer);

// 读当前版本与文档地址
const [
  version, contentHash, uri, effectiveAt,
  project, operator, email, site,
] = await policy.currentPolicy();

// 读某一章摘要（1 ~ 14）
const [title, body] = await policy.getSection(1);

// 校验本地全文是否与链上哈希一致
const ok = await policy.verifyContent(ethers.toUtf8Bytes(全文));

// 用户确认当前版本（每个地址每个版本一次）
await policy.accept();
const accepted = await policy.hasAccepted(userAddress);
```

运营方更新协议：

```js
await policy.updatePolicy(
  version + 1n,
  newContentHash,
  "ipfs://新CID"
);
```

用户在新版本上需要重新 `accept()`。

---

## 5. PrivacyTransfer 接口一览

### 写入

| 方法 | 说明 |
|------|------|
| `deposit(bytes32 commitment) payable` | 存入 BNB |
| `depositToken(address token, uint256 amount, bytes32 commitment)` | 存入 BEP20，需先 `approve` |
| `stealthTransfer(bytes32 secret, bytes32 toCommitment, uint256 amount, bytes32 changeCommitment)` | 合约内划转 |
| `withdraw(bytes32 secret, address recipient)` | 绑定钱包自行提现 |
| `withdrawWithSig(...)` | 签名代付提现 |

### 只读

| 方法 | 说明 |
|------|------|
| `computeCommitment(bytes32 secret, address owner)` | 计算承诺 |
| `noteOf(bytes32 commitment)` | 返回 `(token, amount)`，`token = 0x0` 为 BNB |
| `spent(bytes32 commitment)` | 该承诺是否已花费（不可复用） |

### 事件

- `Deposited(commitment, token, amount)` — 无收款地址
- `StealthTransferred(fromCommitment, toCommitment, changeCommitment, token, amount)` — 无钱包地址
- `Withdrawn(commitment, token, amount)` — 事件无地址；BNB 内部交易 / BEP20 `Transfer` 仍会显示收款地址

不要向合约直接转 BNB（`receive` 会拒绝），必须走 `deposit`。

---

## 6. 常见错误

| 错误 | 原因与处理 |
|------|------------|
| `UnsupportedChain` | 当前网络不是 BSC 56/97 |
| `ZeroAmount` | 存款或到账金额为 0 |
| `InvalidSecret` | `secret` 或 `owner` 为空，或签名者不匹配 |
| `InvalidCommitment` | 承诺为 0 |
| `CommitmentTaken` | 该承诺已有余额或已花费，必须换新的 secret |
| `NoteNotFound` | 承诺下没有资金，或 secret/钱包不匹配 |
| `InsufficientNote` | 划转金额大于票据余额 |
| `ChangeRequired` | 部分划转时未提供找零承诺 |
| `ChangeNotAllowed` | 全额划转时找零承诺必须为 `0x00…00` |
| `DuplicateCommitment` | 新旧承诺重复 |
| `FeeTooHigh` | 代付费大于票据余额 |
| `SignatureExpired` | `deadline` 已过 |
| `TokenTransferFailed` | 未 approve、余额不足或代币拒绝转账 |

---

## 7. 安全注意

1. **`secret` 等同私钥。** 谁持有 `secret` 且能用绑定钱包（或对应签名），谁就能划走资金。用 `ethers.randomBytes(32)` 生成，离线备份。
2. **承诺必须绑定将要调用 `withdraw` / `stealthTransfer` 的那个地址。** 绑错地址，资金无法提取。
3. **每个 `commitment` 只能用一次。** 花费后 `spent` 为 true，不能再存入同一承诺。
4. **扣费代币**（部分 BSC 代币转账会扣税）：合约按实际到账金额记账，不是按你传入的 `amount`。
5. **先 approve 再 `depositToken`。** `approve` 本身会在代币合约上暴露你的地址，这是 BEP20 机制决定的。
6. **不要把 `secret` 发到公开频道、不要写进合约、不要当 commitment 发给对方。** 只传 `commitment`。
7. 合约无 owner，无法暂停、无法代提、无法升级。

---

## 8. 最小 ABI（隐匿转账）

```json
[
  "function computeCommitment(bytes32 secret, address owner) view returns (bytes32)",
  "function noteOf(bytes32 commitment) view returns (address token, uint256 amount)",
  "function spent(bytes32 commitment) view returns (bool)",
  "function deposit(bytes32 commitment) payable",
  "function depositToken(address token, uint256 amount, bytes32 commitment)",
  "function stealthTransfer(bytes32 secret, bytes32 toCommitment, uint256 amount, bytes32 changeCommitment)",
  "function withdraw(bytes32 secret, address recipient)",
  "function withdrawWithSig(bytes32 secret, address owner, address recipient, uint256 relayerFee, address relayer, uint256 deadline, uint8 v, bytes32 r, bytes32 s)",
  "event Deposited(bytes32 indexed commitment, address indexed token, uint256 amount)",
  "event StealthTransferred(bytes32 indexed fromCommitment, bytes32 indexed toCommitment, bytes32 changeCommitment, address token, uint256 amount)",
  "event Withdrawn(bytes32 indexed commitment, address indexed token, uint256 amount)"
]
```

---

## 9. 旧的逐笔 Note 工厂

原来的 `CREATE2 Note` 工厂已经换成第 0 节的零知识池。不要再部署「每个承诺一个合约」的版本，也不要再用 `keccak256(secret, 地址)` 计算承诺。
