// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ChadGotchi} from "../src/ChadGotchi.sol";

/// @notice Drives the token with random transfers, approvals and transferFroms among a fixed set of
///         actors (plus the deployer), including calls that must fail. Ghost state records what
///         every balance and allowance should be, independently of the token's own bookkeeping.
contract ChadGotchiHandler is Test {
    ChadGotchi public immutable token;
    address[] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public calls;
    uint256 public successfulMoves;
    uint256 public expectedReverts;
    uint256 public unexpectedOutcomes;

    constructor(ChadGotchi token_, address deployer) {
        token = token_;
        actors.push(deployer);
        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
        actors.push(makeAddr("actor3"));
        actors.push(makeAddr("actor4"));
        ghostBalance[deployer] = token_.totalSupply();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Amounts are biased to the edges: zero, the whole balance, one past it, or anything up to
    ///      twice the balance (so both success and insufficient-balance paths are exercised).
    function _amount(uint256 seed, uint256 held) internal pure returns (uint256) {
        uint256 mode = seed % 4;
        if (mode == 0) return 0;
        if (mode == 1) return held;
        if (mode == 2) return held + 1;
        return bound(seed >> 2, 0, held * 2 + 1);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        calls++;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = token.balanceOf(from);
        uint256 amount = _amount(amountSeed, held);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok || amount > held) unexpectedOutcomes++;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            successfulMoves++;
        } catch (bytes memory reason) {
            bytes memory expected =
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount);
            if (amount <= held || keccak256(reason) != keccak256(expected)) unexpectedOutcomes++;
            expectedReverts++;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        calls++;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = amountSeed % 5 == 0 ? type(uint256).max : bound(amountSeed, 0, token.totalSupply() * 2);
        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        if (!ok) unexpectedOutcomes++;
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        calls++;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = token.balanceOf(from);
        uint256 allowed = token.allowance(from, spender);
        uint256 amount = _amount(amountSeed, held);

        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!ok || amount > held || amount > allowed) unexpectedOutcomes++;
            if (allowed != type(uint256).max) ghostAllowance[from][spender] -= amount;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            successfulMoves++;
        } catch (bytes memory reason) {
            // Allowance is checked before balance.
            bytes memory expected = amount > allowed
                ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
                : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount);
            if ((amount <= allowed && amount <= held) || keccak256(reason) != keccak256(expected)) {
                unexpectedOutcomes++;
            }
            expectedReverts++;
        }
    }

    /// @dev Burning to the zero address, or approving it, must always fail and change nothing.
    function transferToZero(uint256 fromSeed, uint256 amountSeed) external {
        calls++;
        address from = _actor(fromSeed);
        uint256 amount = _amount(amountSeed, token.balanceOf(from));
        vm.prank(from);
        try token.transfer(address(0), amount) {
            unexpectedOutcomes++;
        } catch {
            expectedReverts++;
        }
    }

    /// @dev Probes mint/burn-shaped selectors from any actor; every one must be rejected.
    function tryPrivileged(uint256 callerSeed, uint256 selectorSeed, uint256 amount) external {
        calls++;
        address caller = _actor(callerSeed);
        bytes[6] memory payloads = [
            abi.encodeWithSignature("mint(address,uint256)", caller, amount),
            abi.encodeWithSignature("mint(uint256)", amount),
            abi.encodeWithSignature("burn(uint256)", amount),
            abi.encodeWithSignature("burnFrom(address,uint256)", _actor(callerSeed / 2), amount),
            abi.encodeWithSignature("transferOwnership(address)", caller),
            abi.encodeWithSignature("pause()")
        ];
        vm.prank(caller);
        (bool ok,) = address(token).call(payloads[selectorSeed % payloads.length]);
        if (ok) unexpectedOutcomes++;
    }
}

/// @notice Invariants over random call sequences: the fixed supply never changes, balances always
///         sum to it, every balance and allowance matches an independent ghost ledger, and no call
///         ever behaved differently from what the standard requires.
contract ChadGotchiInvariantTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 * 10 ** 18;

    ChadGotchi internal token;
    ChadGotchiHandler internal handler;
    address internal deployer = makeAddr("deployer");

    function setUp() public {
        vm.prank(deployer);
        token = new ChadGotchi();
        handler = new ChadGotchiHandler(token, deployer);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_ledgerMatchesGhost() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address a = handler.actors(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a), "balance drift");
            for (uint256 j; j < n; ++j) {
                address s = handler.actors(j);
                assertEq(token.allowance(a, s), handler.ghostAllowance(a, s), "allowance drift");
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_noUnexpectedOutcome() public view {
        assertEq(handler.unexpectedOutcomes(), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "ChadGotchi");
        assertEq(token.symbol(), "CHAD");
        assertEq(token.decimals(), 18);
    }
}

/// @notice Edge cases pinned as unit tests and stateless fuzz over the arithmetic edges.
contract ChadGotchiEdgeTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 * 10 ** 18;

    ChadGotchi internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.prank(deployer);
        token = new ChadGotchi();
    }

    function test_oneWeiTransfer() public {
        vm.prank(deployer);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 1);
    }

    function test_RevertWhen_transferMaxUint() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, deployer, EXPECTED_SUPPLY, type(uint256).max
            )
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
    }

    function test_RevertWhen_transferFromToZeroAddress() public {
        vm.prank(deployer);
        token.approve(alice, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transferFrom(deployer, address(0), 1 ether);
        assertEq(token.allowance(deployer, alice), 1 ether, "failed transferFrom must not spend allowance");
    }

    function test_RevertWhen_transferFromZeroAddressOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 0 + 1));
        vm.prank(alice);
        token.transferFrom(address(0), bob, 1);
    }

    function test_approveOverwritesNotAdds() public {
        vm.startPrank(deployer);
        token.approve(alice, 5 ether);
        token.approve(alice, 2 ether);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 2 ether);
    }

    function test_approveZeroRevokes() public {
        vm.prank(deployer);
        token.approve(alice, 5 ether);
        vm.prank(deployer);
        token.approve(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
    }

    function test_selfTransferFromSpendsAllowance() public {
        // A holder pulling its own tokens via transferFrom still needs an allowance (standard OZ).
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
    }

    function test_allowanceExactlySpentToZero() public {
        vm.prank(deployer);
        token.approve(alice, 3 ether);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 3 ether);
        assertEq(token.allowance(deployer, alice), 0);
    }

    function test_maxAllowanceSurvivesFullSupplyPull() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(bob), EXPECTED_SUPPLY);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_roundTripRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_splitTransfersSumExactly(uint256 a, uint256 b) public {
        a = bound(a, 0, EXPECTED_SUPPLY);
        b = bound(b, 0, EXPECTED_SUPPLY - a);
        vm.startPrank(deployer);
        token.transfer(alice, a);
        token.transfer(bob, b);
        vm.stopPrank();
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - a - b);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_failedTransferChangesNothing(uint256 amount) public {
        amount = bound(amount, EXPECTED_SUPPLY + 1, type(uint256).max);
        vm.prank(deployer);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (alice, amount)));
        assertFalse(ok);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
