# Security

## Status

This repository has not been externally audited. Do not use it with real funds without an independent review.

## Assumptions and known limits

- Rewards accrue per second to the current stakers. While the pool is empty (`totalSupply == 0`) during an active period, that portion of the rewards is not distributed and stays in the contract. There is no recovery function.
- Integer division in the reward rate can leave up to `rewardsDuration` wei of dust undistributed per period.
- `notifyRewardAmount` rolls over the undistributed part of an active period into the new rate. The owner controls when and how much to fund.
- The owner can pause staking and claims, but never withdrawals or `exit`. The owner cannot move staked tokens or accrued rewards.
- The staking token is assumed to be a standard ERC-20. Fee-on-transfer and rebasing tokens would break the accounting.
- A staker contract that cannot receive ETH cannot claim rewards, but can still withdraw its tokens with `withdraw`.

## Invariants

- The contract holds at least the sum of all staked tokens.
- The ETH balance covers all unclaimed rewards.
- `rewardPerToken` never decreases.
- `totalSupply` equals the sum of user balances.

## Reporting a vulnerability

Open a private security advisory on the GitHub repository. Do not open a public issue.
