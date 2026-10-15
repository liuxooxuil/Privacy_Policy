// SPDX-License-Identifier: GPL-3.0-only
pragma circom 2.1.0;

// 本文件 include circomlib（GPL-3.0）。
include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/mux1.circom";

// nullifier = Poseidon(secret, 2^160)。2^160 大于任何地址，不会和 inner = Poseidon(secret, owner) 撞域。

// 证明叶子在增量 Merkle 树中。pathIndices[i] = 0 表示当前节点在左边。
template MerkleProof(levels) {
    signal input leaf;
    signal input pathElements[levels];
    signal input pathIndices[levels];
    signal output root;

    component hashers[levels];
    component mux[levels];
    signal bitsOk[levels];
    signal hashes[levels + 1];
    hashes[0] <== leaf;

    for (var i = 0; i < levels; i++) {
        // 当前 circomlib 的 MultiMux1 不检查选择位。路径位必须是 0 或 1。
        bitsOk[i] <== pathIndices[i] * (pathIndices[i] - 1);
        bitsOk[i] === 0;

        mux[i] = MultiMux1(2);
        mux[i].c[0][0] <== hashes[i];
        mux[i].c[0][1] <== pathElements[i];
        mux[i].c[1][0] <== pathElements[i];
        mux[i].c[1][1] <== hashes[i];
        mux[i].s <== pathIndices[i];

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== mux[i].out[0];
        hashers[i].inputs[1] <== mux[i].out[1];
        hashes[i + 1] <== hashers[i].out;
    }

    root <== hashes[levels];
}

// 花费一张票据。公开量只有根、nullifier、新叶子、找零叶子、提现参数和代币。
// secret、原主人、金额和树路径是私有见证，不会出现在证明的公开输入里。
//
// 金额守恒：amount = sendAmount + changeAmount + amountOut + fee
// 每个数都限制在 128 位，三者之和不会绕过域。
template Shield(levels) {
    signal input root;
    signal input nullifierHash;
    signal input newLeaf;
    signal input changeLeaf;
    signal input recipient;
    signal input relayer;
    signal input fee;
    signal input amountOut;
    signal input token;

    signal input secret;
    signal input owner;
    signal input amount;
    signal input pathElements[levels];
    signal input pathIndices[levels];
    signal input sendAmount;
    signal input changeAmount;
    signal input newCommitment;
    signal input changeCommitment;

    component secretZero = IsZero();
    secretZero.in <== secret;
    secretZero.out === 0;

    component ownerZero = IsZero();
    ownerZero.in <== owner;
    ownerZero.out === 0;

    component amountBits = Num2Bits(128);
    amountBits.in <== amount;
    component sendBits = Num2Bits(128);
    sendBits.in <== sendAmount;
    component changeBits = Num2Bits(128);
    changeBits.in <== changeAmount;
    component feeBits = Num2Bits(128);
    feeBits.in <== fee;
    component outBits = Num2Bits(128);
    outBits.in <== amountOut;

    signal publicAmount;
    publicAmount <== amountOut + fee;
    sendAmount + changeAmount + publicAmount === amount;

    component innerH = Poseidon(2);
    innerH.inputs[0] <== secret;
    innerH.inputs[1] <== owner;

    component leafH = Poseidon(3);
    leafH.inputs[0] <== innerH.out;
    leafH.inputs[1] <== amount;
    leafH.inputs[2] <== token;

    component tree = MerkleProof(levels);
    tree.leaf <== leafH.out;
    for (var i = 0; i < levels; i++) {
        tree.pathElements[i] <== pathElements[i];
        tree.pathIndices[i] <== pathIndices[i];
    }
    tree.root === root;

    // 2^160
    var NULLIFIER_DOMAIN = 1461501637330902918203684832716283019655932542976;
    component nullH = Poseidon(2);
    nullH.inputs[0] <== secret;
    nullH.inputs[1] <== NULLIFIER_DOMAIN;
    nullH.out === nullifierHash;

    component sendZero = IsZero();
    sendZero.in <== sendAmount;
    component changeZero = IsZero();
    changeZero.in <== changeAmount;
    component pubZero = IsZero();
    pubZero.in <== publicAmount;

    // 至少有一个输出：转给新承诺、找零，或提出到钱包。
    signal noShieldedOut;
    noShieldedOut <== sendZero.out * changeZero.out;
    noShieldedOut * pubZero.out === 0;

    component newH = Poseidon(3);
    newH.inputs[0] <== newCommitment;
    newH.inputs[1] <== sendAmount;
    newH.inputs[2] <== token;
    // sendAmount = 0 时 newLeaf 必须为 0；否则必须等于新票据叶子。
    newLeaf === newH.out * (1 - sendZero.out);

    component changeH = Poseidon(3);
    changeH.inputs[0] <== changeCommitment;
    changeH.inputs[1] <== changeAmount;
    changeH.inputs[2] <== token;
    changeLeaf === changeH.out * (1 - changeZero.out);

    component newCZero = IsZero();
    newCZero.in <== newCommitment;
    (1 - sendZero.out) * newCZero.out === 0;

    component changeCZero = IsZero();
    changeCZero.in <== changeCommitment;
    (1 - changeZero.out) * changeCZero.out === 0;

    // 新承诺不能复用正在花费的内部承诺。
    component newIsInner = IsEqual();
    newIsInner.in[0] <== newCommitment;
    newIsInner.in[1] <== innerH.out;
    (1 - sendZero.out) * newIsInner.out === 0;

    component changeIsInner = IsEqual();
    changeIsInner.in[0] <== changeCommitment;
    changeIsInner.in[1] <== innerH.out;
    (1 - changeZero.out) * changeIsInner.out === 0;

    component sameOutCommitment = IsEqual();
    sameOutCommitment.in[0] <== newCommitment;
    sameOutCommitment.in[1] <== changeCommitment;
    signal bothShielded;
    bothShielded <== (1 - sendZero.out) * (1 - changeZero.out);
    bothShielded * sameOutCommitment.out === 0;

    component leavesEq = IsEqual();
    leavesEq.in[0] <== newLeaf;
    leavesEq.in[1] <== changeLeaf;
    bothShielded * leavesEq.out === 0;

    // 有公开提现时，收款地址必须等于承诺里绑定的地址。没有提现时收款地址和手续费必须为 0。
    component recipZero = IsZero();
    recipZero.in <== recipient;
    component ownerMatch = IsEqual();
    ownerMatch.in[0] <== owner;
    ownerMatch.in[1] <== recipient;
    (1 - pubZero.out) * (1 - ownerMatch.out) === 0;
    (1 - pubZero.out) * recipZero.out === 0;
    pubZero.out * (1 - recipZero.out) === 0;

    component feeZero = IsZero();
    feeZero.in <== fee;
    pubZero.out * (1 - feeZero.out) === 0;

    component relayerZero = IsZero();
    relayerZero.in <== relayer;
    pubZero.out * (1 - relayerZero.out) === 0;
    (1 - feeZero.out) * relayerZero.out === 0;
}

component main {public [
    root,
    nullifierHash,
    newLeaf,
    changeLeaf,
    recipient,
    relayer,
    fee,
    amountOut,
    token
]} = Shield(16);
