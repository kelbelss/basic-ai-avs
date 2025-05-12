// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {ServiceManager} from "../../src/ServiceManager.sol";

// Core EigenLayer contracts & interfaces
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager, IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/token/ERC20/IERC20.sol";

abstract contract IntegrationBase is Test {
    tring HOLESKY_RPC = vm.envString("HOLESKY_RPC_URL");
    address AVS_DIRECTORY = vm.envAddress("AVS_DIRECTORY");
    address DELEGATION_MANAGER = vm.envAddress("DELEGATION_MANAGER");
    address STRATEGY_MANAGER = vm.envAddress("STRATEGY_MANAGER");
    IERC20 STETH_TOKEN = IERC20(vm.envAddress("STETH_TOKEN"));
    IStrategy STETH_STRAT = IStrategy(vm.envAddress("STETH_STRAT"));
    address STETH_WHALE = vm.envAddress("STETH_WHALE");

    ServiceManager serviceManager;

    address OPERATOR = makeAddr("operator");

    function setUp() public {
        // 1) fork Holesky
        vm.createSelectFork(HOLESKY_RPC, /*block*/ block.number);

        // 2) get some stETH for your operator
        vm.startPrank(STETH_WHALE);
        STETH_TOKEN.transfer(OPERATOR, FAUCET_AMOUNT);
        vm.stopPrank();

        // 3) operator deposits into the strategy so they can register
        vm.startPrank(OPERATOR);
        STETH_TOKEN.approve(STRATEGY_MANAGER, FAUCET_AMOUNT);
        IStrategyManager(STRATEGY_MANAGER).depositIntoStrategy(STETH_STRAT, STETH_TOKEN, FAUCET_AMOUNT);

        // 4) operator registers with EigenLayer
        IDelegationManager(DELEGATION_MANAGER).registerAsOperator(OPERATOR, 1, "");
        vm.stopPrank();

        // 5) deploy AVS ServiceManager pointing at the real AVSDirectory
        serviceManager = new ServiceManager(AVS_DIRECTORY);
    }
}
