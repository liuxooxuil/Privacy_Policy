// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrivacyFactory
 * @notice BNB Smart Chain 零知识隐藏转账。同一代币的存款进入一棵 Merkle 树，
 *         花费时提交 Groth16 证明，链上不出现 secret，也看不出花的是哪一张票据。
 *
 * 使用
 * - 收款人链下生成 secret，计算
 *     commitment = Poseidon(secret, 收款人地址)
 *   只把 commitment 交给付款人。不要把 secret 交给付款人，也不要写进交易。
 * - 付款人 deposit / depositToken。calldata 里只有 commitment、金额和代币。
 * - 合约内划转 stealthTransfer 只公布新叶子和找零叶子，没有钱包地址，也没有金额。
 * - 提现 withdraw 必须把资金打给承诺里绑定的那个地址。交易发起人可以是代付者。
 * - 一笔里既要转给别人、又要找零、又要提出一部分，用 spend。
 *
 * 仍会公开的内容
 * - 存款交易的 tx.from、存款金额、代币种类
 * - 提现的收款地址、提现金额、手续费
 * - 某个金额在池子里独一无二时，外界仍可能凭金额把存入和提现对上
 * 把金额拆成池子里常见的面额，再提现，匿名集会更大。
 *
 * 每个 secret 只能花费一次。承诺绑错地址、secret 丢失、或树满后无法再存，资金都没有管理员可以找回。
 *
 * 网络：BSC 主网 56 / 测试网 97
 * 编译：solc 0.8.20，Optimizer runs = 200，EVM shanghai
 * 部署顺序：Hash2 → Hash3 → ShieldVerifier → PrivacyFactory(hash2, hash3, verifier)
 *
 * 仓库里的验证密钥是本机生成的 pot13，再加上单方 phase-2，只适合功能测试。
 * 它没有使用 Hermez 公开仪式。掌握仪式随机数的人可以伪造证明、转走池子里的资产。
 * 主网放真实资金之前，必须用公开 phase-1 和多方 phase-2 重新生成 contracts/zk/Verifier.sol。
 */

interface IHash2 {
    function hash(uint256 a, uint256 b) external pure returns (uint256);
}

interface IHash3 {
    function hash(uint256 a, uint256 b, uint256 c) external pure returns (uint256);
}

interface IShieldVerifier {
    function verifyProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[9] calldata pubSignals
    ) external view returns (bool);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract PrivacyFactory {
    error UnsupportedChain();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidCommitment();
    error CommitmentTaken();
    error AmountTooLarge();
    error InvalidProof();
    error UnknownRoot();
    error NoteSpent();
    error UnknownLeaf();
    error TreeFull();
    error InvalidAddress();
    error UnexpectedOutput();
    error InvalidRelayer();
    error Reentrancy();
    error NativeTransferFailed();
    error TokenTransferFailed();
    error DirectNativeNotAllowed();

    /// @dev 公开输入顺序必须和 circuits/shield.circom 的 public 列表一致。
    uint256 internal constant SIG_ROOT = 0;
    uint256 internal constant SIG_NULLIFIER = 1;
    uint256 internal constant SIG_NEW_LEAF = 2;
    uint256 internal constant SIG_CHANGE_LEAF = 3;
    uint256 internal constant SIG_RECIPIENT = 4;
    uint256 internal constant SIG_RELAYER = 5;
    uint256 internal constant SIG_FEE = 6;
    uint256 internal constant SIG_AMOUNT_OUT = 7;
    uint256 internal constant SIG_TOKEN = 8;

    uint256 public constant LEVELS = 16;
    uint256 public constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 public constant MAX_AMOUNT = uint256(1) << 128;
    uint32 internal constant NO_INDEX = type(uint32).max;

    IHash2 public immutable hash2;
    IHash3 public immutable hash3;
    IShieldVerifier public immutable verifier;

    uint256 public nextIndex;
    uint256 public currentRoot;
    uint256[16] public zeros;

    mapping(uint256 => bool) public validRoots;
    mapping(uint256 => bool) public nullifierSpent;
    mapping(uint256 => bool) public usedCommitments;
    mapping(uint256 => mapping(uint256 => uint256)) private _nodes;

    uint256 private _locked;

    event Deposited(
        uint256 indexed commitment,
        uint256 indexed token,
        uint256 amount,
        uint32 leafIndex,
        uint256 leaf
    );
    event StealthTransferred(
        uint256 indexed nullifier,
        uint256 indexed token,
        uint256 newLeaf,
        uint256 changeLeaf,
        uint32 newIndex,
        uint32 changeIndex
    );
    event Withdrawn(
        uint256 indexed nullifier,
        uint256 indexed token,
        address indexed recipient,
        uint256 amountOut,
        uint256 fee
    );

    modifier nonReentrant() {
        if (_locked != 0) revert Reentrancy();
        _locked = 1;
        _;
        _locked = 0;
    }

    constructor(address hash2_, address hash3_, address verifier_) {
        if (block.chainid != 56 && block.chainid != 97) revert UnsupportedChain();
        if (hash2_ == address(0) || hash3_ == address(0) || verifier_ == address(0)) revert ZeroAddress();
        hash2 = IHash2(hash2_);
        hash3 = IHash3(hash3_);
        verifier = IShieldVerifier(verifier_);

        zeros[0] = 0;
        for (uint256 i = 0; i < LEVELS - 1; i++) {
            zeros[i + 1] = hash2.hash(zeros[i], zeros[i]);
        }
    }

    receive() external payable {
        revert DirectNativeNotAllowed();
    }

    // ---------------------------------------------------------------------
    // 查询
    // ---------------------------------------------------------------------

    /// @notice 存款写入树里的叶子。commitment = Poseidon(secret, owner)，由链下计算。
    function computeLeaf(uint256 commitment, uint256 amount, uint256 token) external view returns (uint256) {
        return hash3.hash(commitment, amount, token);
    }

    /// @notice 当前根，以及这张叶子在当前树里的兄弟路径。leafIndex 来自存款或划转事件。
    function proofOf(uint256 leafIndex)
        external
        view
        returns (uint256 root, uint256[16] memory siblings, uint256[16] memory indices)
    {
        if (leafIndex >= nextIndex) revert UnknownLeaf();
        root = currentRoot;
        uint256 idx = leafIndex;
        for (uint256 level = 0; level < LEVELS; level++) {
            uint256 siblingIndex = idx ^ 1;
            uint256 occupied = (nextIndex + (uint256(1) << level) - 1) >> level;
            siblings[level] = siblingIndex < occupied ? _nodes[level][siblingIndex] : zeros[level];
            indices[level] = idx & 1;
            idx >>= 1;
        }
    }

    // ---------------------------------------------------------------------
    // 存款。calldata 里没有收款钱包。
    // ---------------------------------------------------------------------

    /// @notice 存入 BNB。address(0) 表示原生 BNB。
    function deposit(bytes32 commitment) external payable nonReentrant {
        _open(address(0), msg.value, uint256(commitment));
    }

    /// @notice 存入 BEP20。先 approve 本合约。扣费代币按实际到账记账。
    function depositToken(address token, uint256 amount, bytes32 commitment) external nonReentrant {
        if (token == address(0)) revert TokenTransferFailed();
        if (amount == 0) revert ZeroAmount();
        uint256 received = _pullToken(token, msg.sender, amount);
        _open(token, received, uint256(commitment));
    }

    // ---------------------------------------------------------------------
    // 花费。pubSignals 顺序：
    // root, nullifier, newLeaf, changeLeaf, recipient, relayer, fee, amountOut, token
    // ---------------------------------------------------------------------

    /// @notice 通用花费：可以同时转出新票据、留下找零、并向绑定地址提现。
    function spend(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[9] calldata pubSignals
    ) external nonReentrant {
        _execute(pA, pB, pC, pubSignals);
    }

    /// @notice 整笔提到绑定钱包。newLeaf 和 changeLeaf 必须为 0。
    function withdraw(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[9] calldata pubSignals
    ) external nonReentrant {
        if (pubSignals[SIG_NEW_LEAF] != 0 || pubSignals[SIG_CHANGE_LEAF] != 0) revert UnexpectedOutput();
        if (pubSignals[SIG_AMOUNT_OUT] == 0 && pubSignals[SIG_FEE] == 0) revert ZeroAmount();
        _execute(pA, pB, pC, pubSignals);
    }

    /// @notice 合约内划转。没有提现，必须产生一张新票据，找零叶子可为 0。
    function stealthTransfer(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[9] calldata pubSignals
    ) external nonReentrant {
        if (pubSignals[SIG_NEW_LEAF] == 0) revert UnexpectedOutput();
        if (
            pubSignals[SIG_RECIPIENT] != 0 || pubSignals[SIG_RELAYER] != 0 || pubSignals[SIG_FEE] != 0
                || pubSignals[SIG_AMOUNT_OUT] != 0
        ) {
            revert UnexpectedOutput();
        }
        _execute(pA, pB, pC, pubSignals);
    }

    // ---------------------------------------------------------------------
    // 内部
    // ---------------------------------------------------------------------

    function _open(address token, uint256 amount, uint256 commitment) private {
        if (commitment == 0 || commitment >= SNARK_SCALAR_FIELD) revert InvalidCommitment();
        if (amount == 0) revert ZeroAmount();
        if (amount >= MAX_AMOUNT) revert AmountTooLarge();
        if (usedCommitments[commitment]) revert CommitmentTaken();
        usedCommitments[commitment] = true;

        uint256 tokenId = uint256(uint160(token));
        uint256 leaf = hash3.hash(commitment, amount, tokenId);
        if (leaf == 0 || leaf >= SNARK_SCALAR_FIELD) revert InvalidCommitment();
        uint32 index = _insert(leaf);
        emit Deposited(commitment, tokenId, amount, index, leaf);
    }

    function _execute(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[9] calldata pub
    ) private {
        uint256 root = pub[SIG_ROOT];
        uint256 nullifier = pub[SIG_NULLIFIER];
        uint256 newLeaf = pub[SIG_NEW_LEAF];
        uint256 changeLeaf = pub[SIG_CHANGE_LEAF];
        uint256 fee = pub[SIG_FEE];
        uint256 amountOut = pub[SIG_AMOUNT_OUT];

        if (!validRoots[root]) revert UnknownRoot();
        if (nullifier == 0 || nullifierSpent[nullifier]) revert NoteSpent();
        if (fee >= MAX_AMOUNT || amountOut >= MAX_AMOUNT) revert AmountTooLarge();
        if (newLeaf >= SNARK_SCALAR_FIELD || changeLeaf >= SNARK_SCALAR_FIELD) revert InvalidProof();

        address recipient = _addr(pub[SIG_RECIPIENT]);
        address relayer = _addr(pub[SIG_RELAYER]);
        address token = _addr(pub[SIG_TOKEN]);
        if (amountOut + fee > 0 && recipient == address(0)) revert InvalidAddress();
        if (fee > 0 && relayer == address(0)) revert InvalidRelayer();
        if (!verifier.verifyProof(pA, pB, pC, pub)) revert InvalidProof();

        nullifierSpent[nullifier] = true;

        uint32 newIndex = NO_INDEX;
        uint32 changeIndex = NO_INDEX;
        if (newLeaf != 0) newIndex = _insert(newLeaf);
        if (changeLeaf != 0) changeIndex = _insert(changeLeaf);

        uint256 tokenId = uint256(uint160(token));
        if (newLeaf != 0 || changeLeaf != 0) {
            emit StealthTransferred(nullifier, tokenId, newLeaf, changeLeaf, newIndex, changeIndex);
        }
        if (amountOut + fee > 0) {
            emit Withdrawn(nullifier, tokenId, recipient, amountOut, fee);
            if (fee > 0) _payout(token, relayer, fee);
            if (amountOut > 0) _payout(token, recipient, amountOut);
        }
    }

    function _insert(uint256 leaf) private returns (uint32 insertedAt) {
        uint256 index = nextIndex;
        if (index >= (uint256(1) << LEVELS)) revert TreeFull();
        insertedAt = uint32(index);

        uint256 current = leaf;
        uint256 idx = index;
        for (uint256 level = 0; level < LEVELS; level++) {
            _nodes[level][idx] = current;
            uint256 left;
            uint256 right;
            if ((idx & 1) == 0) {
                left = current;
                right = zeros[level];
            } else {
                left = _nodes[level][idx - 1];
                right = current;
            }
            current = hash2.hash(left, right);
            idx >>= 1;
        }

        nextIndex = index + 1;
        currentRoot = current;
        validRoots[current] = true;
    }

    function _addr(uint256 value) private pure returns (address) {
        if (value >= (uint256(1) << 160)) revert InvalidAddress();
        return address(uint160(value));
    }

    function _payout(address token, address to, uint256 amount) private {
        if (token == address(0)) {
            (bool nativeOk, ) = to.call{value: amount}("");
            if (!nativeOk) revert NativeTransferFailed();
            return;
        }
        uint256 beforeBal = IERC20(token).balanceOf(address(this));
        (bool tokenOk, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!tokenOk || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed();
        if (beforeBal - IERC20(token).balanceOf(address(this)) != amount) revert TokenTransferFailed();
    }

    function _pullToken(address token, address from, uint256 amount) private returns (uint256 received) {
        uint256 beforeBal = IERC20(token).balanceOf(address(this));
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed();
        received = IERC20(token).balanceOf(address(this)) - beforeBal;
        if (received == 0) revert ZeroAmount();
    }
}
