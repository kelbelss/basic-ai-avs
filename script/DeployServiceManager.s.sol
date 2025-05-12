// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ServiceManager} from "../src/ServiceManager.sol";

contract DeployServiceManager is Script {
    function run() external {
        
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address avsDirectory = vm.envAddress("AVS_DIRECTORY");

        vm.startBroadcast(deployerKey);
        ServiceManager serviceManager = new ServiceManager(avsDirectory);
        console.log("ServiceManager deployed at:", address(serviceManager));
        vm.stopBroadcast();
    }
}
