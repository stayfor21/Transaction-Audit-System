// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AuditSystem {
    address[3] public owners;
    uint256 public requiredSignatures = 2;
    mapping(address => bool) public isOwner;
    mapping(bytes32 => uint256) public confirmations;
    mapping(address => uint256) public balances;
    bool private locked;
    bool public paused;
    uint256 public feePercentage = 1;
    AggregatorV3Interface internal priceFeed; 

    struct ActionLog {
        address user;
        string action;
        uint256 value;
        uint256 timestamp;
    }

    mapping(address => uint256[]) private userActions;
    mapping(uint256 => ActionLog) private actionLogs;
    uint256 public actionCount; 

    event ActionPerformed(
        address indexed user,
        string action,
        uint256 value,
        uint256 timestamp
    );
    event OwnershipChangeProposed(address indexed newOwner, bytes32 proposalId);
    event OwnershipChangeConfirmed(address indexed confirmer, bytes32 proposalId);

    modifier onlyOwners() {
        require(isOwner[msg.sender], "Only owners can call this function");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(address _priceFeed) {
        owners = [msg.sender, 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2];
        isOwner[msg.sender] = true;
        isOwner[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4] = true;
        isOwner[0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2] = true;
        priceFeed = AggregatorV3Interface(_priceFeed); 
    }

    function getTimestamp() internal view returns (uint256) {
        (, , , uint256 updatedAt, ) = priceFeed.latestRoundData();
        return updatedAt;
    }

    function deposit() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "Deposit must be greater than 0");
        balances[msg.sender] += msg.value;
        actionLogs[actionCount] = ActionLog(msg.sender, "Deposit", msg.value, getTimestamp());
        userActions[msg.sender].push(actionCount);
        actionCount += 1;
        emit ActionPerformed(msg.sender, "Deposit", msg.value, getTimestamp());
    }

    function transfer(address recipient, uint256 amount) external nonReentrant whenNotPaused {
        require(recipient != address(0), "Invalid recipient address");
        require(amount > 0, "Amount must be greater than 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountAfterFee = amount - fee;
        require(balances[msg.sender] >= amount, "Insufficient balance including fee"); 

        balances[msg.sender] -= amount;
        balances[recipient] += amountAfterFee;
        balances[owners[0]] += fee; 

        actionLogs[actionCount] = ActionLog(msg.sender, "Transfer", amount, getTimestamp());
        userActions[msg.sender].push(actionCount);
        actionCount += 1;
        emit ActionPerformed(msg.sender, "Transfer", amount, getTimestamp());
    }

    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        actionLogs[actionCount] = ActionLog(msg.sender, "Withdraw", amount, getTimestamp());
        userActions[msg.sender].push(actionCount);
        actionCount += 1;
        emit ActionPerformed(msg.sender, "Withdraw", amount, getTimestamp());
    }

    function togglePause() external onlyOwners {
        paused = !paused;
        emit ActionPerformed(
            msg.sender,
            paused ? "Pause" : "Unpause",
            0,
            getTimestamp()
        );
    }

    function proposeChangeOwner(address newOwner) external onlyOwners {
        require(newOwner != address(0), "Invalid new owner address");
        bytes32 proposalId = keccak256(abi.encodePacked(newOwner, getTimestamp()));
        confirmations[proposalId] = 1;
        emit OwnershipChangeProposed(newOwner, proposalId);
    }

    function confirmChangeOwner(bytes32 proposalId) external onlyOwners {
        require(confirmations[proposalId] > 0, "Proposal does not exist");
        require(confirmations[proposalId] < requiredSignatures, "Already confirmed");
        confirmations[proposalId] += 1;
        emit OwnershipChangeConfirmed(msg.sender, proposalId);

        if (confirmations[proposalId] == requiredSignatures) {
            address newOwner = address(uint160(uint256(proposalId) ^ uint256(getTimestamp())));
            owners[0] = newOwner;
            emit ActionPerformed(msg.sender, "ChangeOwner", 0, getTimestamp());
            delete confirmations[proposalId];
        }
    }

    function getUserActionCount(address user) external view onlyOwners returns (uint256) {
        return userActions[user].length;
    }

    function getActionLog(uint256 index) external view onlyOwners returns (ActionLog memory) {
        return actionLogs[index];
    }
}
