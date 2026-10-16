// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ChadGotchi} from "../src/ChadGotchi.sol";
import {DeployChadGotchi} from "../script/DeployChadGotchi.s.sol";

/// @notice Behaviour of the token as an ERC-20: metadata, the one-time mint, transfers, allowances,
///         and the failure paths the standard requires.
contract ChadGotchiTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    ChadGotchi internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    event SupplyMinted(address indexed recipient, uint256 amount);

    function setUp() public {
        vm.prank(deployer);
        token = new ChadGotchi();
    }

    // ------------------------------------------------------------------ metadata

    function test_metadata() public view {
        assertEq(token.name(), "ChadGotchi");
        assertEq(token.symbol(), "CHAD");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "ChadGotchi");
        assertEq(token.TOKEN_SYMBOL(), "CHAD");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyConstantsAgree() public view {
        assertEq(token.SUPPLY_WHOLE_TOKENS(), 1_000_000_000);
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
    }

    // ------------------------------------------------------------------ the one-time mint

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsTransferFromZeroAndSupplyMinted() public {
        address who = makeAddr("another deployer");
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), who, EXPECTED_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(who, EXPECTED_SUPPLY);
        vm.prank(who);
        new ChadGotchi();
    }

    function test_supplyGoesToWhoeverDeploysIt() public {
        address factory = makeAddr("factory");
        vm.prank(factory);
        ChadGotchi second = new ChadGotchi();
        assertEq(second.balanceOf(factory), EXPECTED_SUPPLY);
        assertEq(second.balanceOf(deployer), 0);
        // Each deployment is its own supply; the first token is untouched.
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_deployHelperMintsToItsCaller() public {
        DeployChadGotchi helper = new DeployChadGotchi();
        ChadGotchi deployed = helper.deploy();
        // `new` inside the helper makes the helper the deployer.
        assertEq(deployed.balanceOf(address(helper)), EXPECTED_SUPPLY);
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
        assertEq(deployed.name(), "ChadGotchi");
    }

    // ------------------------------------------------------------------ transfers

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferEmitsTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, alice, 5 ether);
        vm.prank(deployer);
        token.transfer(alice, 5 ether);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(deployer, 123 ether);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_transferWholeBalanceLeavesZero() public {
        vm.prank(deployer);
        token.transfer(alice, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), EXPECTED_SUPPLY);
    }

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 10 ether + 1)
        );
        vm.prank(alice);
        token.transfer(bob, 10 ether + 1);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1 ether);
    }

    // ------------------------------------------------------------------ allowances

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(deployer, alice, 7 ether);
        vm.prank(deployer);
        assertTrue(token.approve(alice, 7 ether));
        assertEq(token.allowance(deployer, alice), 7 ether);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 10 ether);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 4 ether));
        assertEq(token.balanceOf(bob), 4 ether);
        assertEq(token.allowance(deployer, alice), 6 ether);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 4 ether);
    }

    function test_transferFromWithMaxAllowanceDoesNotDecrease() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 4 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 3 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 3 ether, 3 ether + 1)
        );
        vm.prank(alice);
        token.transferFrom(deployer, bob, 3 ether + 1);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
    }

    function test_RevertWhen_transferFromExceedsBalanceDespiteAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 1 ether);
        vm.prank(alice);
        token.approve(bob, 2 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 2 ether));
        vm.prank(bob);
        token.transferFrom(alice, bob, 2 ether);
    }

    function test_RevertWhen_approveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    // ------------------------------------------------------------------ fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 excess) public {
        held = bound(held, 0, EXPECTED_SUPPLY - 1);
        excess = bound(excess, 1, EXPECTED_SUPPLY - held);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, held + excess)
        );
        vm.prank(alice);
        token.transfer(bob, held + excess);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, EXPECTED_SUPPLY);
        spent = bound(spent, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        if (spent > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowed, spent)
            );
            vm.prank(alice);
            token.transferFrom(deployer, bob, spent);
            assertEq(token.balanceOf(bob), 0);
        } else {
            vm.prank(alice);
            assertTrue(token.transferFrom(deployer, bob, spent));
            assertEq(token.balanceOf(bob), spent);
            assertEq(token.allowance(deployer, alice), allowed - spent);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }
}
