// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {ServiceManager} from "../src/ServiceManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {AVSDirectory} from "eigenlayer-contracts/core/AVSDirectory.sol";
import {ISignatureUtils} from "eigenlayer-contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "lib/eigenlayer-middleware/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DeployServiceManager is Script, StdCheats {
    // set up, deploy, register

    // Eigen Core Contracts Mainnet
    address internal constant AVS_DIRECTORY = 0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF;
    address internal constant DELEGATION_MANAGER = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;
    address internal constant STRATEGY_MANAGER = 0x858646372CC42E1A627fcE94aa7A7033e7CF075A;

    // TODO: research more
    IERC20 constant WSTETH_TOKEN = IERC20(0x7F39C581F595B53c5CBbb5b4eaeC7062C09d04f0); // wstETH token
    IStrategy constant WSTETH_STRAT = IStrategy(0x28c42De479E57cc0c90B8A3EcEb406dc173aD7cC); // wstETH strategy

    uint256 internal constant FAUCET_AMOUNT = 0.1 ether; // 0.1 wstETH

    address internal deployer;
    address internal operator;
    ServiceManager serviceManager;

    // setup
    function setUp() public {
        // test vm.rememberKey
        deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        operator = vm.rememberKey(vm.envUint("OPERATOR_PRIVATE_KEY"));

        // give the operator some stETH while running on a local fork
        if (block.chainid == 31337) {
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
