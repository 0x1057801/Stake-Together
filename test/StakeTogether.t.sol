// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {StakeTogether} from "../src/StakeTogether.sol";
import {MockCloudCoin} from "./MockCloudCoin.sol";
import {console} from "forge-std/console.sol";

contract StakeTogetherTest is Test {

    // set up the contracts I need to run tests
    StakeTogether public stakeTogether;
    MockCloudCoin public cloudCoin;

    // get some folks involved...including a HACKER!
    address public staker1 = makeAddr("staker1");
    address public staker2 = makeAddr("staker2");
    address public attacker = makeAddr("attacker");

    // set some amounts to work with in the LP (I'm using 
    // real web3 guy lingo now!!)
    uint256 public constant TOTAL_REWARDS = 1_000_000 * 10**18;
    uint256 public constant STAKE_AMOUNT = 10_000 * 10**18;
    uint256 public beginDate;

    function setUp() public {
        cloudCoin = new MockCloudCoin();
        
        console.log("Test contract balance:", cloudCoin.balanceOf(address(this)));
        console.log("TOTAL_REWARDS:", TOTAL_REWARDS);
        
        beginDate = block.timestamp;
        stakeTogether = new StakeTogether(address(cloudCoin), beginDate);
        
        uint256 ourBalance = cloudCoin.balanceOf(address(this));
        require(ourBalance >= TOTAL_REWARDS, "Not enough tokens for rewards");
        
        cloudCoin.transfer(address(stakeTogether), TOTAL_REWARDS);
        
        console.log("StakeTogether balance:", cloudCoin.balanceOf(address(stakeTogether)));
        
        cloudCoin.mint(staker1, 100_000 * 10**18);
        cloudCoin.mint(staker2, 100_000 * 10**18);
        cloudCoin.mint(attacker, 100_000 * 10**18);
    }

    // TESTING STAKING WORKS
    function testStakeSucceeds() public {
        vm.startPrank(staker1);

        // approve contract to spend tokens
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT);

        // go ahead and stake tokens
        stakeTogether.stake(STAKE_AMOUNT);

        vm.stopPrank();

        // make sure the stake recorded correctly
        assertEq(stakeTogether.stakes(staker1), STAKE_AMOUNT);
        assertEq(stakeTogether.totalStaked(), STAKE_AMOUNT);
    }

    // TESTING TO MAKE SURE CANNOT STAKE BEFORE beginDate
    function testCannotStakeBeforeBeginDate() public {
        // I am such an idiot....have to deploy this with a future beingDate...derp..
        uint256 futureBeginDate = block.timestamp + 1 days;
        StakeTogether futureStake = new StakeTogether(address(cloudCoin), futureBeginDate);

        // start attempting to stake tokens
        vm.startPrank(staker1);
        cloudCoin.approve(address(futureStake), STAKE_AMOUNT);

        // we want to expect a revert based on staking requirements
        vm.expectRevert("outside staking period");
        futureStake.stake(STAKE_AMOUNT);

        vm.stopPrank();
    }

    // TESTING TO MAKE SURE CANNOT STAKE AFTER endDate
    function testCannotStakeAfterEndDate() public {
        // need to time travel past the endDate
        vm.warp(beginDate + 7 days + 1);

        // attempt to stake
        vm.startPrank(staker1);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT);

        // expect a revert based on staking requirements
        vm.expectRevert("outside staking period");
        stakeTogether.stake(STAKE_AMOUNT);

        vm.stopPrank();
    }

    // TESTING CALCULATION OF THE REWARD
    function testRewardCalculation() public {
        // staker1 will stake 10K
        vm.startPrank(staker1);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT);
        stakeTogether.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // staker2 will stake 40K (total should be 50K here)
        vm.startPrank(staker2);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT * 4);
        stakeTogether.stake(STAKE_AMOUNT * 4);
        vm.stopPrank();

        // staker1 should get 20% of rewards
        uint256 expectedReward = (TOTAL_REWARDS * 10_000) / 50_000; // 200K tokens
        uint256 actualReward = stakeTogether.calculateReward(staker1);

        // check actual == expected
        assertEq(actualReward, expectedReward);

        // staker2 should get 80% of rewards
        uint256 expectedReward2 = (TOTAL_REWARDS * 40_000) / 50_000;
        uint256 actualReward2 = stakeTogether.calculateReward(staker2);

        // check actual2 == expected2
        assertEq(actualReward2, expectedReward2);
    }

    // TESTING msg.sender CLAIMING REWARDS WORKS
    function testClaimRewardsSucceeds() public {
        // stake some tokens
        vm.startPrank(staker1);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT);
        stakeTogether.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // move past staking period
        vm.warp(beginDate + 7 days + 1);
        
        // attempt a claim
        uint256 balanceBefore = cloudCoin.balanceOf(staker1);
        
        vm.prank(staker1);
        stakeTogether.claimReward();
        
        uint256 balanceAfter = cloudCoin.balanceOf(staker1);
        
        // should receive correct stake + reward
        assertEq(balanceAfter - balanceBefore, STAKE_AMOUNT + TOTAL_REWARDS);
        
        // stake should be 0
        assertEq(stakeTogether.stakes(staker1), 0);
        
        // hasClaimed should == true
        assertTrue(stakeTogether.hasClaimed(staker1));
    }
    
    // TESTING CONSTRAINT ON CLAIMING BEFORE endDate
    function testCannotClaimBeforeEndDate() public {
        // stake some tokens
        vm.startPrank(staker1);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT);
        stakeTogether.stake(STAKE_AMOUNT);
        
        // expect a revert if trying to claim during staking period
        vm.expectRevert("staking period not over");
        stakeTogether.claimReward();
        
        vm.stopPrank();
    }
    
    // TEST THAT STAKE + REWARD CAN'T BE CLAIMED TWICE
    function testCannotClaimTwice() public {
        // stake tokens
        vm.startPrank(staker1);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT);
        stakeTogether.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // go past staking period
        vm.warp(beginDate + 7 days + 1);
        
        // attempt a claim
        vm.startPrank(staker1);
        stakeTogether.claimReward();
        
        // expect a revert if another claim attempted
        vm.expectRevert("reward already claimed");
        stakeTogether.claimReward();
        
        vm.stopPrank();
    }
    
    // THE EXPLOIT I FOUND
    function testLastSecondStakingExploit() public {
        // let staker1 stake 10K tokens early
        vm.startPrank(staker1);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT);
        stakeTogether.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // staker2 also stakes 10K early
        vm.startPrank(staker2);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT);
        stakeTogether.stake(STAKE_AMOUNT);
        vm.stopPrank();
        
        // total so far: 20k
        // each should get 50% = 500k rewards
        
        // move to just before end of staking period
        vm.warp(beginDate + 7 days - 1);
        
        // hackerman stakes 20K on the last second
        vm.startPrank(attacker);
        cloudCoin.approve(address(stakeTogether), STAKE_AMOUNT * 2);
        stakeTogether.stake(STAKE_AMOUNT * 2);
        vm.stopPrank();
        
        // now total is 40k
        // attacker now has 50% for 1 second of staking! That's not fair!
        
        // advance time
        vm.warp(beginDate + 7 days + 1);
        
        // check rewards for each
        uint256 staker1Reward = stakeTogether.calculateReward(staker1);
        uint256 staker2Reward = stakeTogether.calculateReward(staker2);
        uint256 attackerReward = stakeTogether.calculateReward(attacker);
        
        // proves here attacker gets 50% for 1 second of staking
        // stakers get 25% each for 7 whole days of staking!
        // I think this is a vulnerability in this ccontract. 
        // a bad actor can really screw up the economics of a protocol like this
        assertEq(attackerReward, 500_000 * 10**18);
        assertEq(staker1Reward, 250_000 * 10**18);
        assertEq(staker2Reward, 250_000 * 10**18);
    }
}
