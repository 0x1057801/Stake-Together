// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakeTogether {

    // this is to safely transfer tokens in and out
    using SafeERC20 for IERC20;

    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event RewardClaimed(address indexed user, uint256 stake, uint256 reward);

    IERC20 public cloudCoin;
    uint256 public constant TOTAL_REWARDS = 1_000_000 * 10**18; // Assuming 18 decimals
    uint256 public beginDate;
    uint256 public endDate; // beginDate + 7 days
    
    uint256 public totalStaked;
    mapping(address => uint256) public stakes;
    mapping(address => bool) public hasClaimed;

    constructor(address _cloudCoin, uint256 _beginDate) {
        cloudCoin = IERC20(_cloudCoin);
        beginDate = _beginDate;
        endDate = _beginDate + 7 days;
    
        // Contract should receive TOTAL_REWARDS before staking begins
    }

    function stake(uint256 amount) external {
        // make sure the staking period is on and the amount being staked > 0
        require(block.timestamp >= beginDate && block.timestamp <= endDate, "outside staking period");
        require(amount > 0, "must stake more than 0 tokens");

        // transfer tokens from the user to the contract
        // I added safe xferFrom here for added security
        cloudCoin.safeTransferFrom(msg.sender, address(this), amount);

        // keep track of how much each staker is staking when a staker stakes
        stakes[msg.sender] += amount;

        // add each staked amount to the totalStaked (doing reward calc this way)
        totalStaked += amount;

        // emiting event here to log stake events, keeps it all on the up & up!
        emit Staked(msg.sender, amount, block.timestamp);
    }

    function calculateReward(address user) public view returns (uint256) {
        // if no stakes (total or user), return 0
        if (totalStaked == 0 || stakes[user] == 0) {
            return 0;
        }

        // I think this is a big spot for exploiting this contract 
        // and potentially what the RareSkills problem statement was
        // getting at with 'edge cases'. I will investigate once finished
        return (stakes[user] * TOTAL_REWARDS) / totalStaked;
    }

    function claimReward() external {

        require(block.timestamp > endDate, "staking period not over");
        require(hasClaimed[msg.sender] == false, "reward already claimed");
        require(stakes[msg.sender] > 0, "user has no stake");

        // get what msg.sender staked and store it here to use later
        uint256 userStake = stakes[msg.sender];

        // let's calculate msg.sender's reward and store it in a variable to use later
        uint256 reward = calculateReward(msg.sender);
        
        // set up total amount to send back to msg.sender
        uint256 totalAmount = stakes[msg.sender] + reward;

        // make sure the reward can only be claimed once
        hasClaimed[msg.sender] = true;

        // reduce msg.sender's stake in contract o 0
        stakes[msg.sender] = 0;

        // update the totalStaked in the contract
        totalStaked -= userStake;

        // emit the event to keep track of claimed rewards
        emit RewardClaimed(msg.sender, stakes[msg.sender], reward);

        // send msg.sender totalAmount (amount staked + staking reward)
        // using safe xfer here for security 
        cloudCoin.safeTransfer(msg.sender, totalAmount);
    }
}