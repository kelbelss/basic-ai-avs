// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract ServiceManager {
    //    TODO: register operator, deregister operator, create task, respond to task

    using ECDSA for bytes32; // manipulate signatures and hashes

    // state variables
    address public immutable avsDirectory; // mainnet address - set in constructor
    uint32 public lastestTaskNumber; // incremented when a new task is created
    mapping(address => bool) public operatorRegistered; // registered to AVS
    mapping(uint32 => bytes32) public allTaskHashes;
    mapping(address => mapping(uint32 => bytes)) public allTaskResponses;

    // events
    event NewTaskCreated(uint32 indexed taskIndex, Task task);
    event TaskResponsed(uint32 indexed taskIndex, Task task, bool isSafe, address operator);

    // types
    struct Task {
        string contents; // content to moderate
        uint32 taskCreatedBlock;
    }

    // modifiers
    modifier onlyRegisteredOperator() {
        require(operatorRegistered[msg.sender], "Not registered operator");
        _;
    }

    // constructor
    constructor(address _avsDirectory) {
        avsDirectory = _avsDirectory;
    }

    // register operator - IAVSDirectory will register operator to this AVS
    function registerOperatorToAVS(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {
        IAVSDirectory(avsDirectory).registerOperatorToAVS(operator, operatorSignature);
        operatorRegistered[operator] = true;
    }

    // deregister operator - IAVSDirectory will deregister operator from this AVS
    function deregisterOperatorFromAVS(address operator) external onlyRegisteredOperator {
        require(msg.sender == operator, "Only operator can deregister");
        IAVSDirectory(avsDirectory).deregisterOperatorFromAVS(operator);
        operatorRegistered[operator] = false;
    }

    // create task - take in string with contents to moderate
    function createNewTask(string memory contents) external returns (Task memory) {
        // create new task struct
        Task memory newTask = Task({contents: contents, taskCreatedBlock: uint32(block.number)});

        // store hash of task onchain, emit event and increase task number
        allTaskHashes[lastestTaskNumber] = keccak256(abi.encode(newTask));
        emit NewTaskCreated(lastestTaskNumber, newTask);
        lastestTaskNumber++;

        return newTask;
    }

    // respond to task
    function respondToTask(Task calldata task, uint32 referenceTaskIndex, bytes memory signature, bool isSafe)
        external
        onlyRegisteredOperator
    {
        // check that task is valid, hasnt been responded to yet
        require(
            keccak256(abi.encode(task)) == allTaskHashes[referenceTaskIndex],
            "task given does not match the task in the contract"
        );
        require(allTaskResponses[msg.sender][referenceTaskIndex].length == 0, "task already responded to");
        // require(block.number <= task.taskCreatedBlock + 100, "task expired");

        // the message that was signed
        bytes32 messageHash = keccak256(abi.encodePacked(isSafe, task.contents));

        // make sure it was signed by the operator thats calling this function
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        if (ethSignedMessageHash.recover(signature) != msg.sender) {
            revert("Signature does not match");
        } // check gas cost and change to require

        // update storage with task response
        allTaskResponses[msg.sender][referenceTaskIndex] = signature;

        emit TaskResponsed(referenceTaskIndex, task, isSafe, msg.sender);
    }
}
