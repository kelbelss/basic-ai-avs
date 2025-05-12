// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {ISignatureUtilsMixinTypes} from
    "../../../lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

/// @dev Only implements the subset of IAVSDirectory that ServiceManager uses.
interface IAVSDirectory {
    /// @notice Register an operator to this AVS
    /// @param operator the operator address
    /// @param operatorSignature signature + salt + expiry as per core contract
    function registerOperatorToAVS(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry calldata operatorSignature
    ) external;

    /// @notice Deregister an operator from this AVS
    /// @param operator the operator address
    function deregisterOperatorFromAVS(address operator) external;
}

/// @dev A tiny mock that just flips a boolean
contract MockAVSDirectory is IAVSDirectory {
    mapping(address => bool) public registered;

    event Registered(address indexed operator);
    event Deregistered(address indexed operator);

    function registerOperatorToAVS(address operator, ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry calldata)
        external
        override
    {
        registered[operator] = true;
        emit Registered(operator);
    }

    function deregisterOperatorFromAVS(address operator) external override {
        registered[operator] = false;
        emit Deregistered(operator);
    }
}
