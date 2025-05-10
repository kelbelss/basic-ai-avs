// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ServiceManager} from "../src/ServiceManager.sol";
import {IDelegationManager} from "eigenlayer-middleware/src/contracts/interfaces/IDelegationManager.sol";
import {AVSDirectory} from "eigenlayer-middleware/src/contracts/core/AVSDirectory.sol";
import {ISignatureUtils} from "eigenlayer-middleware/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager, IStrategy} from "eigenlayer-middleware/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "lib/eigenlayer-middleware/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployServiceManager is Script, StdCheats {
    // set up, deploy, register

    // Eigen Core Contracts Mainnet
    address internal constant AVS_DIRECTORY = 0xA1585A624E8B7da1c15D16B007FA5a2A4504681D;
    address internal constant DELEGATION_MANAGER = 0x750954a384174dF80446D97eBbCaE6E1A084DE6E;
    address internal constant STRATEGY_MANAGER = 0xb305dd46bf78210b54A903238CA4e799a39687C1;

    // TODO: research more
    IERC20 constant WSTETH_TOKEN = IERC20(0x8d09a4502Cc8Cf1547aD300E066060D043f6982D); // wstETH Holesky
    IStrategy constant WSTETH_STRAT = IStrategy(0x296d39557dEE4F13155Bcb1D2C4ea243330020EA); // wstETH strategy

    uint256 internal constant FAUCET_AMOUNT = 0.1 ether; // 0.1 wstETH

    address internal deployer;
    address internal operator;
    ServiceManager serviceManager;

    // setup
    function setUp() public {
        // test vm.rememberKey
        deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        operator = vm.rememberKey(vm.envUint("OPERATOR_PRIVATE_KEY"));

        // give the operator some wstETH while running on a local fork
        if (block.chainid == 31337 || block.chainid == 17000) {
            // StdCheats.deal(token, to, amount, adjustTotalSupply?)
            deal(address(WSTETH_TOKEN), operator, FAUCET_AMOUNT, true);
        }
    }

    function run() public {
        // deploy AVS - ServiceManager
        vm.startBroadcast(deployer);
        serviceManager = new ServiceManager(AVS_DIRECTORY);
        vm.stopBroadcast();

        // operator deposits stETH into the strategy
        IStrategyManager strategyManager = IStrategyManager(STRATEGY_MANAGER);
        vm.startBroadcast(operator);
        WSTETH_TOKEN.approve(STRATEGY_MANAGER, FAUCET_AMOUNT);
        strategyManager.depositIntoStrategy(WSTETH_STRAT, WSTETH_TOKEN, FAUCET_AMOUNT);
        vm.stopBroadcast();

        // register as an operator on EigenLayer before they can register with AVS - done through del manager, pull up live instance on chain of delegation manager
        IDelegationManager delegationManager = IDelegationManager(DELEGATION_MANAGER);
        // set operator details using struct
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            __deprecated_earningsReceiver: operator, // not needed
            delegationApprover: address(0), // not needed
            stakerOptOutWindowBlocks: 0 // not needed
        });

        vm.startBroadcast(operator);
        delegationManager.registerAsOperator(operatorDetails, ""); // has to have a positive balance to register
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

        ISignatureUtils.SignatureWithSaltAndExpiry memory operatorSignature =
            ISignatureUtils.SignatureWithSaltAndExpiry({signature: signature, salt: salt, expiry: expiry});

        vm.startBroadcast(operator);
        serviceManager.registerOperatorToAVS(operator, operatorSignature);
        vm.stopBroadcast();
    }
}
