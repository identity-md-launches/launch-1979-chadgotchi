// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ChadGotchi} from "../src/ChadGotchi.sol";

/// @notice Stands in for the launch factory: deploys the token through CREATE2 from its creation
///         code, as ProjectFactory.launchCustom does, so the supply lands on the factory's address.
contract FactoryProbe {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0) && deployed.code.length > 0, "constructor failed");
    }

    function move(ChadGotchi token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @notice A local mirror of the launch floor a custom token must clear: the manifest supply is
///         minted whole to the factory, launch flows move exactly what they say, nothing can grow the
///         supply, no privileged hand can move or freeze a holder, and the runtime contains no
///         DELEGATECALL, CALLCODE or SELFDESTRUCT. The authoritative version runs in the verifier's
///         harness against the attested bytecode; this one lets the project check itself first.
contract ChadGotchiLaunchFloorTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 internal constant SWARM_BPS = 1_000;
    uint256 internal constant POOL_BPS = 8_000;

    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant CLAIMANT = address(0xC1A1);
    address internal constant HOLDER = address(0x401D);
    address internal constant OTHER = address(0x07E5);
    address internal constant POOL_MANAGER = address(0x900);
    address internal constant REMAINDER_TO = 0xCe34A5aE98F51b499B92063a7a83d49B26ee5b14;

    FactoryProbe internal factory;
    ChadGotchi internal token;

    function setUp() public {
        factory = new FactoryProbe();
        bytes memory code = type(ChadGotchi).creationCode;
        address predicted = vm.computeCreate2Address(bytes32(uint256(7)), keccak256(code), address(factory));
        token = ChadGotchi(factory.deploy(code, bytes32(uint256(7))));
        assertEq(address(token), predicted, "CREATE2 address prediction");
    }

    function test_mintsTheManifestSupplyToTheFactory() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(factory)), EXPECTED_SUPPLY);
        assertEq(token.decimals(), 18);
    }

    function test_constructorTakesNoArgumentsAndCallsNoContract() public view {
        // Creation code is the runtime plus the constructor only: no ABI-encoded arguments follow.
        bytes memory creation = type(ChadGotchi).creationCode;
        assertGt(creation.length, address(token).code.length, "creation code should wrap the runtime");
        // The probe deployed on an otherwise empty chain and nothing else had code at the time.
        assertEq(address(0xdead).code.length, 0);
    }

    /// @dev Swarm share: factory -> distributor -> claimant, each whole.
    function test_theSwarmShareArrivesWholeAndIsClaimableWhole() public {
        uint256 swarm = (EXPECTED_SUPPLY * SWARM_BPS) / 10_000;
        assertTrue(factory.move(token, DISTRIBUTOR, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm));
        assertEq(token.balanceOf(CLAIMANT), swarm);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    /// @dev The whole launch split: 10% swarm, 80% pool seed, 10% requester remainder, all exact.
    function test_launchSplitMovesExactly() public {
        uint256 swarm = (EXPECTED_SUPPLY * SWARM_BPS) / 10_000;
        uint256 pool = (EXPECTED_SUPPLY * POOL_BPS) / 10_000;
        uint256 remainder = EXPECTED_SUPPLY - swarm - pool;
        assertTrue(factory.move(token, DISTRIBUTOR, swarm));
        assertTrue(factory.move(token, POOL_MANAGER, pool));
        assertTrue(factory.move(token, REMAINDER_TO, remainder));
        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
        assertEq(token.balanceOf(REMAINDER_TO), remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);

        // A trader buys from and sells back into the pool manager: both legs move exactly.
        address trader = makeAddr("trader");
        vm.prank(POOL_MANAGER);
        assertTrue(token.transfer(trader, 1 ether));
        assertEq(token.balanceOf(trader), 1 ether);
        vm.prank(trader);
        assertTrue(token.transfer(POOL_MANAGER, 1 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
    }

    function test_noCommonAdminCallIncreasesSupply() public {
        address attacker = address(0xBEEF);
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpected selector accepted: ", signatures[i]));
            assertEq(token.totalSupply(), EXPECTED_SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
            vm.prank(address(factory));
            (ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpected selector accepted from factory: ", signatures[i]));
            assertEq(token.totalSupply(), EXPECTED_SUPPLY, signatures[i]);
        }
    }

    function test_noPrivilegedHandMovesOrFreezesAHolder() public {
        factory.move(token, HOLDER, EXPECTED_SUPPLY / 1_000);
        uint256 held = token.balanceOf(HOLDER);
        assertGt(held, 0);
        string[13] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "burn(uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], HOLDER, true);
            vm.prank(address(factory));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("unexpected selector accepted: ", signatures[i]));
        }
        // No allowance was granted, so even the factory cannot pull from the holder.
        vm.prank(address(factory));
        (bool moved,) = address(token).call(abi.encodeWithSelector(token.transferFrom.selector, HOLDER, factory, 1));
        assertFalse(moved, "transferFrom without allowance must revert");
        assertEq(token.balanceOf(HOLDER), held);
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, held / 2));
        assertEq(token.balanceOf(OTHER), held / 2);
    }

    function test_unknownSelectorsRevertAndPlainEtherIsRefused() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "fallback must not exist");
        vm.deal(address(this), 1 ether);
        (ok,) = address(token).call{value: 1 wei}("");
        assertFalse(ok, "receive must not exist");
        assertEq(address(token).balance, 0);
    }

    function test_runtimeCodeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
            assertTrue(op != 0xF2, "runtime code contains CALLCODE");
            assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
        }
    }

    function test_runtimeCarriesNoMetadataHash() public view {
        // bytecode_hash = "none" and cbor_metadata = false: the runtime must not end in a CBOR
        // metadata blob (whose last two bytes encode its length and whose body starts 0xa1/0xa2).
        bytes memory runtime = address(token).code;
        uint256 n = runtime.length;
        uint256 cborLength = (uint256(uint8(runtime[n - 2])) << 8) | uint256(uint8(runtime[n - 1]));
        bool looksLikeCbor = cborLength + 2 <= n && cborLength >= 2
            && (uint8(runtime[n - 2 - cborLength]) == 0xa1 || uint8(runtime[n - 2 - cborLength]) == 0xa2)
            && uint8(runtime[n - 1 - cborLength]) == 0x64; // "d" of "ipfs" / "solc" text key
        assertFalse(looksLikeCbor, "runtime ends in a metadata hash; set bytecode_hash = none");
    }
}
