// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import "../../src/ServiceManager.sol";
import {MockAVSDirectory} from "./mocks/MockAVSDirectory.sol";
import {ISignatureUtilsMixinTypes} from
    "../../lib/eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {MockStrategyManager, MockStrategy} from "./mocks/MockStrategyManager.sol";

contract ServiceManagerUnitTest is Test {
    MockAVSDirectory mockAvs;
    ServiceManager serviceManager;
    MockStrategyManager mockStrategyManager;
    MockStrategy mockStrategy;

    uint256 constant MIN_STAKE = 1 ether;

    address operator = vm.addr(1);

    function setUp() public {
        // deploy mock directory and ServiceManager
        mockAvs = new MockAVSDirectory();
        // serviceManager = new ServiceManager(address(mockAvs));
        mockStrategyManager = new MockStrategyManager();
        mockStrategy = new MockStrategy();

        // give the operator some “stake” (in shares == wei for mock)
        mockStrategyManager.setShares(operator, address(mockStrategy), 2 ether);

        // Build the strategy list
        address[] memory strategies = new address[](1);
        strategies[0] = address(mockStrategy);

        serviceManager = new ServiceManager(address(mockAvs), address(mockStrategyManager), strategies, MIN_STAKE);
    }

    function testRegisterOperatorToAvs() public {
        // mock signature wrapper (mock does not validate contents)
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory mockSig = ISignatureUtilsMixinTypes
            .SignatureWithSaltAndExpiry({signature: bytes(""), salt: bytes32(0), expiry: block.timestamp});

        // call registerOperatorToAVS
        serviceManager.registerOperatorToAVS(operator, mockSig);

        // assert mapping flipped
        assertTrue(serviceManager.operatorRegistered(operator), "operatorRegistered should be true");

        // assert mock directory recorded the registration
        assertTrue(mockAvs.registered(operator), "MockAVSDirectory.registered should be true");
    }

    function testDeregisterOperatorFromAvs() public {
        // first register
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory mockSig = ISignatureUtilsMixinTypes
            .SignatureWithSaltAndExpiry({signature: bytes(""), salt: bytes32(0), expiry: block.timestamp});
        serviceManager.registerOperatorToAVS(operator, mockSig);

        // deregister as if called by operator
        vm.prank(operator);
        serviceManager.deregisterOperatorFromAVS(operator);

        // assert mapping cleared
        assertFalse(serviceManager.operatorRegistered(operator), "operatorRegistered should be false");

        // assert mock directory cleared
        assertFalse(mockAvs.registered(operator), "MockAVSDirectory.registered should be false");
    }

    function testCreateNewTaskAndHashing() public {
        // create task
        string memory contents = "Example task";
        ServiceManager.Task memory task = serviceManager.createNewTask(contents);

        // expected hash
        bytes32 expectedHash = keccak256(abi.encode(task));

        // assert stored hash matches
        assertEq(serviceManager.allTaskHashes(uint32(0)), expectedHash, "allTaskHashes[0] mismatch");

        // assert latestTaskNumber ++
        assertEq(uint256(serviceManager.latestTaskNumber()), 1, "latestTaskNumber should be 1");
    }

    function testRespondToTask() public {
        // register operator so they can respond
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory mockSig = ISignatureUtilsMixinTypes
            .SignatureWithSaltAndExpiry({signature: bytes(""), salt: bytes32(0), expiry: block.timestamp});
        serviceManager.registerOperatorToAVS(operator, mockSig);

        // create task
        string memory contents = "Review content";
        ServiceManager.Task memory task = serviceManager.createNewTask(contents);

        // prepare signature: sign keccak256(isSafe, contents)
        bool isSafe = true;
        bytes32 messageHash = keccak256(abi.encodePacked(isSafe, contents));
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(messageHash);

        // sign with operators key index 1
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // respond to task as operator
        vm.prank(operator);
        serviceManager.respondToTask(task, uint32(0), sig, isSafe);

        // assert signature matches
        bytes memory stored = serviceManager.allTaskResponses(operator, uint32(0));
        assertEq(stored, sig, "response signature mismatch");
    }
}
