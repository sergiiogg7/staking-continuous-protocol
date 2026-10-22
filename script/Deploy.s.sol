// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import "../src/StakingToken.sol";
import "../src/StakingApp.sol";

contract DeployScript is Script {
    function run() external {
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 minStakingAmount = vm.envUint("MIN_STAKING_AMOUNT");
        uint256 rewardsDuration = vm.envUint("REWARDS_DURATION");

        vm.startBroadcast();

        StakingToken token = new StakingToken("Staking Token", "STK", owner);
        StakingApp app = new StakingApp(address(token), owner, minStakingAmount, rewardsDuration);

        vm.stopBroadcast();

        console.log("StakingToken:", address(token));
        console.log("StakingApp:  ", address(app));
    }
}
