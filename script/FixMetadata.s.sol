// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";
import "src/OnchainMetadataSeaDrop.sol";

/// @notice Overwrite a single token's metadata to correct a typo / wrong file.
///         Unlike UploadMetadata.s.sol (which skips tokens that already have
///         metadata), this ALWAYS overwrites tokenMetadata[TOKEN_ID].
///
///         Works both before and after reveal — setTokenMetadata does not check
///         the revealed flag. Only finalizeMetadata() blocks it.
///
///         Usage: TOKEN_ID=42 forge script script/FixMetadata.s.sol:FixMetadata \
///                  --broadcast --rpc-url $BASE_MAINNET_RPC_URL \
///                  --private-key $PRIVATE_KEY --chain 8453
contract FixMetadata is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address contractAddress = vm.envAddress("CONTRACT_ADDRESS");
        uint256 tokenId = vm.envUint("TOKEN_ID");

        OnchainMetadataSeaDrop collection = OnchainMetadataSeaDrop(contractAddress);

        console.log("=== FIX TOKEN METADATA ===");
        console.log("Contract:", contractAddress);
        console.log("Token ID:", tokenId);
        console.log("Revealed:", collection.revealed());
        console.log("Old pointer:", collection.tokenMetadata(tokenId));

        require(!collection.metadataFinalized(), "Metadata finalized: corrections are permanently locked");

        // Read the corrected JSON for this token (edit the file first).
        string memory filename = string.concat("data/nfts/token_", _padTokenId(tokenId), ".json");
        string memory metadataJson = vm.readFile(filename);
        bytes memory metadataBytes = bytes(metadataJson);
        console.log("File:", filename);
        console.log("Original size:", metadataBytes.length);
        require(metadataBytes.length <= 50 * 1024, "File too large");

        // Base64 encode and deploy a NEW SSTORE2 blob (the old one is left orphaned on-chain).
        bytes memory base64Bytes = bytes(Base64.encode(metadataBytes));
        console.log("Encoded size:", base64Bytes.length);

        vm.startBroadcast(deployer);
        address newPointer = SSTORE2.write(base64Bytes);
        collection.setTokenMetadata(tokenId, newPointer);
        vm.stopBroadcast();

        console.log("New pointer:", newPointer);
        console.log("=== DONE ===");
        if (collection.revealed()) {
            console.log("Revealed: tokenURI(", tokenId);
            console.log(") now serves the corrected metadata.");
        } else {
            console.log("Pre-reveal: correction is live now and will surface once reveal() is called.");
        }
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
