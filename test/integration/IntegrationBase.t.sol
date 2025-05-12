// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {ServiceManager} from "../../src/ServiceManager.sol";

// Core EigenLayer contracts & interfaces
import {IDelegationManager} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {
    IStrategyManager, IStrategy
} from "../../lib/eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "../../lib/eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/token/ERC20/IERC20.sol";

contract IntegrationBase is Test {
    string HOLESKY_RPC;
    address AVS_DIRECTORY;
    address DELEGATION_MANAGER;
    address STRATEGY_MANAGER;
    IERC20 STETH_TOKEN;
    IStrategy STETH_STRAT;
    address STETH_WHALE;

    uint256 FAUCET_AMOUNT = 1e17; // 0.1 stETH

    ServiceManager serviceManager;

    address operator;

    function setUp() public virtual {
        // 1) load environment & keys
        HOLESKY_RPC = vm.envString("HOLESKY_RPC_URL");
        AVS_DIRECTORY = vm.envAddress("AVS_DIRECTORY");
        DELEGATION_MANAGER = vm.envAddress("DELEGATION_MANAGER");
        STRATEGY_MANAGER = vm.envAddress("STRATEGY_MANAGER");
        STETH_TOKEN = IERC20(vm.envAddress("STETH_TOKEN"));
        STETH_STRAT = IStrategy(vm.envAddress("STETH_STRAT"));
        STETH_WHALE = vm.envAddress("STETH_WHALE");
        operator = vm.envAddress("SIMPLE_OPERATOR");

        // 2) fund the operator with some eth
        vm.deal(operator, 1e18); // 1 eth
        vm.makePersistent(operator);

        // 3) fork Holesky
        vm.createSelectFork(HOLESKY_RPC, block.number);

        // 4) get some stETH for your operator
        vm.startPrank(STETH_WHALE);
        STETH_TOKEN.transfer(operator, FAUCET_AMOUNT);
        vm.stopPrank();

        // 5) operator deposits into the strategy so they can register
        vm.startPrank(operator);
        STETH_TOKEN.approve(STRATEGY_MANAGER, FAUCET_AMOUNT);
        IStrategyManager(STRATEGY_MANAGER).depositIntoStrategy(STETH_STRAT, STETH_TOKEN, FAUCET_AMOUNT);

        // 6) operator registers with EigenLayer
        IDelegationManager(DELEGATION_MANAGER).registerAsOperator(operator, 1, "");
        vm.stopPrank();

        // 7) deploy AVS ServiceManager pointing at the real AVSDirectory
        serviceManager = new ServiceManager(AVS_DIRECTORY);
    }
}
