// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PrivacyPolicy
 * @notice BNB Smart Chain（BSC / 币安智能链）DApp / 代币项目「隐私协议」链上模板。
 * @dev    部署前请替换构造参数中的项目名称、运营主体、联系邮箱、官网与完整协议 URI。
 *         本文件仅提供模板，不构成法律意见。上线前请由专业律师审阅。
 *
 * 网络：BNB Smart Chain 主网 chainId = 56，测试网 chainId = 97
 * 编译：solc 0.8.20+，Optimizer 建议开启（runs = 200）
 * 验证：部署后请在 https://bscscan.com 开源*验证，便于用户查阅本协议全文。
 *
 * =============================================================================
 * 隐私协议全文模板（部署后随源码在区块浏览器公开）
 * =============================================================================
 *
 * 【项目名称】隐私协议
 * 生效日期：[YYYY-MM-DD]
 * 适用网络：BNB Smart Chain（BSC，Chain ID 56）
 *
 * 一、引言与适用范围
 * 1.1 欢迎使用【项目名称】（下称「本项目」「我们」）。本隐私协议说明我们在您访问网站、
 *     DApp、智能合约或使用相关服务时，如何收集、使用、存储、共享与保护与您相关的信息。
 * 1.2 本协议适用于：官方网站、Web/移动 DApp、部署在 BNB Smart Chain 上的智能合约、
 *     以及我们官方公布的社交媒体与客户支持渠道。
 * 1.3 您连接钱包、发起交易、调用合约或继续使用服务，即表示您已阅读并同意本协议。
 *     如不同意，请立即停止使用。
 *
 * 二、我们收集的信息
 * 2.1 链上公开信息（区块链固有公开）
 *     a) 钱包地址（公开密钥对应的账户标识）；
 *     b) 交易哈希、区块高度、时间戳、Gas、Nonce；
 *     c) 代币余额、授权额度（allowance）、合约调用数据（calldata）；
 *     d) 与本项目合约交互产生的事件日志（Event Logs）。
 *     上述数据一经上链即向全网公开，任何人均可通过 BscScan 等浏览器查询，我们无法删除或匿名化。
 * 2.2 您主动提供的信息
 *     当您联系客服、填写表单、申请白名单或订阅通知时，可能提供电子邮箱、Telegram / Discord
 *     账号、国家或地区等。请勿向我们发送种子短语、私钥或验证码。
 * 2.3 自动收集的技术信息（通过网站 / DApp 前端）
 *     IP 地址、浏览器类型与版本、设备类型、操作系统、语言、访问时间、来源页面、
 *     钱包类型（如 MetaMask、Trust Wallet、Binance Wallet）、以及 Cookie / 本地存储中的偏好设置。
 * 2.4 我们不会、也不应当收集：助记词、私钥、钱包密码、短信/邮箱验证码、银行卡或支付密码。
 *
 * 三、信息使用目的
 * 我们仅在以下目的范围内使用信息：
 * 3.1 提供、维护与改进本项目服务（合约交互、界面展示、交易状态查询）；
 * 3.2 保障安全：识别异常交易、女巫攻击、机器人滥用、欺诈与未授权访问；
 * 3.3 履行法律与合规义务（如适用的反洗钱、制裁名单筛查）；
 * 3.4 与您沟通：发送服务通知、安全警报、协议更新（若您留下联系方式）；
 * 3.5 统计与分析：以汇总、去标识化方式了解功能使用情况，优化产品；
 * 3.6 处理争议、执行本协议及保护我们与用户的合法权益。
 *
 * 四、区块链公开性与不可撤销性（请务必阅读）
 * 4.1 BNB Smart Chain 是公开账本。钱包地址、交易金额、合约调用内容默认对任何人可见。
 * 4.2 链上数据具有不可篡改、不可删除的特性。您无法要求我们或验证者「删除」已经上链的记录。
 * 4.3 钱包地址具有假名性，但可能通过链上分析、交易所 KYC、社交暴露等方式与真实身份关联。
 * 4.4 向合约转入资产、授权代币或签名消息前，请自行评估公开性与风险。
 *
 * 五、信息共享与第三方
 * 5.1 我们不会出售您的个人信息。
 * 5.2 为实现服务，信息可能被以下类别的第三方处理或由其独立收集：
 *     a) 区块链基础设施：RPC 节点、验证者、索引服务（如 The Graph）、区块浏览器（BscScan）；
 *     b) 去中心化协议：PancakeSwap 等 DEX、跨链桥、预言机（其自身协议与隐私政策独立适用）；
 *     c) 钱包与浏览器插件：由对应钱包服务商按其政策处理；
 *     d) 云服务、CDN、分析与客服工具（如使用）；
 *     e) 专业顾问（律师、审计）及依法有权要求披露的监管或司法机关。
 * 5.3 第三方有独立的隐私政策，请在使用前自行查阅。我们不对第三方独立收集的数据负责。
 *
 * 六、Cookie 与本地存储
 * 6.1 网站 / DApp 可能使用 Cookie、localStorage 或 sessionStorage 保存语言、主题、
 *     已连接钱包偏好、公告已读状态等。
 * 6.2 您可在浏览器中拒绝或清除 Cookie，但这可能影响部分功能（如保持钱包连接状态）。
 *
 * 七、数据存储、期限与跨境
 * 7.1 链上数据永久存储于 BNB Smart Chain 全球节点。
 * 7.2 链下数据（客服邮件、表单、日志）仅在实现本协议目的所必需的期限内保留，到期后删除或匿名化，
 *     法律法规要求更长期限的除外。
 * 7.3 因区块链与云服务的分布式特性，数据可能在您所在司法辖区以外处理。使用本服务即理解该等传输。
 *
 * 八、安全措施
 * 8.1 我们采取合理的技术与管理措施（访问控制、最小权限、传输加密、合约审计等）保护链下数据。
 * 8.2 互联网与区块链传输无法保证绝对安全。请妥善保管私钥与助记词，开启钱包硬件或多重签名（如适用）。
 * 8.3 任何声称「官方客服」索要私钥、助记词或要求您向陌生地址转账的行为，均为欺诈。
 *
 * 九、您的权利
 * 在适用法律允许的范围内，您可以：
 * 9.1 查阅、更正您向我们提供的链下个人信息；
 * 9.2 撤回对链下数据处理的同意（不影响撤回前基于同意的处理）；
 * 9.3 要求删除链下个人数据（法律另有规定或存在合法保留理由的除外）；
 * 9.4 通过断开钱包、停用 DApp 访问停止向我们提供新的前端技术信息。
 * 9.5 限制：已经写入 BNB Smart Chain 的交易与事件无法删除、修改或「被遗忘」。
 * 行使权利请联系文末邮箱。为防止冒用，我们可能要求您证明对相关钱包或联系方式的控制权。
 *
 * 十、儿童隐私
 * 本服务面向年满 18 周岁（或您所在地法定成年年龄）的用户。我们不会故意收集儿童的个人信息。
 * 如发现误收集，将尽快删除链下相关数据。
 *
 * 十一、协议更新
 * 11.1 我们可通过本合约的 `updatePolicy` 发布新版本，并更新版本号、内容哈希与文档 URI。
 * 11.2 更新后继续使用服务，视为接受新版本。重大变更将通过官网、DApp 公告或链上事件提示。
 * 11.3 历史版本的内容哈希与 URI 可在链上事件中查询。
 *
 * 十二、免责声明
 * 12.1 智能合约按「现状」提供。请自行审计或阅读已验证源码后再交互。
 * 12.2 代币价格波动、无常损失、授权被盗、钓鱼网站、RPC 劫持、私钥泄露等风险由您自行承担。
 * 12.3 本协议不构成投资、法律或税务建议。
 *
 * 十三、适用法律与争议
 * 本协议的解释与争议解决适用【运营主体所在地】法律（强制性规定除外）。
 * 因本协议引起的争议，双方应先行友好协商；协商不成的，提交【约定仲裁机构 / 有管辖权的法院】。
 *
 * 十四、联系我们
 * 运营主体：【运营主体名称】
 * 电子邮箱：【contact@example.com】
 * 官方网站：【https://example.com】
 * 合约网络：BNB Smart Chain（Chain ID 56）
 *
 * =============================================================================
 */

contract PrivacyPolicy {
    // -------------------------------------------------------------------------
    // 错误
    // -------------------------------------------------------------------------
    error NotOwner();
    error ZeroAddress();
    error EmptyField();
    error UnsupportedChain();
    error UnchangedVersion();
    error AlreadyAccepted();

    // -------------------------------------------------------------------------
    // 事件
    // -------------------------------------------------------------------------
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PolicyUpdated(
        uint256 indexed version,
        bytes32 indexed contentHash,
        string documentURI,
        uint64 effectiveAt
    );
    event PolicyAccepted(address indexed user, uint256 indexed version, uint64 acceptedAt);

    // -------------------------------------------------------------------------
    // 状态
    // -------------------------------------------------------------------------
    address public owner;

    /// @notice 项目名称
    string public projectName;
    /// @notice 运营主体
    string public operatorName;
    /// @notice 联系邮箱
    string public contactEmail;
    /// @notice 官方网站
    string public website;

    /// @notice 当前协议版本（从 1 起）
    uint256 public version;
    /// @notice 完整协议文本的 keccak256 哈希，用于完整性校验
    bytes32 public contentHash;
    /// @notice 完整协议文档地址（IPFS cid 或 HTTPS）
    string public documentURI;
    /// @notice 当前版本生效时间（unix 秒）
    uint64 public effectiveAt;

    /// @notice 用户已接受的协议版本；0 表示尚未接受
    mapping(address => uint256) public acceptedVersion;
    /// @notice 用户接受时间
    mapping(address => uint64) public acceptedAt;

    // -------------------------------------------------------------------------
    // 修饰器
    // -------------------------------------------------------------------------
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // -------------------------------------------------------------------------
    // 构造
    // -------------------------------------------------------------------------
    /**
     * @param _projectName  项目名称，例如 "Example Token"
     * @param _operatorName 运营主体法定名称
     * @param _contactEmail 隐私事务联系邮箱
     * @param _website      官方网站，含 https://
     * @param _contentHash  完整协议正文的 keccak256（可对 UTF-8 文本取哈希）
     * @param _documentURI  完整协议托管地址，推荐 ipfs://<CID> 或 https://...
     */
    constructor(
        string memory _projectName,
        string memory _operatorName,
        string memory _contactEmail,
        string memory _website,
        bytes32 _contentHash,
        string memory _documentURI
    ) {
        if (block.chainid != 56 && block.chainid != 97) revert UnsupportedChain();
        if (bytes(_projectName).length == 0) revert EmptyField();
        if (bytes(_operatorName).length == 0) revert EmptyField();
        if (bytes(_contactEmail).length == 0) revert EmptyField();
        if (_contentHash == bytes32(0)) revert EmptyField();
        if (bytes(_documentURI).length == 0) revert EmptyField();

        owner = msg.sender;
        projectName = _projectName;
        operatorName = _operatorName;
        contactEmail = _contactEmail;
        website = _website;
        version = 1;
        contentHash = _contentHash;
        documentURI = _documentURI;
        effectiveAt = uint64(block.timestamp);

        emit OwnershipTransferred(address(0), msg.sender);
        emit PolicyUpdated(1, _contentHash, _documentURI, uint64(block.timestamp));
    }

    // -------------------------------------------------------------------------
    // 查询：身份与元数据
    // -------------------------------------------------------------------------
    function chainId() external view returns (uint256) {
        return block.chainid;
    }

    function networkName() external view returns (string memory) {
        if (block.chainid == 56) return "BNB Smart Chain Mainnet";
        if (block.chainid == 97) return "BNB Smart Chain Testnet";
        return "Unknown";
    }

    /**
     * @notice 当前协议元数据，便于前端一次读取。
     */
    function currentPolicy()
        external
        view
        returns (
            uint256 currentVersion,
            bytes32 hash,
            string memory uri,
            uint64 effective,
            string memory project,
            string memory operator,
            string memory email,
            string memory site
        )
    {
        return (
            version,
            contentHash,
            documentURI,
            effectiveAt,
            projectName,
            operatorName,
            contactEmail,
            website
        );
    }

    /**
     * @notice 校验一段明文是否与当前链上哈希一致。
     */
    function verifyContent(bytes calldata plaintext) external view returns (bool) {
        return keccak256(plaintext) == contentHash;
    }

    /**
     * @notice 用户是否已接受「当前」版本。
     */
    function hasAccepted(address user) public view returns (bool) {
        return acceptedVersion[user] == version && version != 0;
    }

    // -------------------------------------------------------------------------
    // 查询：条款摘要（前端可直接展示，完整正文以 documentURI / 源码注释为准）
    // -------------------------------------------------------------------------
    function sectionCount() external pure returns (uint256) {
        return 14;
    }

    function sectionTitle(uint256 id) public pure returns (string memory) {
        if (id == 1) return unicode"一、引言与适用范围";
        if (id == 2) return unicode"二、我们收集的信息";
        if (id == 3) return unicode"三、信息使用目的";
        if (id == 4) return unicode"四、区块链公开性与不可撤销性";
        if (id == 5) return unicode"五、信息共享与第三方";
        if (id == 6) return unicode"六、Cookie 与本地存储";
        if (id == 7) return unicode"七、数据存储、期限与跨境";
        if (id == 8) return unicode"八、安全措施";
        if (id == 9) return unicode"九、您的权利";
        if (id == 10) return unicode"十、儿童隐私";
        if (id == 11) return unicode"十一、协议更新";
        if (id == 12) return unicode"十二、免责声明";
        if (id == 13) return unicode"十三、适用法律与争议";
        if (id == 14) return unicode"十四、联系我们";
        return "";
    }

    function sectionBody(uint256 id) public pure returns (string memory) {
        if (id == 1) {
            return unicode"本协议说明项目在您访问网站、DApp、智能合约或使用服务时如何处理相关信息。"
                unicode"适用于官方网站、Web/移动 DApp、BNB Smart Chain 上的智能合约及官方支持渠道。"
                unicode"连接钱包、发起交易或继续使用即表示您已阅读并同意本协议。";
        }
        if (id == 2) {
            return unicode"我们可能处理：钱包地址、交易哈希、区块数据、余额与授权、合约事件等链上公开信息；"
                unicode"您主动提供的邮箱或社交账号；以及 DApp 前端自动收集的 IP、设备、浏览器与 Cookie。"
                unicode"我们不会收集助记词、私钥、钱包密码或验证码。链上数据一经写入即公开且无法删除。";
        }
        if (id == 3) {
            return unicode"信息用于：提供与改进服务、安全风控、法律合规、必要沟通、汇总统计分析及争议处理。"
                unicode"我们不会出售个人信息。";
        }
        if (id == 4) {
            return unicode"BNB Smart Chain 为公开账本。地址、金额与调用数据默认可见，且不可篡改、不可删除。"
                unicode"钱包地址具有假名性，仍可能与真实身份关联。交互前请自行评估公开性风险。";
        }
        if (id == 5) {
            return unicode"为实现服务，数据可能由 RPC 节点、验证者、BscScan、索引服务、DEX、跨链桥、预言机、"
                unicode"钱包厂商、云服务及依法有权机关处理。第三方适用其自身隐私政策。";
        }
        if (id == 6) {
            return unicode"网站/DApp 可能使用 Cookie 或本地存储保存语言、主题、钱包偏好等。"
                unicode"您可在浏览器中拒绝或清除，部分功能可能因此不可用。";
        }
        if (id == 7) {
            return unicode"链上数据由全球节点永久保存。链下数据仅在目的所需期限内保留，法律法规另有要求除外。"
                unicode"因分布式基础设施，数据可能跨境处理。";
        }
        if (id == 8) {
            return unicode"我们采取合理的访问控制、加密与合约审计等措施。互联网与区块链无法保证绝对安全。"
                unicode"请自行保管私钥。任何索要助记词或私钥的行为均为欺诈。";
        }
        if (id == 9) {
            return unicode"在适用法律下，您可查阅、更正、删除链下个人信息或撤回同意。"
                unicode"已写入 BNB Smart Chain 的记录无法删除或被遗忘。行使权利请联系运营方邮箱。";
        }
        if (id == 10) {
            return unicode"本服务面向年满 18 周岁（或当地法定成年年龄）的用户。我们不会故意收集儿童个人信息。";
        }
        if (id == 11) {
            return unicode"运营方可通过本合约发布新版本并更新哈希与文档 URI。"
                unicode"更新后继续使用视为接受新版本。重大变更将通过官网、DApp 或链上事件提示。";
        }
        if (id == 12) {
            return unicode"智能合约按现状提供。代币波动、授权盗用、钓鱼、RPC 劫持与私钥泄露等风险由用户自行承担。"
                unicode"本协议不构成投资、法律或税务建议。";
        }
        if (id == 13) {
            return unicode"本协议适用运营主体所在地法律（强制性规定除外）。争议应先行协商，协商不成按约定机构解决。";
        }
        if (id == 14) {
            return unicode"请以合约中 operatorName、contactEmail、website 字段为准联系我们。"
                unicode"网络：BNB Smart Chain（主网 Chain ID 56）。";
        }
        return "";
    }

    function getSection(uint256 id) external pure returns (string memory title, string memory body) {
        title = sectionTitle(id);
        body = sectionBody(id);
    }

    // -------------------------------------------------------------------------
    // 用户确认
    // -------------------------------------------------------------------------
    /**
     * @notice 对当前版本隐私协议表示同意。建议 DApp 在首次连接钱包后调用。
     */
    function accept() external {
        if (acceptedVersion[msg.sender] == version) revert AlreadyAccepted();
        acceptedVersion[msg.sender] = version;
        acceptedAt[msg.sender] = uint64(block.timestamp);
        emit PolicyAccepted(msg.sender, version, uint64(block.timestamp));
    }

    // -------------------------------------------------------------------------
    // 管理
    // -------------------------------------------------------------------------
    function updateIdentity(
        string calldata _projectName,
        string calldata _operatorName,
        string calldata _contactEmail,
        string calldata _website
    ) external onlyOwner {
        if (bytes(_projectName).length == 0) revert EmptyField();
        if (bytes(_operatorName).length == 0) revert EmptyField();
        if (bytes(_contactEmail).length == 0) revert EmptyField();
        projectName = _projectName;
        operatorName = _operatorName;
        contactEmail = _contactEmail;
        website = _website;
    }

    /**
     * @notice 发布新版协议。version 必须严格递增。
     * @param newVersion   新版本号，须大于当前 version
     * @param newHash      新正文 keccak256
     * @param newURI       新文档 URI
     */
    function updatePolicy(
        uint256 newVersion,
        bytes32 newHash,
        string calldata newURI
    ) external onlyOwner {
        if (newVersion <= version) revert UnchangedVersion();
        if (newHash == bytes32(0)) revert EmptyField();
        if (bytes(newURI).length == 0) revert EmptyField();

        version = newVersion;
        contentHash = newHash;
        documentURI = newURI;
        effectiveAt = uint64(block.timestamp);

        emit PolicyUpdated(newVersion, newHash, newURI, uint64(block.timestamp));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address previous = owner;
        owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }

    function renounceOwnership() external onlyOwner {
        address previous = owner;
        owner = address(0);
        emit OwnershipTransferred(previous, address(0));
    }
}
