# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
forge build                        # compile
forge test                         # run all tests (-vvv for traces)
forge test --match-test <name>     # run a single test
forge test --match-contract StakingAppFuzz  # run one suite
forge test --gas-report            # include gas breakdown
forge snapshot --check             # verify no gas regressions vs .gas-snapshot
forge fmt                          # format (CI enforces --check)
forge fmt --check                  # lint-only, no writes
```

**Deploy (requires Anvil or a live RPC):**
```bash
cp .env.example .env   # fill OWNER_ADDRESS, MIN_STAKING_AMOUNT, REWARDS_DURATION, RPC_URL, PRIVATE_KEY
source .env
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

CI runs: `forge fmt --check` → `forge build --sizes` → `forge test` (profile `ci`) → 95% line-coverage gate on `src/` (`forge coverage --no-match-coverage "script|test"`) → `forge snapshot --check` → Slither (`slither.config.json`).

## Architecture

Two contracts, one reward model:

- **`StakingToken`** (`src/StakingToken.sol`) — plain ERC20 (OZ v5) with a 1,000,000-token hard cap, `onlyOwner` mint, and a batch `distributeTokens` for airdrops.
- **`StakingApp`** (`src/StakingApp.sol`) — core protocol. Inherits `Ownable2Step`, `ReentrancyGuard`, `Pausable` (OZ v5). Uses `SafeERC20` for all token moves.

### Reward index (Synthetix model)

```
rewardPerTokenStored += rewardRate × Δt × 1e18 / totalSupply
earned(user) = balance[user] × (rewardPerToken − userRewardPerTokenPaid[user]) / 1e18
               + pendingRewards[user]
```

`updateReward(account)` — applied as a modifier before every state-changing function — snapshots the global index and flushes accrued rewards into `pendingRewards[account]` before any balance changes. This prevents reward manipulation across deposits and withdrawals.

`notifyRewardAmount()` (owner, payable) rolls over undistributed ETH from mid-period calls: `leftover = (periodFinish − now) × rewardRate`, then `rewardRate = (reward + leftover) / rewardsDuration`.

### Security invariants to preserve

- **CEI everywhere**: `withdraw`, `claimRewards`, and `exit` zero out state before any external call.
- **Pause scope**: `stake` and `claimRewards` are `whenNotPaused`; `withdraw` is intentionally unrestricted.
- `msg.value == reward_` enforced in `notifyRewardAmount` (`IncorrectRewardValue`) to prevent ETH accounting drift. Rewards that round the rate to zero revert with `RewardRateTooLow`.
- Rewards duration is bounded to `MIN_REWARDS_DURATION` (1 day) .. `MAX_REWARDS_DURATION` (365 days) in the constructor and `setRewardsDuration`.
- Rewards accrued while `totalSupply == 0` are not distributed (Synthetix behaviour); see `SECURITY.md`.

## Tests

Five suites in `test/` (shared setup in `test/utils/StakingBase.sol`):

| File | Type | Notes |
|---|---|---|
| `StakingAppTest.t.sol` | Unit | Happy path, reverts, access control, pause, reentrancy attacker |
| `StakingAppValidation.t.sol` | Unit | Constructor and duration bounds, reward rate checks, ETH payment failures, exit branches, pause scope |
| `StakingTokenTest.t.sol` | Unit | Mint, distribute, cap, access control |
| `StakingAppFuzz.t.sol` | Fuzz | 256 runs; stake bounds, reward proportionality, monotonicity, withdrawal limits |
| `StakingAppInvariant.t.sol` | Invariant | Handler drives 5 stakers; 256 sequences × 128k calls; token solvency, ETH solvency, monotonic `rewardPerToken`, `totalSupply` consistency |

The invariant handler (`StakingAppHandler`) is in the same file as the invariant test and is the only part of the test suite that uses `vm.deal` + `vm.prank` together to simulate owner funding.
