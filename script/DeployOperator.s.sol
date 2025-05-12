// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import {SimpleOperator} from "../src/SimpleOperator.sol";

contract DeployOperator is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEV_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        SimpleOperator operator = new SimpleOperator();
        console.log("SimpleOperator deployed at:", address(operator));

        vm.stopBroadcast();
    }
}
