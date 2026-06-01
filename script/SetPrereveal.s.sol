// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import "src/OnchainMetadataSeaDrop.sol";

/// @notice Deploy the single pre-reveal metadata blob and point the contract at it.
///         Every token's tokenURI returns this blob until reveal() is called.
contract SetPrereveal is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address contractAddress = vm.envAddress("CONTRACT_ADDRESS");

        OnchainMetadataSeaDrop collection = OnchainMetadataSeaDrop(contractAddress);

        console.log("=== SET PRE-REVEAL METADATA ===");
        console.log("Contract:", contractAddress);
        console.log("Already revealed:", collection.revealed());

        // Read the single pre-reveal JSON (shared by every token).
        string memory filename = "data/prereveal.json";
        string memory metadataJson = vm.readFile(filename);
        bytes memory metadataBytes = bytes(metadataJson);
        console.log("Pre-reveal file:", filename);
        console.log("Original size:", metadataBytes.length);

        require(metadataBytes.length <= 50 * 1024, "Pre-reveal file too large");

        // Base64 encode for anti-sniping consistency with per-token metadata.
        string memory base64EncodedJson = Base64.encode(metadataBytes);
        bytes memory base64Bytes = bytes(base64EncodedJson);
        console.log("Encoded size:", base64Bytes.length);

        vm.startBroadcast(deployer);

        // Deploy the blob to SSTORE2 and register it as the pre-reveal pointer.
        address pointer = SSTORE2.write(base64Bytes);
        console.log("SSTORE2 pointer:", pointer);

        collection.setPrerevealMetadata(pointer);

        vm.stopBroadcast();

        console.log("=== PRE-REVEAL METADATA SET ===");
        console.log("prerevealPointer:", collection.prerevealPointer());
        console.log("Every token now resolves to this blob until reveal().");
    }
}
