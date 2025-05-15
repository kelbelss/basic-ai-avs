// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {MockStrategy} from "./MockStrategy.sol";

contract MockStrategyManager {
    mapping(address => mapping(address => uint256)) public shares;

    function setShares(address staker, address strat, uint256 amount) external {
        shares[staker][strat] = amount;
    }

    // selector matches IStrategyManager.stakerDepositShares
    function stakerDepositShares(address staker, address strat) external view returns (uint256) {
        return shares[staker][strat];
    }
}
