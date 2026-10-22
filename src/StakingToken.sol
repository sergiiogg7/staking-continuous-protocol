// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Thrown when a mint would exceed the maximum token supply.
/// @param available Remaining mintable supply at the time of the call.
/// @param requested The amount the owner attempted to mint.
error MaxSupplyExceeded(uint256 available, uint256 requested);

/// @notice Thrown when the recipients and amounts arrays have different lengths in `distributeTokens`.
/// @param recipientsLength Length of the recipients array.
/// @param amountsLength Length of the amounts array.
error LengthMismatch(uint256 recipientsLength, uint256 amountsLength);

/// @notice Thrown when a recipient address in `distributeTokens` is the zero address.
/// @param index Index of the invalid entry in the recipients array.
error InvalidRecipient(uint256 index);

/// @title StakingToken
/// @notice Mintable ERC20 token used as the staking asset in StakingApp.
/// @dev Supply is hard-capped at MAX_SUPPLY. Only the owner can mint or distribute tokens.
contract StakingToken is ERC20, Ownable {
    /// @notice Hard cap on the total token supply (1,000,000 tokens with 18 decimals).
    uint256 public constant MAX_SUPPLY = 1_000_000 * 1e18;

    /// @notice Deploys the token with the given name, symbol, and initial owner.
    /// @param name_ ERC20 token name.
    /// @param symbol_ ERC20 token symbol.
    /// @param owner_ Address that will own this contract and receive minting rights.
    constructor(string memory name_, string memory symbol_, address owner_) ERC20(name_, symbol_) Ownable(owner_) {}

    /// @notice Mints `amount_` tokens to the owner's address.
    /// @dev Reverts with {MaxSupplyExceeded} if minting would push total supply past `MAX_SUPPLY`.
    /// @param amount_ Number of tokens to mint (in wei, 18 decimals).
    function mint(uint256 amount_) external onlyOwner {
        uint256 available = MAX_SUPPLY - totalSupply();
        if (amount_ > available) revert MaxSupplyExceeded(available, amount_);
        _mint(msg.sender, amount_);
    }

    /// @notice Transfers tokens from the owner to multiple recipients in a single transaction.
    /// @dev Reverts with {LengthMismatch} if array lengths differ.
    ///      Reverts with {InvalidRecipient} if any recipient is the zero address.
    /// @param recipients_ Array of recipient addresses.
    /// @param amounts_ Array of token amounts corresponding to each recipient (in wei, 18 decimals).
    function distributeTokens(address[] calldata recipients_, uint256[] calldata amounts_) external onlyOwner {
        if (recipients_.length != amounts_.length) revert LengthMismatch(recipients_.length, amounts_.length);
        for (uint256 i = 0; i < recipients_.length; i++) {
            if (recipients_[i] == address(0)) revert InvalidRecipient(i);
            _transfer(msg.sender, recipients_[i], amounts_[i]);
        }
    }
}
