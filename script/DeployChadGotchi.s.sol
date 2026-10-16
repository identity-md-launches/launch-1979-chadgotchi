// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {ChadGotchi} from "../src/ChadGotchi.sol";

/// @title DeployChadGotchi
/// @notice Reviewable deploy helper for a plain (non-IdentityMD) deployment of the token.
/// @dev The IdentityMD launch does not use this script: its ProjectFactory deploys the token from
///      the built bytecode through CREATE2. This script exists so the deployment is reproducible and
///      testable elsewhere. `deploy()` takes no configuration because the token has no constructor
///      arguments; tests call it directly and never read the environment.
contract DeployChadGotchi is Script {
    /// @notice Deploys the token. Whoever is `msg.sender` of the CREATE receives the whole supply.
    /// @return token The deployed token.
    function deploy() public returns (ChadGotchi token) {
        token = new ChadGotchi();
    }

    /// @notice Broadcast entry point: `forge script script/DeployChadGotchi.s.sol --broadcast`.
    ///         The broadcasting account becomes the deployer and receives the whole supply.
    function run() external returns (ChadGotchi token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
