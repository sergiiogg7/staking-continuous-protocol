// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StakingApp} from "../../src/StakingApp.sol";
import {StakingToken} from "../../src/StakingToken.sol";

/// @dev Staker contract that cannot receive ETH, so reward payments to it fail.
contract NoReceiveStaker {
    function stake(StakingToken token_, StakingApp app_, uint256 amount_) external {
        token_.approve(address(app_), amount_);
        app_.stake(amount_);
    }

    function claim(StakingApp app_) external {
        app_.claimRewards();
    }

    function exit(StakingApp app_) external {
        app_.exit();
    }
}
