const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  init,
  hash,
  createNote,
  toBytes32,
  proveSpend,
} = require("../sdk/privacy");

async function deploy() {
  const hash2 = await ethers.deployContract("Hash2");
  const hash3 = await ethers.deployContract("Hash3");
  const verifier = await ethers.deployContract("ShieldVerifier");
  const factory = await ethers.deployContract("PrivacyFactory", [
    await hash2.getAddress(),
    await hash3.getAddress(),
    await verifier.getAddress(),
  ]);
  return { hash2, hash3, verifier, factory };
}

function absent(address, tx, receipt) {
  const needle = address.slice(2).toLowerCase();
  expect(tx.data.toLowerCase()).to.not.include(needle);
  for (const log of receipt.logs) {
    expect(log.data.toLowerCase()).to.not.include(needle);
    for (const topic of log.topics) expect(topic.toLowerCase()).to.not.include(needle);
  }
}

describe("PrivacyFactory", function () {
  before(async function () {
    await init();
  });

  it("链上 Poseidon 与电路使用的哈希一致", async function () {
    const hash2 = await ethers.deployContract("Hash2");
    const hash3 = await ethers.deployContract("Hash3");
    const a = 3n;
    const b = 5n;
    const c = 7n;
    expect(await hash2.hash(a, b)).to.equal(hash([a, b]));
    expect(await hash3.hash(a, b, c)).to.equal(hash([a, b, c]));
  });

  it("存款不出现收款地址，提现只能进入绑定地址", async function () {
    const { factory } = await deploy();
    const [payer, bob, relayer] = await ethers.getSigners();
    const note = createNote(bob.address);
    const amount = ethers.parseEther("1");

    const tx = await factory.connect(payer).deposit(toBytes32(note.commitment), { value: amount });
    const receipt = await tx.wait();
    absent(bob.address, tx, receipt);
    expect(JSON.stringify(receipt.logs).toLowerCase()).to.not.include(note.secret.toString(16));

    const proof = await factory.proofOf(0);
    const args = await proveSpend({
      root: proof.root,
      siblings: proof.siblings,
      indices: proof.indices,
      note,
      amount,
      amountOut: amount,
    });
    const before = await ethers.provider.getBalance(bob.address);
    await factory.connect(relayer).withdraw(args.pA, args.pB, args.pC, args.pubSignals);
    expect(await ethers.provider.getBalance(bob.address)).to.equal(before + amount);
    expect(await ethers.provider.getBalance(await factory.getAddress())).to.equal(0n);

    await expect(
      factory.connect(relayer).withdraw(args.pA, args.pB, args.pC, args.pubSignals)
    ).to.be.revertedWithCustomError(factory, "NoteSpent");
  });

  it("三笔存款后，第一笔和第三笔都能按当前路径提出", async function () {
    const { factory } = await deploy();
    const signers = await ethers.getSigners();
    const amount = ethers.parseEther("0.1");
    const notes = [];
    for (let i = 0; i < 3; i++) {
      const owner = signers[i + 1];
      const note = createNote(owner.address);
      notes.push(note);
      await factory.deposit(toBytes32(note.commitment), { value: amount });
    }

    for (const index of [0, 2]) {
      const proof = await factory.proofOf(index);
      const args = await proveSpend({
        root: proof.root,
        siblings: proof.siblings,
        indices: proof.indices,
        note: notes[index],
        amount,
        amountOut: amount,
      });
      const owner = signers[index + 1];
      const before = await ethers.provider.getBalance(owner.address);
      await factory.withdraw(args.pA, args.pB, args.pC, args.pubSignals);
      expect(await ethers.provider.getBalance(owner.address)).to.equal(before + amount);
    }
  });

  it("合约内划转不出现新收款地址，新旧票据都能再提出", async function () {
    const { factory } = await deploy();
    const [payer, alice, carol] = await ethers.getSigners();
    const amount = ethers.parseEther("0.5");
    const note = createNote(alice.address);
    await factory.connect(payer).deposit(toBytes32(note.commitment), { value: amount });

    const carolNote = createNote(carol.address);
    const change = createNote(alice.address);
    const changeAmount = ethers.parseEther("0.2");
    change.amount = changeAmount;
    const proof = await factory.proofOf(0);
    const args = await proveSpend({
      root: proof.root,
      siblings: proof.siblings,
      indices: proof.indices,
      note,
      amount,
      toNote: carolNote,
      changeNote: change,
    });

    const tx = await factory.stealthTransfer(args.pA, args.pB, args.pC, args.pubSignals);
    const receipt = await tx.wait();
    absent(carol.address, tx, receipt);
    absent(alice.address, tx, receipt);
    expect(await ethers.provider.getBalance(await factory.getAddress())).to.equal(amount);

    const carolProof = await factory.proofOf(1);
    const carolArgs = await proveSpend({
      root: carolProof.root,
      siblings: carolProof.siblings,
      indices: carolProof.indices,
      note: carolNote,
      amount: args.sendAmount,
      amountOut: args.sendAmount,
    });
    const carolBefore = await ethers.provider.getBalance(carol.address);
    await factory.withdraw(carolArgs.pA, carolArgs.pB, carolArgs.pC, carolArgs.pubSignals);
    expect(await ethers.provider.getBalance(carol.address)).to.equal(carolBefore + args.sendAmount);

    const changeProof = await factory.proofOf(2);
    const changeArgs = await proveSpend({
      root: changeProof.root,
      siblings: changeProof.siblings,
      indices: changeProof.indices,
      note: change,
      amount: changeAmount,
      amountOut: changeAmount,
    });
    const aliceBefore = await ethers.provider.getBalance(alice.address);
    await factory.withdraw(changeArgs.pA, changeArgs.pB, changeArgs.pC, changeArgs.pubSignals);
    expect(await ethers.provider.getBalance(alice.address)).to.equal(aliceBefore + changeAmount);
  });

  it("同一笔可以提出一部分并留下找零", async function () {
    const { factory } = await deploy();
    const [, alice] = await ethers.getSigners();
    const amount = ethers.parseEther("0.4");
    const note = createNote(alice.address);
    await factory.deposit(toBytes32(note.commitment), { value: amount });
    const change = createNote(alice.address);
    const changeAmount = ethers.parseEther("0.1");
    change.amount = changeAmount;
    const proof = await factory.proofOf(0);
    const args = await proveSpend({
      root: proof.root,
      siblings: proof.siblings,
      indices: proof.indices,
      note,
      amount,
      changeNote: change,
      amountOut: amount - changeAmount,
    });
    const before = await ethers.provider.getBalance(alice.address);
    await factory.spend(args.pA, args.pB, args.pC, args.pubSignals);
    expect(await ethers.provider.getBalance(alice.address)).to.equal(before + (amount - changeAmount));

    const left = await factory.proofOf(1);
    const rest = await proveSpend({
      root: left.root,
      siblings: left.siblings,
      indices: left.indices,
      note: change,
      amount: changeAmount,
      amountOut: changeAmount,
    });
    await factory.withdraw(rest.pA, rest.pB, rest.pC, rest.pubSignals);
    expect(await ethers.provider.getBalance(await factory.getAddress())).to.equal(0n);
  });

  it("BEP20 按实际到账记账，提现把代币打给绑定地址", async function () {
    const { factory } = await deploy();
    const [payer, bob] = await ethers.getSigners();
    const token = await ethers.deployContract("MockERC20");
    await token.setFeeBps(100);
    await token.mint(payer.address, 10000n);
    await token.connect(payer).approve(await factory.getAddress(), 10000n);
    const note = createNote(bob.address);
    await factory.connect(payer).depositToken(await token.getAddress(), 10000n, toBytes32(note.commitment));
    expect(await token.balanceOf(await factory.getAddress())).to.equal(9900n);
    await token.setFeeBps(0);

    const proof = await factory.proofOf(0);
    const args = await proveSpend({
      root: proof.root,
      siblings: proof.siblings,
      indices: proof.indices,
      note,
      amount: 9900n,
      token: BigInt(await token.getAddress()),
      amountOut: 9900n,
    });
    await factory.withdraw(args.pA, args.pB, args.pC, args.pubSignals);
    expect(await token.balanceOf(bob.address)).to.equal(9900n);
  });

  it("手续费从票据里扣给代付地址", async function () {
    const { factory } = await deploy();
    const [, bob, relayer] = await ethers.getSigners();
    const amount = ethers.parseEther("1");
    const fee = ethers.parseEther("0.01");
    const note = createNote(bob.address);
    await factory.deposit(toBytes32(note.commitment), { value: amount });
    const proof = await factory.proofOf(0);
    const args = await proveSpend({
      root: proof.root,
      siblings: proof.siblings,
      indices: proof.indices,
      note,
      amount,
      amountOut: amount - fee,
      fee,
      relayer: BigInt(relayer.address),
    });
    const bobBefore = await ethers.provider.getBalance(bob.address);
    const relayerBefore = await ethers.provider.getBalance(relayer.address);
    await factory.withdraw(args.pA, args.pB, args.pC, args.pubSignals);
    expect(await ethers.provider.getBalance(bob.address)).to.equal(bobBefore + (amount - fee));
    expect(await ethers.provider.getBalance(relayer.address)).to.equal(relayerBefore + fee);
  });

  it("重复承诺、直接转账和改过的公开输入都会失败", async function () {
    const { factory } = await deploy();
    const [, bob] = await ethers.getSigners();
    const note = createNote(bob.address);
    const commitment = toBytes32(note.commitment);
    await factory.deposit(commitment, { value: 1n });
    await expect(factory.deposit(commitment, { value: 1n })).to.be.revertedWithCustomError(
      factory,
      "CommitmentTaken"
    );
    await expect(bob.sendTransaction({ to: await factory.getAddress(), value: 1n })).to.be.revertedWithCustomError(
      factory,
      "DirectNativeNotAllowed"
    );

    const proof = await factory.proofOf(0);
    const args = await proveSpend({
      root: proof.root,
      siblings: proof.siblings,
      indices: proof.indices,
      note,
      amount: 1n,
      amountOut: 1n,
    });
    args.pubSignals[7] = (1n + 10n ** 18n).toString();
    await expect(factory.withdraw(args.pA, args.pB, args.pC, args.pubSignals)).to.be.revertedWithCustomError(
      factory,
      "InvalidProof"
    );
  });
});
