// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "src/OnchainMetadataSeaDrop.sol";

/// @notice Flip the collection from pre-reveal to revealed (one-way).
///         Upload all per-token metadata with UploadMetadata.s.sol BEFORE running this,
///         otherwise revealed tokens without metadata will revert in tokenURI.
contract Reveal is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        address contractAddress = vm.envAddress("CONTRACT_ADDRESS");

        OnchainMetadataSeaDrop collection = OnchainMetadataSeaDrop(contractAddress);

        console.log("=== REVEAL ===");
        console.log("Contract:", contractAddress);
        console.log("Already revealed:", collection.revealed());
        require(!collection.revealed(), "Already revealed");

        // Safety: warn if not all per-token metadata is uploaded.
        uint256 count = collection.getMetadataCount();
        uint256 maxSupply = collection.maxSupply();
        console.log("Per-token metadata uploaded:", count);
        console.log("Max supply:", maxSupply);
        if (count < maxSupply) {
            console.log("WARNING: Not all tokens have metadata!");
            console.log("Missing count:", maxSupply - count);
            console.log("Tokens without metadata will revert in tokenURI after reveal.");
        }

        vm.startBroadcast(deployer);
        collection.reveal();
        vm.stopBroadcast();

        console.log("=== REVEALED ===");
        console.log("revealed:", collection.revealed());
        console.log("tokenURI now returns per-token metadata.");
    }
}
