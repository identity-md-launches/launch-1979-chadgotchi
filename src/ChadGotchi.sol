// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ChadGotchi (CHAD)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, in the constructor, to the
///         deployer (`msg.sender`). Nothing can mint afterwards, nothing can burn on behalf of a
///         holder, and there is no owner, pauser, blocklist, tax or hook of any kind: every
///         transfer moves exactly the amount asked for.
/// @dev The contract has no constructor arguments and holds no privileged roles. On the IdentityMD
///      launch `msg.sender` is the ProjectFactory, which then distributes the supply (swarm share,
///      pool seed, requester remainder) itself.
contract ChadGotchi is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "ChadGotchi";

    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "CHAD";

    /// @notice Decimals: the ERC-20 default of 18.
    uint8 public constant DECIMALS = 18;

    /// @notice Whole-token supply before scaling by decimals: one billion.
    uint256 public constant SUPPLY_WHOLE_TOKENS = 1_000_000_000;

    /// @notice The fixed total supply in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = SUPPLY_WHOLE_TOKENS * 10 ** DECIMALS;

    /// @notice Emitted once, in the constructor, recording who received the whole supply.
    /// @param recipient The deployer that received `amount`.
    /// @param amount The fixed total supply in minor units.
    event SupplyMinted(address indexed recipient, uint256 amount);

    /// @notice Mints the entire fixed supply to the deployer. Runs once; nothing else can mint.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
