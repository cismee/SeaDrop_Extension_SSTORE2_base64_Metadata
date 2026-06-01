// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import "src/OnchainMetadataSeaDrop.sol";

contract UploadMetadata is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address contractAddress = vm.envAddress("CONTRACT_ADDRESS");

        vm.startBroadcast(deployer);

        OnchainMetadataSeaDrop collection = OnchainMetadataSeaDrop(contractAddress);

        console.log("=== METADATA UPLOAD STARTING ===");
        console.log("Contract:", contractAddress);
        console.log("Current metadata count:", collection.getMetadataCount());
        console.log("Max supply:", collection.maxSupply());
        console.log("Mode: Base64 encoded JSON (anti-sniping protection)");

        // Upload in batches to manage gas limits
        uint256 batchSize = 1;  // Process one token at a time
        uint256 maxSupply = collection.maxSupply();

        // Start from current progress (automatically detect where to resume)
        uint256 currentCount = collection.getMetadataCount();
        uint256 startingToken = currentCount + 1;
        console.log("Current metadata count:", currentCount);
        console.log("Starting from token:", startingToken);

        for (uint256 startToken = startingToken; startToken <= maxSupply; startToken += batchSize) {
            uint256 endToken = startToken + batchSize - 1;
            if (endToken > maxSupply) {
                endToken = maxSupply;
            }

            console.log("");
            console.log("=== BATCH:", startToken);
            console.log("    to:", endToken, "===");
            uploadBatch(collection, startToken, endToken, deployer);

            // Show progress
            uint256 newCount = collection.getMetadataCount();
            console.log("Progress:", newCount);
            console.log("Total:", maxSupply);
        }

        uint256 finalCount = collection.getMetadataCount();
        console.log("");
        console.log("=== UPLOAD COMPLETE ===");
        console.log("Final metadata count:", finalCount);
        console.log("Out of total:", maxSupply);

        if (finalCount == maxSupply) {
            console.log("SUCCESS: All metadata uploaded with base64 encoding!");
            console.log("Anti-sniping protection: ACTIVE");
            console.log("");
            console.log("Optional: Finalize metadata to prevent further changes:");
            console.log("cast send", contractAddress, "finalizeMetadata()");
            console.log("Add: --rpc-url $BASE_MAINNET_RPC_URL");
            console.log("Add: --private-key $PRIVATE_KEY");
        } else {
            console.log("WARNING: Missing metadata for some tokens");
            console.log("Missing count:", maxSupply - finalCount);
            console.log("Check your data/nfts/ directory");
        }

        vm.stopBroadcast();
    }

    /// @notice Upload a batch of tokens efficiently with base64 encoding - IMPROVED VERSION
    function uploadBatch(OnchainMetadataSeaDrop collection, uint256 startToken, uint256 endToken, address deployer) internal {
        uint256 batchSize = endToken - startToken + 1;
        uint256[] memory tokenIds = new uint256[](batchSize);
        address[] memory metadataPointers = new address[](batchSize);

        uint256 successCount = 0;

        // Deploy SSTORE2 contracts for each token in batch
        for (uint256 tokenId = startToken; tokenId <= endToken; tokenId++) {
            // Skip if already has metadata
            if (collection.hasMetadata(tokenId)) {
                console.log("Token already uploaded:", tokenId);
                continue;
            }

            // Try to read metadata file
            string memory filename = string.concat(
                "data/nfts/token_",
                _padTokenId(tokenId),
                ".json"
            );

            try vm.readFile(filename) returns (string memory metadataJson) {
                bytes memory metadataBytes = bytes(metadataJson);

                // Validate file size before encoding
                if (metadataBytes.length > 50 * 1024) {  // 50KB limit before encoding
                    console.log("  Token", vm.toString(tokenId), ": WARNING - File too large");
                    console.log("    Size:", vm.toString(metadataBytes.length), "bytes, skipping");
                    continue;
                }

                // Encode JSON to base64 for anti-sniping protection
                string memory base64EncodedJson = Base64.encode(metadataBytes);
                bytes memory base64Bytes = bytes(base64EncodedJson);

                // Deploy base64 encoded JSON to SSTORE2
                address metadataPointer = SSTORE2.write(base64Bytes);

                tokenIds[successCount] = tokenId;
                metadataPointers[successCount] = metadataPointer;
                successCount++;

                console.log("Token encoded:", vm.toString(tokenId));
                console.log("Pointer:", metadataPointer);
                console.log("Original size:", vm.toString(metadataBytes.length));
                console.log("Encoded size:", vm.toString(base64Bytes.length));

            } catch {
                console.log("ERROR reading file for token:", vm.toString(tokenId));
            }
        }

        // Process individual uploads instead of batch to avoid failures
        console.log("Processing", vm.toString(successCount), "tokens individually");

        // Check ETH balance before individual uploads
        uint256 currentBalance = deployer.balance;
        console.log("Current balance before uploads:", vm.toString(currentBalance));

        if (currentBalance < 0.001 ether) {
            console.log("WARNING: Very low balance, uploads may fail");
            console.log("Balance in ETH:", vm.toString(currentBalance / 1e18));
        }

        for (uint256 i = 0; i < successCount; i++) {
            uint256 tokenId = tokenIds[i];
            address pointer = metadataPointers[i];

            // Check if already has metadata (double check)
            if (collection.hasMetadata(tokenId)) {
                console.log("Token", vm.toString(tokenId), "already has metadata, skipping");
                continue;
            }

            // Upload individually with error handling
            console.log("Attempting to upload token:", vm.toString(tokenId));
            console.log("Using pointer:", pointer);
            console.log("Token has metadata?", collection.hasMetadata(tokenId));

            try collection.setTokenMetadata(tokenId, pointer) {
                console.log("SUCCESS: Token", vm.toString(tokenId), "uploaded");
            } catch Error(string memory reason) {
                console.log("FAILED: Token", vm.toString(tokenId), "failed with reason:", reason);
            } catch {
                console.log("FAILED: Token", vm.toString(tokenId), "failed with empty revert");

                // Try to diagnose the issue
                console.log("  Pointer:", pointer);
                console.log("  Token in range:", tokenId >= 1 && tokenId <= collection.maxSupply());
                console.log("  Contract owner:", collection.owner());
                console.log("  Metadata finalized:", collection.metadataFinalized());
            }
        }

        console.log("Batch processing complete");
        console.log("New metadata count:", collection.getMetadataCount());
    }

    /// @notice Helper to pad token ID to 3 digits (001, 002, etc.)
    function _padTokenId(uint256 tokenId) internal pure returns (string memory) {
        if (tokenId < 10) {
            return string.concat("00", vm.toString(tokenId));
        } else if (tokenId < 100) {
            return string.concat("0", vm.toString(tokenId));
        } else {
            return vm.toString(tokenId);
        }
    }
}
