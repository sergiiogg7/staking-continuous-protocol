// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {StakingBase} from "./utils/StakingBase.sol";
import {NoReceiveStaker} from "./mocks/NoReceiveStaker.sol";
import "../src/StakingApp.sol";

contract StakingAppValidationTest is StakingBase {
    // -------------------------------------------------------------------------
    // constructor
    // -------------------------------------------------------------------------

    function test_constructor_setsConfiguration() external view {
        // Assert
        assertEq(address(stakingApp.stakingToken()), address(token));
        assertEq(stakingApp.owner(), owner);
        assertEq(stakingApp.minStakingAmount(), MIN_STAKE);
        assertEq(stakingApp.rewardsDuration(), DURATION);
    }

    function test_constructor_withZeroToken_revertsWithZeroAddress() external {
        // Arrange / Act / Assert
        vm.expectRevert(ZeroAddress.selector);
        new StakingApp(address(0), owner, MIN_STAKE, DURATION);
    }

    function test_constructor_withDurationBelowMin_revertsWithInvalidRewardsDuration() external {
        // Arrange
        uint256 tooShort = stakingApp.MIN_REWARDS_DURATION() - 1;

        // Act / Assert
        vm.expectRevert(abi.encodeWithSelector(InvalidRewardsDuration.selector, tooShort));
        new StakingApp(address(token), owner, MIN_STAKE, tooShort);
    }

    function test_constructor_withDurationAboveMax_revertsWithInvalidRewardsDuration() external {
        // Arrange
        uint256 tooLong = stakingApp.MAX_REWARDS_DURATION() + 1;

        // Act / Assert
        vm.expectRevert(abi.encodeWithSelector(InvalidRewardsDuration.selector, tooLong));
        new StakingApp(address(token), owner, MIN_STAKE, tooLong);
    }

    // -------------------------------------------------------------------------
    // setRewardsDuration
    // -------------------------------------------------------------------------

    function test_setRewardsDuration_belowMin_revertsWithInvalidRewardsDuration() external {
        // Arrange
        uint256 tooShort = stakingApp.MIN_REWARDS_DURATION() - 1;

        // Act / Assert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InvalidRewardsDuration.selector, tooShort));
        stakingApp.setRewardsDuration(tooShort);
    }

    function test_setRewardsDuration_aboveMax_revertsWithInvalidRewardsDuration() external {
        // Arrange
        uint256 tooLong = stakingApp.MAX_REWARDS_DURATION() + 1;

        // Act / Assert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InvalidRewardsDuration.selector, tooLong));
        stakingApp.setRewardsDuration(tooLong);
    }

    function test_setRewardsDuration_emitsEvent() external {
        // Arrange
        vm.expectEmit(false, false, false, true);
        emit StakingApp.RewardsDurationChanged(7 days);

        // Act
        vm.prank(owner);
        stakingApp.setRewardsDuration(7 days);
    }

    // -------------------------------------------------------------------------
    // notifyRewardAmount
    // -------------------------------------------------------------------------

    function test_notifyRewardAmount_withTooSmallReward_revertsWithRewardRateTooLow() external {
        // Arrange: a reward below one wei per second rounds the rate down to zero
        uint256 reward = DURATION - 1;
        vm.deal(owner, reward);

        // Act / Assert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RewardRateTooLow.selector, reward));
        stakingApp.notifyRewardAmount{value: reward}(reward);
    }

    function test_notifyRewardAmount_withZeroReward_revertsWithRewardRateTooLow() external {
        // Arrange / Act / Assert
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RewardRateTooLow.selector, 0));
        stakingApp.notifyRewardAmount(0);
    }

    function test_notifyRewardAmount_emitsRewardAdded() external {
        // Arrange
        vm.deal(owner, 1 ether);
        vm.expectEmit(false, false, false, true);
        emit StakingApp.RewardAdded(1 ether);

        // Act
        vm.prank(owner);
        stakingApp.notifyRewardAmount{value: 1 ether}(1 ether);
    }

    // -------------------------------------------------------------------------
    // reward accounting views
    // -------------------------------------------------------------------------

    function test_lastTimeRewardApplicable_afterPeriodEnd_returnsPeriodFinish() external {
        // Arrange
        _fund(1 ether);
        uint256 finish = stakingApp.periodFinish();

        // Act
        vm.warp(finish + 10 days);

        // Assert
        assertEq(stakingApp.lastTimeRewardApplicable(), finish);
    }

    function test_lastTimeRewardApplicable_duringPeriod_returnsNow() external {
        // Arrange
        _fund(1 ether);

        // Act
        vm.warp(block.timestamp + 1 days);

        // Assert
        assertEq(stakingApp.lastTimeRewardApplicable(), block.timestamp);
    }

    function test_rewardPerToken_withNoStakers_returnsStoredValue() external {
        // Arrange
        _fund(1 ether);
        vm.warp(block.timestamp + 5 days);

        // Act / Assert
        assertEq(stakingApp.rewardPerToken(), 0);
    }

    function test_rewards_whileNobodyStaked_areNotDistributedRetroactively() external {
        // Arrange: first half of the period passes with an empty pool
        _fund(30 ether);
        vm.warp(block.timestamp + 15 days);

        // Act: Alice stakes and the rest of the period elapses
        _stake(alice, 10 ether);
        vm.warp(block.timestamp + 15 days);

        // Assert: she only earns the second half
        assertApproxEqAbs(stakingApp.earned(alice), 15 ether, DURATION);
    }

    // -------------------------------------------------------------------------
    // ETH payment failures
    // -------------------------------------------------------------------------

    function test_claimRewards_whenStakerCannotReceiveEth_revertsWithEthTransferFailed() external {
        // Arrange
        NoReceiveStaker staker = new NoReceiveStaker();
        _giveTokens(address(staker), 10 ether);
        staker.stake(token, stakingApp, 10 ether);
        _fund(30 ether);
        vm.warp(block.timestamp + DURATION);

        // Act / Assert
        vm.expectRevert(EthTransferFailed.selector);
        staker.claim(stakingApp);
    }

    function test_exit_whenStakerCannotReceiveEth_revertsWithEthTransferFailed() external {
        // Arrange
        NoReceiveStaker staker = new NoReceiveStaker();
        _giveTokens(address(staker), 10 ether);
        staker.stake(token, stakingApp, 10 ether);
        _fund(30 ether);
        vm.warp(block.timestamp + DURATION);

        // Act / Assert
        vm.expectRevert(EthTransferFailed.selector);
        staker.exit(stakingApp);
        assertEq(stakingApp.balances(address(staker)), 10 ether);
    }

    // -------------------------------------------------------------------------
    // exit branches
    // -------------------------------------------------------------------------

    function test_exit_withBalanceAndNoRewards_returnsOnlyTokens() external {
        // Arrange
        _stake(alice, 10 ether);

        // Act
        vm.prank(alice);
        stakingApp.exit();

        // Assert
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(alice.balance, 0);
    }

    function test_exit_afterFullWithdraw_stillPaysPendingRewards() external {
        // Arrange
        _stake(alice, 10 ether);
        _fund(30 ether);
        vm.warp(block.timestamp + DURATION);
        vm.prank(alice);
        stakingApp.withdraw(10 ether);
        uint256 pending = stakingApp.pendingRewards(alice);

        // Act
        vm.prank(alice);
        stakingApp.exit();

        // Assert
        assertGt(pending, 0);
        assertEq(alice.balance, pending);
        assertEq(stakingApp.pendingRewards(alice), 0);
    }

    function test_exit_emitsWithdrawnAndRewardPaid() external {
        // Arrange
        _stake(alice, 10 ether);
        _fund(30 ether);
        vm.warp(block.timestamp + DURATION);
        uint256 reward = stakingApp.earned(alice);
        vm.expectEmit(true, false, false, true);
        emit StakingApp.Withdrawn(alice, 10 ether);
        vm.expectEmit(true, false, false, true);
        emit StakingApp.RewardPaid(alice, reward);

        // Act
        vm.prank(alice);
        stakingApp.exit();
    }

    // -------------------------------------------------------------------------
    // pause
    // -------------------------------------------------------------------------

    function test_pause_byNonOwner_reverts() external {
        // Arrange / Act / Assert
        vm.prank(alice);
        vm.expectRevert();
        stakingApp.pause();
    }

    function test_pause_blocksStakeAndClaimButNotWithdrawOrExit() external {
        // Arrange
        _stake(alice, 10 ether);
        _fund(30 ether);
        vm.warp(block.timestamp + 1 days);
        vm.prank(owner);
        stakingApp.pause();
        _giveTokens(bob, 5 ether);

        // Act / Assert
        vm.startPrank(bob);
        token.approve(address(stakingApp), 5 ether);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakingApp.stake(5 ether);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        stakingApp.claimRewards();
        stakingApp.exit();
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 10 ether);
    }
}
