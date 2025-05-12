// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/// @dev Minimal EIP-1271 verifier to use as operator in integration tests
// Issues with the EIP-1271 flow - the mixin’s first isValidSignature call now succeeds and falls back to ECDSA
contract SimpleOperator {
    // bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 constant MAGIC = 0x1626ba7e;

    /// @dev Always returns MAGIC to signal “this signature is valid”
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return MAGIC;
    }
}
