// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import "src/OnchainMetadataSeaDrop.sol";

contract TestSingleUpload is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address contractAddress = vm.envAddress("CONTRACT_ADDRESS");

        vm.startBroadcast(deployer);

        OnchainMetadataSeaDrop collection = OnchainMetadataSeaDrop(contractAddress);

        console.log("=== SINGLE UPLOAD TEST ===");
        console.log("Contract:", contractAddress);
        console.log("Deployer:", deployer);
        console.log("Contract owner:", collection.owner());
        console.log("Metadata finalized:", collection.metadataFinalized());
        console.log("Current metadata count:", collection.getMetadataCount());

        // Try to upload metadata for token 1
        uint256 testTokenId = 1;

        // Check if it already has metadata
        bool hasMetadata = collection.hasMetadata(testTokenId);
        console.log("Token", testTokenId, "has metadata:", hasMetadata);

        if (!hasMetadata) {
            console.log("Attempting to upload metadata for token", testTokenId);

            // Try to read the file
            string memory filename = "data/nfts/token_001.json";

            try vm.readFile(filename) returns (string memory metadataJson) {
                console.log("File read successfully");
                bytes memory metadataBytes = bytes(metadataJson);
                console.log("Original size:", metadataBytes.length);

                // Encode to base64
                string memory base64EncodedJson = Base64.encode(metadataBytes);
                bytes memory base64Bytes = bytes(base64EncodedJson);
                console.log("Encoded size:", base64Bytes.length);

                // Deploy to SSTORE2
                address metadataPointer = SSTORE2.write(base64Bytes);
                console.log("SSTORE2 pointer created:", metadataPointer);

                // Try to set metadata
                try collection.setTokenMetadata(testTokenId, metadataPointer) {
                    console.log("SUCCESS: Metadata set for token", testTokenId);

                    // Verify it was set
                    bool nowHasMetadata = collection.hasMetadata(testTokenId);
                    console.log("Verification - Token now has metadata:", nowHasMetadata);

                    if (nowHasMetadata) {
                        console.log("Final metadata count:", collection.getMetadataCount());
                    }
                } catch Error(string memory reason) {
                    console.log("FAILED: setTokenMetadata failed with reason:", reason);
                } catch {
                    console.log("FAILED: setTokenMetadata failed with empty revert");
                }

            } catch {
                console.log("ERROR: Could not read file:", filename);
            }
        } else {
            console.log("Token already has metadata");
        }

        vm.stopBroadcast();
    }
}
