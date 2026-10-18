// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/StakingToken.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MaxSupplyExceeded, LengthMismatch, InvalidRecipient} from "../src/StakingToken.sol";

contract StakingTokenTest is Test {
    StakingToken stakingToken;
    string name_ = "Staking Token";
    string symbol_ = "STK";
    address owner_ = vm.addr(1);
    address randomUser = vm.addr(2);
    address user2 = vm.addr(3);
    address user3 = vm.addr(4);

    function setUp() public {
        stakingToken = new StakingToken(name_, symbol_, owner_);
    }

    function testStakingTokenMintsCorrectly() public {
        vm.startPrank(owner_);
        uint256 amount = 1 ether;

        uint256 balanceBefore_ = IERC20(address(stakingToken)).balanceOf(owner_);
        stakingToken.mint(amount);
        uint256 balanceAfter_ = IERC20(address(stakingToken)).balanceOf(owner_);

        assert(balanceAfter_ - balanceBefore_ == amount);

        vm.stopPrank();
    }

    function testMintShouldRevertForNonOwner() public {
        vm.startPrank(randomUser);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomUser));
        stakingToken.mint(1 ether);

        vm.stopPrank();
    }

    function testMintShouldRevertWhenExceedingMaxSupply() public {
        vm.startPrank(owner_);

        uint256 available = StakingToken(stakingToken).MAX_SUPPLY() - stakingToken.totalSupply();
        vm.expectRevert(abi.encodeWithSelector(MaxSupplyExceeded.selector, available, available + 1));
        stakingToken.mint(available + 1);

        vm.stopPrank();
    }

    function testDistributeTokensCorrectly() public {
        vm.startPrank(owner_);
        uint256 totalToDistribute = 1 ether + 2 ether + 3 ether;
        stakingToken.mint(totalToDistribute);

        address[] memory recipients = new address[](3);
        recipients[0] = randomUser;
        recipients[1] = user2;
        recipients[2] = user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        uint256 ownerBalanceBefore = stakingToken.balanceOf(owner_);
        stakingToken.distributeTokens(recipients, amounts);

        assert(stakingToken.balanceOf(randomUser) == 1 ether);
        assert(stakingToken.balanceOf(user2) == 2 ether);
        assert(stakingToken.balanceOf(user3) == 3 ether);
        assert(stakingToken.balanceOf(owner_) == ownerBalanceBefore - totalToDistribute);

        vm.stopPrank();
    }

    function testDistributeShouldRevertForNonOwner() public {
        vm.startPrank(randomUser);

        address[] memory recipients = new address[](1);
        recipients[0] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", randomUser));
        stakingToken.distributeTokens(recipients, amounts);

        vm.stopPrank();
    }

    function testDistributeShouldRevertOnLengthMismatch() public {
        vm.startPrank(owner_);

        address[] memory recipients = new address[](2);
        recipients[0] = randomUser;
        recipients[1] = user2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(LengthMismatch.selector, 2, 1));
        stakingToken.distributeTokens(recipients, amounts);

        vm.stopPrank();
    }

    function testDistributeShouldRevertOnInvalidRecipient() public {
        vm.startPrank(owner_);

        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(InvalidRecipient.selector, 0));
        stakingToken.distributeTokens(recipients, amounts);

        vm.stopPrank();
    }

    function testDistributeShouldRevertOnInsufficientBalance() public {
        vm.startPrank(owner_);

        address[] memory recipients = new address[](1);
        recipients[0] = randomUser;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.expectRevert(
            abi.encodeWithSignature("ERC20InsufficientBalance(address,uint256,uint256)", owner_, 0, 1 ether)
        );
        stakingToken.distributeTokens(recipients, amounts);

        vm.stopPrank();
    }
}
