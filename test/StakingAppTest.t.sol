// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/StakingApp.sol";
import "../src/StakingToken.sol";

contract StakingAppTest is Test {
    StakingToken internal token;
    StakingApp internal stakingApp;

    address internal owner = vm.addr(1);
    address internal user1 = vm.addr(2);
    address internal user2 = vm.addr(3);
    address internal newOwner = vm.addr(4);

    uint256 internal minStakingAmount_ = 1e18;
    uint256 internal rewardsDuration_ = 30 days;

    function setUp() public {
        token = new StakingToken("Staking Token", "STK", owner);
        stakingApp = new StakingApp(address(token), owner, minStakingAmount_, rewardsDuration_);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _mintAndApprove(address user_, uint256 amount_) internal {
        vm.startPrank(owner);
        token.mint(amount_);
        token.transfer(user_, amount_);
        vm.stopPrank();
        vm.prank(user_);
        token.approve(address(stakingApp), amount_);
    }

    function _stake(address user_, uint256 amount_) internal {
        _mintAndApprove(user_, amount_);
        vm.prank(user_);
        stakingApp.stake(amount_);
    }

    function _fundRewards(uint256 ethAmount_) internal {
        vm.deal(owner, ethAmount_);
        vm.prank(owner);
        stakingApp.notifyRewardAmount{value: ethAmount_}(ethAmount_);
    }

    // ─── stake() ──────────────────────────────────────────────────────────────

    function test_stake_success() public {
        _mintAndApprove(user1, minStakingAmount_);

        vm.expectEmit(true, false, false, true);
        emit StakingApp.Staked(user1, minStakingAmount_);

        vm.prank(user1);
        stakingApp.stake(minStakingAmount_);

        assertEq(stakingApp.balances(user1), minStakingAmount_);
        assertEq(stakingApp.totalSupply(), minStakingAmount_);
        assertEq(token.balanceOf(address(stakingApp)), minStakingAmount_);
    }

    function test_stake_zero_reverts() public {
        vm.prank(user1);
        vm.expectRevert(ZeroAmount.selector);
        stakingApp.stake(0);
    }

    function test_stake_belowMinimum_reverts() public {
        uint256 below = minStakingAmount_ - 1;
        _mintAndApprove(user1, below);

        vm.expectRevert(abi.encodeWithSelector(BelowMinimumStake.selector, minStakingAmount_, below));
        vm.prank(user1);
        stakingApp.stake(below);
    }

    function test_stake_accumulates() public {
        _stake(user1, minStakingAmount_);
        _mintAndApprove(user1, minStakingAmount_);

        vm.prank(user1);
        stakingApp.stake(minStakingAmount_);

        assertEq(stakingApp.balances(user1), 2 * minStakingAmount_);
        assertEq(stakingApp.totalSupply(), 2 * minStakingAmount_);
    }

    function test_stake_whenPaused_reverts() public {
        vm.prank(owner);
        stakingApp.pause();

        _mintAndApprove(user1, minStakingAmount_);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(user1);
        stakingApp.stake(minStakingAmount_);
    }

    // ─── withdraw() ───────────────────────────────────────────────────────────

    function test_withdraw_full() public {
        _stake(user1, minStakingAmount_);

        vm.expectEmit(true, false, false, true);
        emit StakingApp.Withdrawn(user1, minStakingAmount_);

        vm.prank(user1);
        stakingApp.withdraw(minStakingAmount_);

        assertEq(stakingApp.balances(user1), 0);
        assertEq(stakingApp.totalSupply(), 0);
        assertEq(token.balanceOf(user1), minStakingAmount_);
    }

    function test_withdraw_partial() public {
        uint256 stakeAmount = 3 * minStakingAmount_;
        uint256 withdrawAmount = minStakingAmount_;
        _stake(user1, stakeAmount);

        vm.prank(user1);
        stakingApp.withdraw(withdrawAmount);

        assertEq(stakingApp.balances(user1), stakeAmount - withdrawAmount);
        assertEq(stakingApp.totalSupply(), stakeAmount - withdrawAmount);
        assertEq(token.balanceOf(user1), withdrawAmount);
    }

    function test_withdraw_zero_reverts() public {
        vm.prank(user1);
        vm.expectRevert(ZeroAmount.selector);
        stakingApp.withdraw(0);
    }

    function test_withdraw_moreThanBalance_reverts() public {
        _stake(user1, minStakingAmount_);

        uint256 excess = minStakingAmount_ + 1;
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, minStakingAmount_, excess));
        vm.prank(user1);
        stakingApp.withdraw(excess);
    }

    function test_withdraw_whenPaused_succeeds() public {
        _stake(user1, minStakingAmount_);

        vm.prank(owner);
        stakingApp.pause();

        vm.prank(user1);
        stakingApp.withdraw(minStakingAmount_);

        assertEq(stakingApp.balances(user1), 0);
        assertEq(token.balanceOf(user1), minStakingAmount_);
    }

    // ─── claimRewards() ───────────────────────────────────────────────────────

    function test_claimRewards_afterTime() public {
        _stake(user1, minStakingAmount_);
        _fundRewards(1 ether);

        vm.warp(block.timestamp + rewardsDuration_);

        uint256 expectedReward = stakingApp.earned(user1);
        assertTrue(expectedReward > 0);

        vm.expectEmit(true, false, false, true);
        emit StakingApp.RewardPaid(user1, expectedReward);

        vm.prank(user1);
        stakingApp.claimRewards();

        assertEq(stakingApp.pendingRewards(user1), 0);
        // Tolerance = rewardsDuration_ wei: max integer division loss from rewardRate = reward / duration
        assertApproxEqAbs(user1.balance, 1 ether, rewardsDuration_);
    }

    function test_claimRewards_proportional() public {
        _stake(user1, minStakingAmount_);
        _stake(user2, minStakingAmount_);
        _fundRewards(1 ether);

        vm.warp(block.timestamp + rewardsDuration_);

        uint256 earned1 = stakingApp.earned(user1);
        uint256 earned2 = stakingApp.earned(user2);

        // Each user gets ~50% of total rewards (tolerance = rewardsDuration_ wei from integer division)
        assertApproxEqAbs(earned1, 0.5 ether, rewardsDuration_);
        assertApproxEqAbs(earned2, 0.5 ether, rewardsDuration_);
        assertApproxEqAbs(earned1 + earned2, 1 ether, rewardsDuration_);
    }

    function test_claimRewards_nothingToClaim_reverts() public {
        vm.expectRevert(NothingToClaim.selector);
        vm.prank(user1);
        stakingApp.claimRewards();
    }

    function test_claimRewards_whenPaused_reverts() public {
        _stake(user1, minStakingAmount_);
        _fundRewards(1 ether);
        vm.warp(block.timestamp + rewardsDuration_);

        vm.prank(owner);
        stakingApp.pause();

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(user1);
        stakingApp.claimRewards();
    }

    function test_claimRewards_reentrancy_blocked() public {
        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(stakingApp)));

        _mintAndApprove(address(attacker), minStakingAmount_);
        attacker.deposit(minStakingAmount_);

        _fundRewards(1 ether);
        vm.warp(block.timestamp + rewardsDuration_);

        attacker.claim();

        assertEq(
            attacker.lastRevertReason(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
        );
    }

    // ─── exit() ───────────────────────────────────────────────────────────────

    function test_exit_withdrawsAndClaims() public {
        _stake(user1, minStakingAmount_);
        _fundRewards(1 ether);
        vm.warp(block.timestamp + rewardsDuration_);

        vm.prank(user1);
        stakingApp.exit();

        assertEq(stakingApp.balances(user1), 0);
        assertEq(stakingApp.pendingRewards(user1), 0);
        assertEq(token.balanceOf(user1), minStakingAmount_);
        assertApproxEqAbs(user1.balance, 1 ether, rewardsDuration_);
    }

    function test_exit_noBalance_noRewards_noRevert() public {
        vm.prank(user1);
        stakingApp.exit();

        assertEq(stakingApp.balances(user1), 0);
        assertEq(user1.balance, 0);
    }

    // ─── notifyRewardAmount() ─────────────────────────────────────────────────

    function test_notifyRewardAmount_setsRate() public {
        _fundRewards(1 ether);

        uint256 expectedRate = 1 ether / rewardsDuration_;
        assertEq(stakingApp.rewardRate(), expectedRate);
        assertEq(stakingApp.periodFinish(), block.timestamp + rewardsDuration_);
    }

    function test_notifyRewardAmount_midPeriod_carriesLeftover() public {
        _fundRewards(1 ether);

        uint256 halfPeriod = rewardsDuration_ / 2;
        vm.warp(block.timestamp + halfPeriod);

        uint256 leftover = halfPeriod * stakingApp.rewardRate();
        uint256 newReward = 1 ether;
        uint256 expectedRate = (newReward + leftover) / rewardsDuration_;

        vm.deal(owner, newReward);
        vm.prank(owner);
        stakingApp.notifyRewardAmount{value: newReward}(newReward);

        assertEq(stakingApp.rewardRate(), expectedRate);
    }

    function test_notifyRewardAmount_nonOwner_reverts() public {
        vm.deal(user1, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        stakingApp.notifyRewardAmount{value: 1 ether}(1 ether);
    }

    function test_notifyRewardAmount_valueMismatch_reverts() public {
        vm.deal(owner, 2 ether);
        vm.expectRevert("msg.value != reward_");
        vm.prank(owner);
        stakingApp.notifyRewardAmount{value: 2 ether}(1 ether);
    }

    // ─── setRewardsDuration() ─────────────────────────────────────────────────

    function test_setRewardsDuration_success() public {
        uint256 newDuration = 60 days;

        vm.expectEmit(false, false, false, true);
        emit StakingApp.RewardsDurationChanged(newDuration);

        vm.prank(owner);
        stakingApp.setRewardsDuration(newDuration);

        assertEq(stakingApp.rewardsDuration(), newDuration);
    }

    function test_setRewardsDuration_midPeriod_reverts() public {
        _fundRewards(1 ether);

        vm.expectRevert(RewardsDurationNotFinished.selector);
        vm.prank(owner);
        stakingApp.setRewardsDuration(60 days);
    }

    function test_setRewardsDuration_nonOwner_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        stakingApp.setRewardsDuration(60 days);
    }

    // ─── setMinStakingAmount() ────────────────────────────────────────────────

    function test_setMinStakingAmount_success() public {
        uint256 newMin = 2e18;

        vm.expectEmit(false, false, false, true);
        emit StakingApp.MinStakingAmountChanged(newMin);

        vm.prank(owner);
        stakingApp.setMinStakingAmount(newMin);

        assertEq(stakingApp.minStakingAmount(), newMin);
    }

    function test_setMinStakingAmount_nonOwner_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        stakingApp.setMinStakingAmount(2e18);
    }

    // ─── earned() / rewardPerToken() ─────────────────────────────────────────

    function test_earned_zeroBeforeRewardPeriod() public {
        _stake(user1, minStakingAmount_);
        assertEq(stakingApp.earned(user1), 0);
    }

    function test_earned_correctAccrual() public {
        _stake(user1, minStakingAmount_);
        _fundRewards(1 ether);

        uint256 halfPeriod = rewardsDuration_ / 2;
        vm.warp(block.timestamp + halfPeriod);

        uint256 earnedHalf = stakingApp.earned(user1);
        assertApproxEqAbs(earnedHalf, 0.5 ether, rewardsDuration_);

        vm.warp(block.timestamp + halfPeriod);

        uint256 earnedFull = stakingApp.earned(user1);
        assertApproxEqAbs(earnedFull, 1 ether, rewardsDuration_);
    }

    function test_earned_stopsAccruingAfterPeriodFinish() public {
        _stake(user1, minStakingAmount_);
        _fundRewards(1 ether);

        vm.warp(block.timestamp + rewardsDuration_);
        uint256 earnedAtEnd = stakingApp.earned(user1);

        vm.warp(block.timestamp + 100 days);
        uint256 earnedLater = stakingApp.earned(user1);

        assertEq(earnedAtEnd, earnedLater);
    }

    // ─── Pausable ────────────────────────────────────────────────────────────

    function test_unpause_restoresStake() public {
        vm.prank(owner);
        stakingApp.pause();

        vm.prank(owner);
        stakingApp.unpause();

        _mintAndApprove(user1, minStakingAmount_);
        vm.prank(user1);
        stakingApp.stake(minStakingAmount_);

        assertEq(stakingApp.balances(user1), minStakingAmount_);
    }

    function test_unpause_nonOwner_reverts() public {
        vm.prank(owner);
        stakingApp.pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        stakingApp.unpause();
    }

    // ─── Ownership (Ownable2Step) ─────────────────────────────────────────────

    function test_transferOwnership_twoStep() public {
        vm.prank(owner);
        stakingApp.transferOwnership(newOwner);

        assertEq(stakingApp.owner(), owner);
        assertEq(stakingApp.pendingOwner(), newOwner);
    }

    function test_acceptOwnership_success() public {
        vm.prank(owner);
        stakingApp.transferOwnership(newOwner);

        vm.prank(newOwner);
        stakingApp.acceptOwnership();

        assertEq(stakingApp.owner(), newOwner);
        assertEq(stakingApp.pendingOwner(), address(0));
    }

    function test_acceptOwnership_nonPending_reverts() public {
        vm.prank(owner);
        stakingApp.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        stakingApp.acceptOwnership();
    }

    function test_transferOwnership_nonOwner_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        vm.prank(user1);
        stakingApp.transferOwnership(newOwner);
    }
}

// ─── Reentrancy attacker ──────────────────────────────────────────────────────

contract ReentrantAttacker {
    StakingApp public stakingApp;
    bytes public lastRevertReason;

    constructor(address payable stakingApp_) {
        stakingApp = StakingApp(stakingApp_);
    }

    function deposit(uint256 amount_) external {
        IERC20(address(stakingApp.stakingToken())).approve(address(stakingApp), amount_);
        stakingApp.stake(amount_);
    }

    function claim() external {
        stakingApp.claimRewards();
    }

    receive() external payable {
        try stakingApp.claimRewards() {} catch (bytes memory reason) {
            lastRevertReason = reason;
        }
    }
}
