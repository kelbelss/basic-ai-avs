// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {ServiceManager} from "../src/ServiceManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {AVSDirectory} from "eigenlayer-contracts/core/AVSDirectory.sol";
import {ISignatureUtils} from "eigenlayer-contracts/interfaces/ISignatureUtils.sol";

contract DeployServiceManager is Script {
    // set up, deploy, register

    // Eigen Core Contracts Mainnet
    address internal constant AVS_DIRECTORY = 0x135DDa560e946695d6f155dACaFC6f1F25C1F5AF;
    address internal constant DELEGATION_MANAGER = 0x39053D51B77DC0d36036Fc1fCc8Cb819df8Ef37A;

    address internal deployer;
    address internal operator;
    ServiceManager serviceManager;

    // setup
    function setUp() public {
        // test vm.rememberKey
        deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        operator = vm.rememberKey(vm.envUint("OPERATOR_PRIVATE_KEY"));
    }

    function run() public {
        // deploy ServiceManager
        vm.startBroadcast(deployer);
        serviceManager = new ServiceManager(AVS_DIRECTORY);
        vm.stopBroadcast();

        // register operator to AVS
        // register as an operator on EigenLayer before they can register with AVS - done through del manager, pull up live instance on chain of delegation manager
        IDelegationManager delegationManager = IDelegationManager(DELEGATION_MANAGER);
        // set operator details using struct
        IDelegationManager.OperatorDetails memory operatorDetails = IDelegationManager.OperatorDetails({
            __deprecated_earningsReceiver: address(0), // not needed
            delegationApprover: address(0), // not needed
            stakerOptOutWindowBlocks: 0 // not needed
        });

        vm.startBroadcast(operator);
        delegationManager.registerAsOperator(operatorDetails, "");
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
