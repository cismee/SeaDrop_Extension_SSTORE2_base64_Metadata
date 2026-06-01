// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "src/OnchainMetadataSeaDrop.sol";

contract Deploy is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        // Collection size — configurable per-deploy (the contract has no hard-coded supply).
        uint256 maxSupply = vm.envUint("MAX_SUPPLY");

        // SAFETY CHECK: Ensure we're on the correct network
        require(block.chainid == 8453, "ERROR: Not on Base Mainnet! Current chain ID is not 8453");

        // SAFETY CHECK: Ensure deployer has sufficient ETH
        require(deployer.balance >= 0.05 ether, "ERROR: Insufficient ETH balance for deployment");

        console.log("=== MAINNET DEPLOYMENT STARTING ===");
        console.log("WARNING: This is MAINNET deployment with REAL ETH!");
        console.log("Network: Base Mainnet (Chain ID: 8453)");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "ETH");
        console.log("");

        // Ready to deploy
        console.log("Ready to deploy...");

        vm.startBroadcast(deployer);

        // Deploy the contract with Base Mainnet SeaDrop address
        OnchainMetadataSeaDrop collection = new OnchainMetadataSeaDrop(
            "OnchainMetadataSeaDrop",
            "NFT",
            0x00005EA00Ac477B1030CE78506496e8C2dE24bf5  // SeaDrop address for Base Mainnet
        );

        // Configure the collection size (SeaDrop's inherited setMaxSupply).
        collection.setMaxSupply(maxSupply);

        vm.stopBroadcast();

        console.log("=== MAINNET DEPLOYMENT SUCCESSFUL ===");
        console.log("Contract deployed to:", address(collection));
        console.log("Contract owner:", collection.owner());
        console.log("Max supply:", collection.maxSupply());
        console.log("Starting token ID: 1");
        console.log("Anti-sniping: Base64 encoded JSON metadata");
        console.log("SeaDrop integration: ACTIVE");
        console.log("");

        console.log("=== IMPORTANT: SAVE THIS INFO ===");
        console.log("Contract Address:", address(collection));
        console.log("Block Explorer: https://basescan.org/address/", address(collection));
        console.log("OpenSea (when ready): https://opensea.io/assets/base/", address(collection));
        console.log("");

        console.log("=== NEXT STEPS ===");
        console.log("1. Set environment variable:");
        console.log("   export CONTRACT_ADDRESS=", address(collection));
        console.log("");
        console.log("2. Update your .env file:");
        console.log("   CONTRACT_ADDRESS=", address(collection));
        console.log("");
        console.log("3. Verify contract on BaseScan:");
        console.log("   forge verify-contract --chain-id 8453 \\");
        console.log("     --rpc-url $BASE_MAINNET_RPC_URL \\");
        console.log("     --etherscan-api-key $BASESCAN_API_KEY \\");
        console.log("     ", address(collection), " \\");
        console.log("     src/OnchainMetadataSeaDrop.sol:OnchainMetadataSeaDrop \\");
        console.log("     --constructor-args $(cast abi-encode \"constructor(string,string,address)\" \"OnchainMetadataSeaDrop\" \"NFT\" \"0x00005EA00Ac477B1030CE78506496e8C2dE24bf5\")");
        console.log("");
        console.log("4. Upload metadata (AFTER verification):");
        console.log("   forge script script/UploadMetadata.s.sol:UploadMetadata \\");
        console.log("     --broadcast --rpc-url $BASE_MAINNET_RPC_URL \\");
        console.log("     --private-key $PRIVATE_KEY --chain 8453");
        console.log("");
        console.log("5. Check deployment:");
        console.log("   cast call", address(collection), "name()(string) --rpc-url $BASE_MAINNET_RPC_URL");
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
    }
}
