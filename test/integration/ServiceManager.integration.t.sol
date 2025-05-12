// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {ServiceManager} from "../../src/ServiceManager.sol";

// Core EigenLayer contracts & interfaces
import {IntegrationBase} from "./IntegrationBase.t.sol";
import {IDelegationManager} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {
    IStrategyManager, IStrategy
} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {AVSDirectory} from "../../lib/eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {IERC20} from "../../lib/eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtilsMixinTypes} from
    "../../lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

contract ServiceManagerIntegrationTest is IntegrationBase {
    function setUp() public {
        // 1) fork Holesky
        vm.createSelectFork("holesky");

        // 2) get some stETH for your operator
        vm.startPrank(STETH_WHALE);
        STETH_TOKEN.transfer(OPERATOR, FAUCET_AMOUNT);
        vm.stopPrank();

        // 3) operator deposits into the strategy so they can register
        vm.startPrank(OPERATOR);
        STETH_TOKEN.approve(STRATEGY_MANAGER, FAUCET_AMOUNT);
        IStrategyManager(STRATEGY_MANAGER).depositIntoStrategy(STETH_STRAT, STETH_TOKEN, FAUCET_AMOUNT);
        vm.stopPrank();

        // 4) operator registers with EigenLayer
        vm.startPrank(OPERATOR);
        IDelegationManager(DELEGATION_MANAGER).registerAsOperator(OPERATOR, 1, "");
        vm.stopPrank();

        // 5) deploy AVS ServiceManager pointing at the real AVSDirectory
        serviceManager = new ServiceManager(AVS_DIRECTORY);
    }

    function testEndToEndRegistration() public {
        vm.startPrank(OPERATOR);

        // compute salt & expiry
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, OPERATOR));
        uint256 expiry = block.timestamp + 1 days;

        AVSDirectory avs = AVSDirectory(AVS_DIRECTORY);
        bytes32 digest = avs.calculateOperatorAVSRegistrationDigestHash(OPERATOR, address(serviceManager), salt, expiry);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("OPERATOR_PRIVATE_KEY"), digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory signature =
            ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({signature: sig, salt: salt, expiry: expiry});

        // call into your contract
        serviceManager.registerOperatorToAVS(OPERATOR, signature);
        vm.stopPrank();

        // assert your state change
        assertTrue(serviceManager.operatorRegistered(OPERATOR), "operator should be marked as registered");
    }
}

// give operator eth
// operator deposits stETH into the strategy - in order to delegate to himself on registration
// register operator on eigenlayer
// register operator to AVS which will also register the AVS to eigenlayer
