// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PoseidonT3.sol";

/// @notice 两输入 Poseidon。单独部署，避免和三输入版本挤在同一个 24KB 上限里。
contract Hash2 {
    function hash(uint256 a, uint256 b) external pure returns (uint256) {
        return PoseidonT3.hash([a, b]);
    }
}
