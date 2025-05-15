// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

contract MockStrategy {
    function sharesToUnderlying(uint256 shares) external pure returns (uint256) {
        return shares;
    }
}
