// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../../src/ECDSAStakeRegistry.sol";

import {ISignatureUtilsMixinTypes} from
    "../../lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
// import {ECDSA} from "solady/utils/ECDSA.sol";

contract ECDSAStakeRegistryTest is Test {
    ECDSAStakeRegistry registry;
    address operator = vm.addr(1); // test EOA

    // helper to build a valid SignatureWithSaltAndExpiry for operator registration
    function _makeSignature(bytes32 digest, uint256 privateKey, uint256 expiry)
        internal
        returns (ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        return ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry({signature: sig, salt: bytes32(0), expiry: expiry});
    }

    function setUp() public {
        // Deploy with a threshold of 1 ether
        registry = new ECDSAStakeRegistry(1 ether);

        // Give operator 5 ETH
        vm.deal(address(operator), 5 ether);
    }

    function testInitialTotalWeightIsZero() public {
        // total stake should be zero at the start
        uint256 weight = registry.getTotalWeight(uint32(block.number));
        assertEq(weight, 0, "Total weight should start at 0");
    }

    function testDepositIncreasesStakeAndTotal() public {
        vm.prank(operator);
        // Deposit 3 ETH
        registry.deposit{value: 3 ether}();

        // check live stake mapping
        assertEq(registry.stakes(address(operator)), 3 ether, "Stake mapping incorrect");

        // check operator weight at current block
        uint32 _block = uint32(block.number);
        assertEq(registry.getOperatorWeight(address(operator), _block), 3 ether, "Operator weight wrong");

        // check total weight matches
        assertEq(registry.getTotalWeight(_block), 3 ether, "Total weight wrong");
    }
}
