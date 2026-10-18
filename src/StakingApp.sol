// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/// @notice Thrown when a stake amount is below the required minimum.
/// @param minimum The minimum stake amount.
/// @param provided The amount the caller attempted to stake.
error BelowMinimumStake(uint256 minimum, uint256 provided);

/// @notice Thrown when a withdrawal amount exceeds the caller's staked balance.
/// @param balance The caller's current staked balance.
/// @param requested The amount the caller attempted to withdraw.
error InsufficientBalance(uint256 balance, uint256 requested);

/// @notice Thrown when a user tries to claim with no accrued rewards.
error NothingToClaim();

/// @notice Thrown when `setRewardsDuration` is called while a reward period is still active.
error RewardsDurationNotFinished();

/// @notice Thrown when a zero amount is passed to stake or withdraw.
error ZeroAmount();

/// @notice Thrown when the ETH transfer to the staker fails.
error EthTransferFailed();

/// @title StakingApp
/// @notice Continuous proportional ERC20 staking contract that rewards stakers with ETH.
/// @dev Implements the Synthetix StakingRewards model with ETH as the reward token.
///      Reward accrual is proportional to each user's share of total staked supply.
///      Inherits Ownable2Step, ReentrancyGuard, and Pausable from OpenZeppelin v5.
contract StakingApp is Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice The ERC20 token accepted for staking.
    IERC20 public immutable stakingToken;

    /// @notice Duration in seconds of each reward distribution period.
    uint256 public rewardsDuration;

    /// @notice Timestamp at which the current reward period ends.
    uint256 public periodFinish;

    /// @notice ETH distributed per second across all stakers during an active period.
    uint256 public rewardRate;

    /// @notice Last timestamp at which `rewardPerTokenStored` was updated.
    uint256 public lastUpdateTime;

    /// @notice Cumulative ETH earned per token staked, scaled by 1e18.
    uint256 public rewardPerTokenStored;

    /// @notice Total tokens currently staked across all users.
    uint256 public totalSupply;

    /// @notice Minimum token amount required per stake call.
    uint256 public minStakingAmount;

    /// @notice Token balance staked by each user.
    mapping(address => uint256) public balances;

    /// @notice Snapshot of `rewardPerTokenStored` at the time of each user's last interaction.
    mapping(address => uint256) public userRewardPerTokenPaid;

    /// @notice Accrued but unclaimed ETH rewards for each user.
    mapping(address => uint256) public pendingRewards;

    /// @notice Emitted when a user stakes tokens.
    /// @param user The address of the staker.
    /// @param amount The amount of tokens staked.
    event Staked(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws staked tokens.
    /// @param user The address of the withdrawer.
    /// @param amount The amount of tokens withdrawn.
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when a user claims ETH rewards.
    /// @param user The address of the claimer.
    /// @param reward The ETH amount paid.
    event RewardPaid(address indexed user, uint256 reward);

    /// @notice Emitted when the owner funds a new reward period.
    /// @param reward The ETH amount added.
    event RewardAdded(uint256 reward);

    /// @notice Emitted when the owner updates the minimum staking amount.
    /// @param newAmount The new minimum in token units.
    event MinStakingAmountChanged(uint256 newAmount);

    /// @notice Emitted when the owner updates the rewards duration.
    /// @param newDuration The new duration in seconds.
    event RewardsDurationChanged(uint256 newDuration);

    /// @notice Deploys the staking contract.
    /// @param stakingToken_ Address of the ERC20 token accepted for staking.
    /// @param owner_ Address that will own and manage this contract.
    /// @param minStakingAmount_ Minimum token amount per stake call.
    /// @param rewardsDuration_ Duration in seconds of each reward period.
    constructor(address stakingToken_, address owner_, uint256 minStakingAmount_, uint256 rewardsDuration_)
        Ownable(owner_)
    {
        stakingToken = IERC20(stakingToken_);
        minStakingAmount = minStakingAmount_;
        rewardsDuration = rewardsDuration_;
    }

    /// @dev Updates the global reward index and the caller's accrued rewards before execution.
    modifier updateReward(address account_) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account_ != address(0)) {
            pendingRewards[account_] = earned(account_);
            userRewardPerTokenPaid[account_] = rewardPerTokenStored;
        }
        _;
    }

    /// @notice Pauses deposits and reward claims. Withdrawals remain available.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, re-enabling deposits and reward claims.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Returns the effective timestamp for reward accrual (capped at period end).
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice Returns the cumulative ETH earned per token staked, scaled by 1e18.
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) return rewardPerTokenStored;
        return rewardPerTokenStored
            + (rewardRate * (lastTimeRewardApplicable() - lastUpdateTime) * 1e18) / totalSupply;
    }

    /// @notice Returns the total accrued but unclaimed ETH rewards for `account_`.
    /// @param account_ The address to query.
    function earned(address account_) public view returns (uint256) {
        return (balances[account_] * (rewardPerToken() - userRewardPerTokenPaid[account_])) / 1e18
            + pendingRewards[account_];
    }

    /// @notice Stakes `amount_` tokens into the contract.
    /// @dev Caller must approve this contract for at least `amount_` before calling.
    ///      Multiple calls accumulate into a single position. Paused when contract is paused.
    /// @param amount_ Token amount to stake. Must be >= `minStakingAmount`.
    function stake(uint256 amount_) external nonReentrant whenNotPaused updateReward(msg.sender) {
        if (amount_ == 0) revert ZeroAmount();
        if (amount_ < minStakingAmount) revert BelowMinimumStake(minStakingAmount, amount_);

        totalSupply += amount_;
        balances[msg.sender] += amount_;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount_);

        emit Staked(msg.sender, amount_);
    }

    /// @notice Withdraws `amount_` staked tokens back to the caller.
    /// @dev Always available, even when the contract is paused.
    ///      Follows CEI: state updated before external transfer.
    /// @param amount_ Token amount to withdraw. Must not exceed the caller's staked balance.
    function withdraw(uint256 amount_) external nonReentrant updateReward(msg.sender) {
        if (amount_ == 0) revert ZeroAmount();
        if (amount_ > balances[msg.sender]) revert InsufficientBalance(balances[msg.sender], amount_);

        totalSupply -= amount_;
        balances[msg.sender] -= amount_;
        stakingToken.safeTransfer(msg.sender, amount_);

        emit Withdrawn(msg.sender, amount_);
    }

    /// @notice Claims all accrued ETH rewards for the caller.
    /// @dev Resets `pendingRewards` to zero before the ETH transfer (CEI).
    function claimRewards() external nonReentrant whenNotPaused updateReward(msg.sender) {
        uint256 reward = pendingRewards[msg.sender];
        if (reward == 0) revert NothingToClaim();

        pendingRewards[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: reward}("");
        if (!success) revert EthTransferFailed();

        emit RewardPaid(msg.sender, reward);
    }

    /// @notice Withdraws all staked tokens and claims all accrued ETH rewards in a single transaction.
    function exit() external nonReentrant updateReward(msg.sender) {
        uint256 balance = balances[msg.sender];
        uint256 reward = pendingRewards[msg.sender];

        if (balance > 0) {
            totalSupply -= balance;
            balances[msg.sender] = 0;
            stakingToken.safeTransfer(msg.sender, balance);
            emit Withdrawn(msg.sender, balance);
        }

        if (reward > 0) {
            pendingRewards[msg.sender] = 0;
            (bool success,) = msg.sender.call{value: reward}("");
            if (!success) revert EthTransferFailed();
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Funds the contract with ETH and activates a new reward period.
    /// @dev If called mid-period, remaining undistributed ETH is rolled into the new rate.
    ///      `msg.value` must equal `reward_` to prevent accounting drift.
    /// @param reward_ ETH amount to distribute over `rewardsDuration` seconds.
    function notifyRewardAmount(uint256 reward_) external payable onlyOwner updateReward(address(0)) {
        require(msg.value == reward_, "msg.value != reward_");

        if (block.timestamp < periodFinish) {
            uint256 leftover = (periodFinish - block.timestamp) * rewardRate;
            rewardRate = (reward_ + leftover) / rewardsDuration;
        } else {
            rewardRate = reward_ / rewardsDuration;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        emit RewardAdded(reward_);
    }

    /// @notice Updates the minimum token amount required per stake call.
    /// @param amount_ New minimum in token units.
    function setMinStakingAmount(uint256 amount_) external onlyOwner {
        minStakingAmount = amount_;
        emit MinStakingAmountChanged(amount_);
    }

    /// @notice Updates the rewards period duration.
    /// @dev Can only be called after the current reward period has ended to avoid
    ///      breaking the in-flight rate calculation.
    /// @param duration_ New duration in seconds.
    function setRewardsDuration(uint256 duration_) external onlyOwner {
        if (block.timestamp < periodFinish) revert RewardsDurationNotFinished();
        rewardsDuration = duration_;
        emit RewardsDurationChanged(duration_);
    }
}
