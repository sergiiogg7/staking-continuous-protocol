// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/StakingApp.sol";
import "../src/StakingToken.sol";

contract StakingAppHandler is Test {
    StakingToken public stakingToken;
    StakingApp public stakingApp;
    address public owner;

    address[5] public stakers;

    uint256 public totalDeposited;
    uint256 public totalRewardsFunded;
    uint256 public totalRewardsClaimed;
    uint256 public lastRewardPerToken;

    constructor(StakingToken stakingToken_, StakingApp stakingApp_, address owner_) {
        stakingToken = stakingToken_;
        stakingApp = stakingApp_;
        owner = owner_;

        for (uint256 i = 0; i < 5; i++) {
            stakers[i] = vm.addr(100 + i);
        }
    }

    function stake(uint256 stakerIndex_, uint256 amount_) external {
        stakerIndex_ = bound(stakerIndex_, 0, 4);
        amount_ = bound(amount_, stakingApp.minStakingAmount(), 10e18);

        address staker = stakers[stakerIndex_];

        vm.startPrank(owner);
        stakingToken.mint(amount_);
        stakingToken.transfer(staker, amount_);
        vm.stopPrank();

        vm.startPrank(staker);
        stakingToken.approve(address(stakingApp), amount_);
        stakingApp.stake(amount_);
        vm.stopPrank();

        totalDeposited += amount_;

        uint256 current = stakingApp.rewardPerToken();
        if (current >= lastRewardPerToken) lastRewardPerToken = current;
    }

    function withdraw(uint256 stakerIndex_, uint256 amount_) external {
        stakerIndex_ = bound(stakerIndex_, 0, 4);
        address staker = stakers[stakerIndex_];
        uint256 balance = stakingApp.balances(staker);
        if (balance == 0) return;

        amount_ = bound(amount_, 1, balance);

        vm.prank(staker);
        stakingApp.withdraw(amount_);

        totalDeposited -= amount_;

        uint256 current = stakingApp.rewardPerToken();
        if (current >= lastRewardPerToken) lastRewardPerToken = current;
    }

    function claimRewards(uint256 stakerIndex_) external {
        stakerIndex_ = bound(stakerIndex_, 0, 4);
        address staker = stakers[stakerIndex_];
        uint256 earnedAmount = stakingApp.earned(staker);
        if (earnedAmount == 0) return;

        vm.prank(staker);
        stakingApp.claimRewards();

        totalRewardsClaimed += earnedAmount;

        uint256 current = stakingApp.rewardPerToken();
        if (current >= lastRewardPerToken) lastRewardPerToken = current;
    }

    function notifyRewardAmount(uint256 reward_) external {
        reward_ = bound(reward_, 0.001 ether, 10 ether);
        vm.deal(owner, reward_);
        vm.prank(owner);
        stakingApp.notifyRewardAmount{value: reward_}(reward_);
        totalRewardsFunded += reward_;
    }

    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 30 days);
        vm.warp(block.timestamp + seconds_);
    }

    function sumAllEarned() external view returns (uint256 total) {
        for (uint256 i = 0; i < 5; i++) {
            total += stakingApp.earned(stakers[i]);
        }
    }
}

contract StakingAppInvariant is Test {
    StakingToken internal token;
    StakingApp internal stakingApp;
    StakingAppHandler internal handler;

    address internal owner = vm.addr(1);
    uint256 internal minStakingAmount_ = 1e18;
    uint256 internal rewardsDuration_ = 30 days;

    function setUp() public {
        token = new StakingToken("Staking Token", "STK", owner);
        stakingApp = new StakingApp(address(token), owner, minStakingAmount_, rewardsDuration_);
        handler = new StakingAppHandler(token, stakingApp, owner);

        targetContract(address(handler));
    }

    // Token solvency: contract always holds >= all active stakes
    function invariant_tokenBalanceCoversTotalDeposited() external view {
        assertGe(token.balanceOf(address(stakingApp)), handler.totalDeposited());
    }

    // ETH solvency: contract ETH >= all accrued rewards for active stakers
    function invariant_ethBalanceCoversAccruedRewards() external view {
        assertGe(address(stakingApp).balance, handler.sumAllEarned());
    }

    // rewardPerToken never decreases
    function invariant_rewardPerTokenMonotonic() external view {
        assertGe(stakingApp.rewardPerToken(), handler.lastRewardPerToken());
    }

    // totalSupply always matches sum of individual balances tracked by handler
    function invariant_totalSupplyConsistent() external view {
        uint256 sum;
        address[5] memory stakers;
        for (uint256 i = 0; i < 5; i++) {
            stakers[i] = vm.addr(100 + i);
            sum += stakingApp.balances(stakers[i]);
        }
        assertEq(stakingApp.totalSupply(), sum);
    }
}
