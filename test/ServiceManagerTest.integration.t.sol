// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {ServiceManager} from "../src/ServiceManager.sol";

// Core EigenLayer contracts & interfaces
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager, IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {IERC20} from "eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";

contract ServiceManagerIntegrationTest is Test {
    uint256 constant FAUCET_AMOUNT = 1 ether;
    address constant AVS_DIRECTORY = 0x055733000064333CaDDbC92763c58BF0192fFeBf; // Holesky AVSDirectory
    address constant DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7; // Holesky DelegationManager
    address constant STRATEGY_MANAGER = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6; // Holesky StrategyManager
    IERC20 constant STETH_TOKEN = IERC20(0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034);
    IStrategy constant STETH_STRAT = IStrategy(0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3);
    address constant STETH_WHALE = 0xbf2a35956c1FE31139FbE625b576Cd0A5e3DB05A;

    ServiceManager serviceManager;

    address OPERATOR = makeAddr("operator");

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
