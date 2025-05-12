// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ServiceManager} from "../src/ServiceManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {AVSDirectory} from "eigenlayer-contracts/src/contracts/core/AVSDirectory.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IStrategyManager, IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/token/ERC20/IERC20.sol";

// TODO remove
import "forge-std/Test.sol";

contract DeployServiceManager is Script {
    // set up, deploy, register

    // Eigen Core Contracts Holesky
    address internal constant AVS_DIRECTORY = 0x055733000064333CaDDbC92763c58BF0192fFeBf;
    address internal constant DELEGATION_MANAGER = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address internal constant STRATEGY_MANAGER = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;

    // TODO: research more
    IERC20 constant STETH_TOKEN = IERC20(0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034); // stETH Holesky
    IStrategy constant STETH_STRAT = IStrategy(0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3); // stETH strategy

    uint256 internal constant FAUCET_AMOUNT = 1 ether; // 1 stETH
    address constant STETH_WHALE = 0xbf2a35956c1FE31139FbE625b576Cd0A5e3DB05A; // Holesky stETH holder

    address internal deployer;
    address internal operator;
    ServiceManager serviceManager;

    function setUp() public {
        // test vm.rememberKey
        deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        operator = vm.rememberKey(vm.envUint("OPERATOR_PRIVATE_KEY"));

        // give the operator some stETH while running on a local fork
        vm.startPrank(STETH_WHALE);
        STETH_TOKEN.transfer(operator, FAUCET_AMOUNT);
        vm.stopPrank();
    }

    function run() public {
        // deploy AVS - ServiceManager
        vm.startBroadcast(deployer);
        serviceManager = new ServiceManager(AVS_DIRECTORY);
        vm.stopBroadcast();

        // operator deposits stETH into the strategy - in order to delegate to himself on registration
        vm.startBroadcast(operator);
        STETH_TOKEN.approve(STRATEGY_MANAGER, FAUCET_AMOUNT);
        IStrategyManager(STRATEGY_MANAGER).depositIntoStrategy(STETH_STRAT, STETH_TOKEN, FAUCET_AMOUNT);
        vm.stopBroadcast();

        // register as an operator on EigenLayer before they can register with AVS - done through del manager, pull up live instance on chain of delegation manager
        IDelegationManager delegationManager = IDelegationManager(DELEGATION_MANAGER);

        vm.startBroadcast(operator);
        delegationManager.registerAsOperator(operator, 1, ""); // has to have a positive balance to register
        vm.stopBroadcast();

        // register operator to this AVS
        AVSDirectory avsDirectory = AVSDirectory(AVS_DIRECTORY); // pull in instance that is deployed
        // salt = concat of block.timestamp and operator
        bytes32 salt = keccak256(abi.encodePacked(block.timestamp, operator));
        uint256 expiry = block.timestamp + 1 days; // 1 day expiry

        // create hash to sign
        bytes32 operatorRegistrationDigestHash =
            avsDirectory.calculateOperatorAVSRegistrationDigestHash(operator, address(serviceManager), salt, expiry);

        // sign the hash
        (uint256 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("OPERATOR_PRIVATE_KEY"), operatorRegistrationDigestHash);

        // create signature string
        bytes memory signature = abi.encodePacked(r, s, v);

        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature =
            ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({signature: signature, salt: salt, expiry: expiry});

        vm.startBroadcast(operator);
        serviceManager.registerOperatorToAVS(operator, operatorSignature);
        vm.stopBroadcast();
    }
}
