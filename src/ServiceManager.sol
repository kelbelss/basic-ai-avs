// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IAVSDirectory} from "eigenlayer-contracts/src/contracts/interfaces/IAVSDirectory.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {IStrategyManager, IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

contract ServiceManager {
    // TODO: createNewTask is permissionless so open to griefing - add a whitelist of operators that can create tasks? consider?
    // TODO: add task expiry - currently commented out
    // TODO: add slashing logic, and rewards

    using ECDSA for bytes32; // manipulate signatures and hashes

    // config
    IStrategyManager public immutable strategyManager;
    IStrategy[] public countedStrategies; // strategies we count toward the threshold
    uint256 public immutable MIN_STAKE;
    address public immutable avsDirectory; // mainnet address - set in constructor

    // state variables
    uint32 public latestTaskNumber; // incremented when a new task is created
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
    constructor(
        address _avsDirectory,
        address _strategyManager,
        address[] memory _strategies, // stETH
        uint256 _minStakeWei
    ) {
        avsDirectory = _avsDirectory;
        strategyManager = IStrategyManager(_strategyManager);
        MIN_STAKE = _minStakeWei;

        for (uint256 i = 0; i < _strategies.length; ++i) {
            countedStrategies.push(IStrategy(_strategies[i]));
        }
    }

    // register operator - IAVSDirectory will register operator to this AVS
    function registerOperatorToAVS(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry memory operatorSignature
    ) external {
        require(meetsStakeThreshold(operator), "operator: insufficient stake");

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
        allTaskHashes[latestTaskNumber] = keccak256(abi.encode(newTask));
        emit NewTaskCreated(latestTaskNumber, newTask);
        latestTaskNumber++;

        return newTask;
    }

    // respond to task
    function respondToTask(Task calldata task, uint32 taskIndex, bytes memory signature, bool isSafe)
        external
        onlyRegisteredOperator
    {
        require(meetsStakeThreshold(msg.sender), "stake below minimum");
        // check that task is valid, hasnt been responded to yet
        require(
            keccak256(abi.encode(task)) == allTaskHashes[taskIndex],
            "task given does not match the task in the contract"
        );
        require(allTaskResponses[msg.sender][taskIndex].length == 0, "task already responded to");
        // require(block.number <= task.taskCreatedBlock + 100, "task expired");

        bytes32 digest = keccak256(abi.encodePacked(isSafe, task.contents)).toEthSignedMessageHash();

        if (digest.recover(signature) != msg.sender) {
            // 1271 fallback path
            (bool ok, bytes memory ret) =
                msg.sender.staticcall(abi.encodeWithSignature("isValidSignature(bytes32,bytes)", digest, signature));
            require(ok, "1271 call failed");

            bytes4 magic; // accept valid signatures from every EIP-1271 wallet
            if (ret.length == 32) magic = abi.decode(ret, (bytes4)); // slice first 4 bytes

            else if (ret.length == 4) magic = bytes4(ret); // already sized

            else revert("unexpected 1271 return");
            require(magic == 0x1626ba7e, "bad 1271 signature");
        }

        // update storage with task response
        allTaskResponses[msg.sender][taskIndex] = signature;

        emit TaskResponsed(taskIndex, task, isSafe, msg.sender);
    }

    // shares -> underlying ETH

    function currentUnderlying(address operator) internal view returns (uint256 total) {
        uint256 length = countedStrategies.length;
        for (uint256 i = 0; i < length; ++i) {
            IStrategy strat = countedStrategies[i];

            // amount of shares this operator owns in this strategy
            uint256 shares = strategyManager.stakerDepositShares(operator, strat);

            // convert shares to the ETH-denominated “underlying” value
            total += strat.sharesToUnderlying(shares);
        }
        return total;
    }

    // threshold gate
    function meetsStakeThreshold(address operator) internal view returns (bool) {
        return currentUnderlying(operator) >= MIN_STAKE;
    }
}
