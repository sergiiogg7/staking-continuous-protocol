// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/StakingApp.sol";
import "../src/StakingToken.sol";

contract StakingAppFuzz is Test {
    StakingToken internal token;
    StakingApp internal stakingApp;

    address internal owner = vm.addr(1);
    address internal user1 = vm.addr(2);
    address internal user2 = vm.addr(3);

    uint256 internal minStakingAmount_ = 1e18;
    uint256 internal rewardsDuration_ = 30 days;

    function setUp() public {
        token = new StakingToken("Staking Token", "STK", owner);
        stakingApp = new StakingApp(address(token), owner, minStakingAmount_, rewardsDuration_);
    }

    function _mintAndApprove(address user_, uint256 amount_) internal {
        vm.startPrank(owner);
        token.mint(amount_);
        token.transfer(user_, amount_);
        vm.stopPrank();
        vm.prank(user_);
        token.approve(address(stakingApp), amount_);
    }

    function _fundRewards(uint256 ethAmount_) internal {
        vm.deal(owner, ethAmount_);
        vm.prank(owner);
        stakingApp.notifyRewardAmount{value: ethAmount_}(ethAmount_);
    }

    // Any amount below minStakingAmount (and > 0) reverts with BelowMinimumStake
    function testFuzz_stake_belowMinimum_reverts(uint256 amount_) public {
        vm.assume(amount_ > 0 && amount_ < minStakingAmount_);
        _mintAndApprove(user1, amount_);

        vm.expectRevert(abi.encodeWithSelector(BelowMinimumStake.selector, minStakingAmount_, amount_));
        vm.prank(user1);
        stakingApp.stake(amount_);
    }

    // earned() grows monotonically as time advances within the reward period
    function testFuzz_earned_growsWithTime(uint256 timeElapsed_) public {
        timeElapsed_ = bound(timeElapsed_, 1, rewardsDuration_);

        _mintAndApprove(user1, minStakingAmount_);
        vm.prank(user1);
        stakingApp.stake(minStakingAmount_);
        _fundRewards(1 ether);

        uint256 earnedBefore = stakingApp.earned(user1);

        vm.warp(block.timestamp + timeElapsed_);

        uint256 earnedAfter = stakingApp.earned(user1);
        assertGe(earnedAfter, earnedBefore);
    }

    // Two equal stakers split rewards ~50/50 regardless of amount and time
    function testFuzz_earned_equalStakers_splitHalf(uint96 amount_, uint256 timeElapsed_) public {
        uint256 amount = bound(uint256(amount_), minStakingAmount_, 1e23);
        timeElapsed_ = bound(timeElapsed_, 1, rewardsDuration_);

        _mintAndApprove(user1, amount);
        _mintAndApprove(user2, amount);

        vm.prank(user1);
        stakingApp.stake(amount);
        vm.prank(user2);
        stakingApp.stake(amount);

        _fundRewards(1 ether);
        vm.warp(block.timestamp + timeElapsed_);

        uint256 earned1 = stakingApp.earned(user1);
        uint256 earned2 = stakingApp.earned(user2);

        // Both earn equal amounts (within 1 wei rounding)
        assertApproxEqAbs(earned1, earned2, 1);
    }

    // Total rewards distributed never exceed funded amount
    function testFuzz_totalRewards_neverExceedFunded(uint96 amount1_, uint96 amount2_, uint256 timeElapsed_) public {
        uint256 amount1 = bound(uint256(amount1_), minStakingAmount_, 1e23);
        uint256 amount2 = bound(uint256(amount2_), minStakingAmount_, 1e23);
        timeElapsed_ = bound(timeElapsed_, 1, rewardsDuration_);

        _mintAndApprove(user1, amount1);
        _mintAndApprove(user2, amount2);

        vm.prank(user1);
        stakingApp.stake(amount1);
        vm.prank(user2);
        stakingApp.stake(amount2);

        uint256 funded = 1 ether;
        _fundRewards(funded);
        vm.warp(block.timestamp + timeElapsed_);

        uint256 totalEarned = stakingApp.earned(user1) + stakingApp.earned(user2);
        assertLe(totalEarned, funded + 1); // +1 for rounding
    }

    // Any in-bounds rewardsDuration is stored correctly after period ends
    function testFuzz_setRewardsDuration_stores(uint256 duration_) public {
        duration_ = bound(duration_, stakingApp.MIN_REWARDS_DURATION(), stakingApp.MAX_REWARDS_DURATION());
        vm.prank(owner);
        stakingApp.setRewardsDuration(duration_);
        assertEq(stakingApp.rewardsDuration(), duration_);
    }

    // Withdraw never returns more than staked
    function testFuzz_withdraw_neverExceedsBalance(uint256 stakeAmount_, uint256 withdrawAmount_) public {
        stakeAmount_ = bound(stakeAmount_, minStakingAmount_, 1e23);
        withdrawAmount_ = bound(withdrawAmount_, 1, stakeAmount_);

        _mintAndApprove(user1, stakeAmount_);
        vm.prank(user1);
        stakingApp.stake(stakeAmount_);

        vm.prank(user1);
        stakingApp.withdraw(withdrawAmount_);

        assertEq(stakingApp.balances(user1), stakeAmount_ - withdrawAmount_);
        assertEq(token.balanceOf(user1), withdrawAmount_);
    }
}
