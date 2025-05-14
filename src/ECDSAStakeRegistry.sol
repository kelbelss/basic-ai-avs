// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {ISignatureUtilsMixinTypes} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtilsMixin.sol";
import {IERC1271} from "../lib/eigenlayer-contracts/lib/openzeppelin-contracts-v4.9.0/contracts/interfaces/IERC1271.sol";

contract ECDSAStakeRegistry is IERC1271 {
    using ECDSA for bytes32;

    // MAGIC: EIP-1271 return value. This is the value that the contract returns to signal that the signature is valid.
    bytes4 public constant MAGIC = 0x1626ba7e;

    struct Checkpoint {
        uint32 fromBlock;
        uint256 stake;
    }

    Checkpoint[] public totalHistory; // checkpoint array
    mapping(address => Checkpoint[]) public operatorHistory; //checkpoint array
    mapping(address => uint256) public stakes; // current balances
    uint256 public thresholdStake; // minimum stake to qualify.

    constructor(uint256 _thresholdStake) {
        thresholdStake = _thresholdStake; // declare system’s minimum stake requirement up front (e.g. 32 ETH)
        totalHistory.push(Checkpoint(uint32(block.number), 0)); // Seeding totalHistory ensures that “get total stake at block = deployment block” works correctly, even if nobody has staked yet.
    }

    // move collateral in and out of registry.
    // “skin in the game" ometer
    // will use these balances to gate registration and to pro-rata rewards
    function deposit() external payable {
        stakes[msg.sender] += msg.value;
        _writeCheckpoint(msg.sender);
        _writeTotalCheckpoint();
    }

    function withdraw(uint256 amount) external {
        require(stakes[msg.sender] >= amount, "Insufficient stake");
        stakes[msg.sender] -= amount;
        _writeCheckpoint(msg.sender);
        _writeTotalCheckpoint();
        payable(msg.sender).transfer(amount);
    }

    // query historical stake
    // record a checkpoint for that operator and one for the global stake - used in deposit/withdraw
    // if multiple changes happen in the same block, update the existing checkpoint rather than pushing a new one
    // this accurate history is critical for fair rewards or slashing that I'll implement later
    function _writeCheckpoint(address operator) internal {
        Checkpoint[] storage history = operatorHistory[operator];
        uint32 _block = uint32(block.number);
        if (history.length > 0 && history[history.length - 1].fromBlock == _block) {
            history[history.length - 1].stake = stakes[operator];
        } else {
            history.push(Checkpoint(_block, stakes[operator]));
        }
    }

    function _writeTotalCheckpoint() internal {
        uint32 _block = uint32(block.number);
        uint256 total = address(this).balance;
        Checkpoint storage last = totalHistory[totalHistory.length - 1];
        if (last.fromBlock == _block) {
            last.stake = total;
        } else {
            totalHistory.push(Checkpoint(_block, total));
        }
    }

    // a generic _getValueAt that is linearly-scanning backward for the last checkpoint ≤ _refBlock
    // used in getOperatorWeight(operator, block) and getTotalWeight(block)
    // the off-chain services, the AVSDirectory, and the rewards logic will all need to know “what was the stake at this precise past block?”
    // can’t accurately attribute work or slash events to the correct snapshot in time without this
    function _getValueAt(Checkpoint[] storage history, uint32 refBlock) internal view returns (uint256) {
        if (history.length == 0 || refBlock < history[0].fromBlock) return 0;
        for (uint256 i = history.length; i > 0; --i) {
            if (history[i - 1].fromBlock <= refBlock) {
                return history[i - 1].stake;
            }
        }
        return 0;
    }

    function getOperatorWeight(address operator, uint32 refBlock) public view returns (uint256) {
        return _getValueAt(operatorHistory[operator], refBlock);
    }

    function getTotalWeight(uint32 refBlock) public view returns (uint256) {
        return _getValueAt(totalHistory, refBlock);
    }

    // helper _validateThresholdStake(weight) that reverts if weight < thresholdStake
    // centralises the “must have minimum stake” rule so I can call it from registration, signature-verification
    function _validateThresholdStake(uint256 signedWeight) internal view {
        require(signedWeight >= thresholdStake, "Stake below threshold");
    }

    // how the  service manager confirms that this key really holds enough stake right now and signed off on joining the AVS
    // enforcing cryptographic validity and collateral sufficiency
    function registerOperatorWithSignature(
        ISignatureUtilsMixinTypes.SignatureWithSaltAndExpiry calldata sigData,
        address signingKey
    ) external view {
        require(block.timestamp <= sigData.expiry, "Signature expired");

        bytes32 digest = keccak256(abi.encodePacked(signingKey, sigData.salt, sigData.expiry)).toEthSignedMessageHash();

        address recovered = digest.recover(sigData.signature);
        require(recovered == signingKey, "Bad registration sig");

        uint256 weight = getOperatorWeight(signingKey, uint32(block.number));
        _validateThresholdStake(weight);
    }

    // EIP-1271 lets the contracts act like wallets -> other contracts can call isValidSignature to accept or reject arbitrary data signatures
    // ensure any on-chain signature checks automatically enforce the stake rule
    function isValidSignature(bytes32 hash, bytes memory signature) public view override returns (bytes4) {
        address signer = hash.toEthSignedMessageHash().recover(signature);
        if (getOperatorWeight(signer, uint32(block.number)) < thresholdStake) {
            return 0xffffffff;
        }
        return MAGIC;
    }
}
