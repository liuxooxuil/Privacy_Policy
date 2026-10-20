// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrivacyTransfer
 * @notice 隐匿转账合约：存款与合约内划转不出现收款钱包地址。
 *
 * 原理
 * - 收款人链下生成 secret，计算
 *     commitment = keccak256(abi.encodePacked(secret, 收款人地址))
 *   把 commitment 发给付款人（不要把 secret 发给付款人）。
 * - 付款人调用 deposit / depositToken，calldata 里只有 commitment，没有收款地址。
 * - 合约内划转 stealthTransfer 只移动承诺，事件里没有钱包地址。
 * - 收款人用自己的钱包带着 secret 调用 withdraw。提现这一笔会暴露收款地址（资金打入钱包无法避免）。
 * - 承诺绑定收款人，密钥出现在 mempool 时也无法被他人改地址提走。
 *
 * 链上仍然可见
 * - 存款交易的 tx.from（付 gas 的账户）
 * - 存款/提现金额
 * - 提现交易的发起者与内部转账收款地址
 * 本合约隐藏的是「存款与合约内转账」中的收款地址，不是零知识证明，也不是混币器。
 * secret 会写进花费交易。要对上「看不出花的是哪张票据」，用 contracts/PrivacyFactory.sol。
 *
 * 前端计算承诺（ethers v6）：
 *   const secret = ethers.hexlify(ethers.randomBytes(32));
 *   const commitment = ethers.solidityPackedKeccak256(
 *     ["bytes32", "address"],
 *     [secret, recipientAddress]
 *   );
 *
 * 网络：以太坊主网 1 / Sepolia 11155111，以及 BSC 主网 56 / 测试网 97
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract PrivacyTransfer {
    error UnsupportedChain();
    error ZeroAmount();
    error InvalidSecret();
    error InvalidCommitment();
    error CommitmentTaken();
    error NoteNotFound();
    error InsufficientNote();
    error ChangeRequired();
    error ChangeNotAllowed();
    error DuplicateCommitment();
    error InvalidRecipient();
    error InvalidRelayer();
    error FeeTooHigh();
    error SignatureExpired();
    error Reentrancy();
    error NativeTransferFailed();
    error TokenTransferFailed();
    error DirectNativeNotAllowed();

    struct Note {
        address token;
        uint256 amount;
    }

    uint256 private _locked;

    mapping(bytes32 => Note) private _notes;
    mapping(bytes32 => bool) public spent;

    event Deposited(bytes32 indexed commitment, address indexed token, uint256 amount);
    event StealthTransferred(
        bytes32 indexed fromCommitment,
        bytes32 indexed toCommitment,
        bytes32 changeCommitment,
        address token,
        uint256 amount
    );
    event Withdrawn(bytes32 indexed commitment, address indexed token, uint256 amount);

    modifier nonReentrant() {
        if (_locked != 0) revert Reentrancy();
        _locked = 1;
        _;
        _locked = 0;
    }

    constructor() {
        uint256 id = block.chainid;
        if (id != 1 && id != 11155111 && id != 56 && id != 97) revert UnsupportedChain();
    }

    receive() external payable {
        revert DirectNativeNotAllowed();
    }

    // 查询
    function computeCommitment(bytes32 secret, address owner) public pure returns (bytes32) {
        if (secret == bytes32(0) || owner == address(0)) revert InvalidSecret();
        return keccak256(abi.encodePacked(secret, owner));
    }

    function noteOf(bytes32 commitment) external view returns (address token, uint256 amount) {
        Note storage note = _notes[commitment];
        return (note.token, note.amount);
    }

    // 存款交易 calldata 只有 commitment，没有收款地址
    /// @notice 存入原生币，记到承诺名下。address(0) 表示 ETH 或 BNB。
    function deposit(bytes32 commitment) external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        _createNote(commitment, address(0), msg.value);
        emit Deposited(commitment, address(0), msg.value);
    }

    /// @notice 存入 BEP20。调用前需 approve 本合约。兼容扣费代币（按实际到账记账）。
    function depositToken(address token, uint256 amount, bytes32 commitment) external nonReentrant {
        if (token == address(0)) revert TokenTransferFailed();
        if (amount == 0) revert ZeroAmount();

        uint256 received = _pullToken(token, msg.sender, amount);
        _createNote(commitment, token, received);
        emit Deposited(commitment, token, received);
    }

    // 合约内划转只移动承诺事件不含钱包地址
    /**
     * @notice 将一张票据的部分或全部金额划到新的承诺（收款人预先给出的 commitment）。
     * @param secret            当前票据的密钥
     * @param toCommitment      收款承诺（不得已花费、不得已占用）
     * @param amount            划转金额
     * @param changeCommitment  找零承诺；全额划转时必须为 0
     */
    function stealthTransfer(
        bytes32 secret,
        bytes32 toCommitment,
        uint256 amount,
        bytes32 changeCommitment
    ) external nonReentrant {
        bytes32 fromCommitment = computeCommitment(secret, msg.sender);
        Note memory note = _consume(fromCommitment);

        if (amount == 0 || amount > note.amount) revert InsufficientNote();
        _assertFresh(toCommitment);
        if (toCommitment == fromCommitment) revert DuplicateCommitment();

        uint256 change = note.amount - amount;
        if (change == 0) {
            if (changeCommitment != bytes32(0)) revert ChangeNotAllowed();
        } else {
            if (changeCommitment == bytes32(0)) revert ChangeRequired();
            if (changeCommitment == toCommitment || changeCommitment == fromCommitment) {
                revert DuplicateCommitment();
            }
            _assertFresh(changeCommitment);
            _notes[changeCommitment] = Note({token: note.token, amount: change});
        }

        _notes[toCommitment] = Note({token: note.token, amount: amount});
        emit StealthTransferred(fromCommitment, toCommitment, changeCommitment, note.token, amount);
    }

    // 提现资金离开合约时才会出现收款地址
    /**
     * @notice 票据所有人自行提现。承诺必须等于 keccak256(secret, msg.sender)。
     * @param secret    票据密钥
     * @param recipient 收款钱包，填 address(0) 则打给 msg.sender
     */
    function withdraw(bytes32 secret, address payable recipient) external nonReentrant {
        _withdraw(secret, msg.sender, recipient, 0, payable(address(0)));
    }

    /**
     * @notice 代付 gas 提现。签名人必须是承诺绑定的所有人。
     *         签名消息：keccak256(secret, recipient, relayerFee, relayer, deadline, this, chainid)
     *         再包一层 Ethereum Signed Message。
     */
    function withdrawWithSig(
        bytes32 secret,
        address owner,
        address payable recipient,
        uint256 relayerFee,
        address payable relayer,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        if (owner == address(0)) revert InvalidSecret();
        if (block.timestamp > deadline) revert SignatureExpired();
        if (relayerFee > 0 && relayer == address(0)) revert InvalidRelayer();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(secret, recipient, relayerFee, relayer, deadline, address(this), block.chainid)
                )
            )
        );
        if (ecrecover(digest, v, r, s) != owner) revert InvalidSecret();

        _withdraw(secret, owner, recipient, relayerFee, relayer);
    }

    // 内部
    function _withdraw(
        bytes32 secret,
        address owner,
        address payable recipient,
        uint256 relayerFee,
        address payable relayer
    ) private {
        bytes32 commitment = computeCommitment(secret, owner);
        Note memory note = _consume(commitment);

        if (recipient == address(0)) {
            recipient = payable(owner);
        }
        if (relayerFee > note.amount) revert FeeTooHigh();

        uint256 payout = note.amount - relayerFee;
        emit Withdrawn(commitment, note.token, note.amount);

        if (relayerFee > 0) {
            _payout(note.token, relayer, relayerFee);
        }
        if (payout > 0) {
            _payout(note.token, recipient, payout);
        }
    }

    function _createNote(bytes32 commitment, address token, uint256 amount) private {
        if (commitment == bytes32(0)) revert InvalidCommitment();
        _assertFresh(commitment);
        _notes[commitment] = Note({token: token, amount: amount});
    }

    function _assertFresh(bytes32 commitment) private view {
        if (commitment == bytes32(0)) revert InvalidCommitment();
        if (spent[commitment] || _notes[commitment].amount != 0) revert CommitmentTaken();
    }

    function _consume(bytes32 commitment) private returns (Note memory note) {
        note = _notes[commitment];
        if (note.amount == 0) revert NoteNotFound();
        spent[commitment] = true;
        delete _notes[commitment];
    }

    function _payout(address token, address to, uint256 amount) private {
        if (token == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            if (!ok) revert NativeTransferFailed();
        } else {
            _pushToken(token, to, amount);
        }
    }

    function _pullToken(address token, address from, uint256 amount) private returns (uint256 received) {
        uint256 beforeBal = IERC20(token).balanceOf(address(this));
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed();
        received = IERC20(token).balanceOf(address(this)) - beforeBal;
        if (received == 0) revert ZeroAmount();
    }

    function _pushToken(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TokenTransferFailed();
    }
}
