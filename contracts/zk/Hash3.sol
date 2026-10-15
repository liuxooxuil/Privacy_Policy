// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PoseidonT4.sol";

/// @notice 三输入 Poseidon。叶子是 Poseidon(commitment, amount, token)。
contract Hash3 {
    function hash(uint256 a, uint256 b, uint256 c) external pure returns (uint256) {
        return PoseidonT4.hash([a, b, c]);
    }
}
