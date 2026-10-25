// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {StakingApp} from "../../src/StakingApp.sol";
import {StakingToken} from "../../src/StakingToken.sol";

/// @dev Shared deployment and helpers for the extended StakingApp test suites.
abstract contract StakingBase is Test {
    StakingToken internal token;
    StakingApp internal stakingApp;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant MIN_STAKE = 1 ether;
    uint256 internal constant DURATION = 30 days;

    function setUp() public virtual {
        token = new StakingToken("Staking Token", "STK", owner);
        stakingApp = new StakingApp(address(token), owner, MIN_STAKE, DURATION);
    }

    function _giveTokens(address user_, uint256 amount_) internal {
        vm.startPrank(owner);
        token.mint(amount_);
        assertTrue(token.transfer(user_, amount_));
        vm.stopPrank();
    }

    function _stake(address user_, uint256 amount_) internal {
        _giveTokens(user_, amount_);
        vm.startPrank(user_);
        token.approve(address(stakingApp), amount_);
        stakingApp.stake(amount_);
        vm.stopPrank();
    }

    function _fund(uint256 reward_) internal {
        vm.deal(owner, reward_);
        vm.prank(owner);
        stakingApp.notifyRewardAmount{value: reward_}(reward_);
    }
}
