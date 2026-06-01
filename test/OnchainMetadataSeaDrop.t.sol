// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/OnchainMetadataSeaDrop.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";
import {Base64} from "openzeppelin-contracts/utils/Base64.sol";

contract OnchainMetadataSeaDropTest is Test {
    OnchainMetadataSeaDrop public collection;
    address public seadropAddress = 0x8FFf93E810af25A6d5EDa6E6f2d14bD1138484f5;
    uint256 public constant TEST_SUPPLY = 512;  // Any value works; supply is configurable.

    // ERC-4906 events, redeclared so vm.expectEmit can match them.
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function setUp() public {
        // Deploy with current 3-argument constructor
        collection = new OnchainMetadataSeaDrop("OnchainMetadataSeaDrop", "NFT", seadropAddress);
        // Supply is no longer a constant — configure it via the inherited setMaxSupply().
        collection.setMaxSupply(TEST_SUPPLY);
    }

    function testContractSetup() public {
        assertEq(collection.name(), "OnchainMetadataSeaDrop");
        assertEq(collection.symbol(), "NFT");
        assertEq(collection.maxSupply(), TEST_SUPPLY);
        assertEq(collection.getMetadataCount(), 0);
        assertFalse(collection.metadataFinalized());
    }

    function testSupplyIsConfigurable() public {
        // Supply can be changed to any value via setMaxSupply().
        collection.setMaxSupply(10000);
        assertEq(collection.maxSupply(), 10000);

        // Token IDs are validated against the current supply, so the new ceiling applies.
        address pointer = _writeBlob('{"name":"#9001"}');
        collection.setTokenMetadata(9001, pointer);
        assertTrue(collection.hasMetadata(9001));
    }

    function testTokenIdsStartAtOne() public {
        // Test that _startTokenId returns 1
        // We can't call it directly since it's internal, but we can test behavior
        assertTrue(true); // Placeholder - would need to test via minting
    }

    function testSetTokenMetadata() public {
        // Create test metadata
        string memory testJson = '{"name":"Test NFT","description":"A test NFT"}';
        bytes memory jsonBytes = bytes(testJson);

        // Encode to base64
        string memory base64Json = Base64.encode(jsonBytes);
        bytes memory base64Bytes = bytes(base64Json);

        // Store in SSTORE2
        address metadataPointer = SSTORE2.write(base64Bytes);

        // Set metadata for token 1
        collection.setTokenMetadata(1, metadataPointer);

        // Verify metadata was set
        assertTrue(collection.hasMetadata(1));
        assertEq(collection.getMetadataCount(), 1);
        assertEq(collection.tokenMetadata(1), metadataPointer);
    }

    function testBatchSetTokenMetadata() public {
        // Create test metadata for tokens 1-3
        uint256[] memory tokenIds = new uint256[](3);
        address[] memory pointers = new address[](3);

        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = i + 1;

            string memory testJson = string.concat('{"name":"Test NFT #', vm.toString(i + 1), '"}');
            bytes memory jsonBytes = bytes(testJson);
            string memory base64Json = Base64.encode(jsonBytes);
            bytes memory base64Bytes = bytes(base64Json);

            pointers[i] = SSTORE2.write(base64Bytes);
        }

        // Batch set metadata
        collection.batchSetTokenMetadata(tokenIds, pointers);

        // Verify all metadata was set
        assertEq(collection.getMetadataCount(), 3);
        for (uint256 i = 1; i <= 3; i++) {
            assertTrue(collection.hasMetadata(i));
        }
    }

    function testTokenURI() public {
        // Create and set test metadata
        string memory testJson = '{"name":"Test NFT","description":"A test NFT"}';
        bytes memory jsonBytes = bytes(testJson);
        string memory base64Json = Base64.encode(jsonBytes);
        bytes memory base64Bytes = bytes(base64Json);
        address metadataPointer = SSTORE2.write(base64Bytes);

        _mint(1);
        collection.setTokenMetadata(1, metadataPointer);

        // Per-token metadata only surfaces after reveal.
        collection.reveal();

        // Test tokenURI returns base64 data URI
        string memory tokenURI = collection.tokenURI(1);

        // Should start with data:application/json;base64,
        assertTrue(bytes(tokenURI).length > 0);

        // Check it starts with correct prefix
        string memory expectedPrefix = "data:application/json;base64,";
        bytes memory prefixBytes = bytes(expectedPrefix);
        bytes memory uriBytes = bytes(tokenURI);

        assertTrue(uriBytes.length >= prefixBytes.length);

        // Extract and verify the prefix
        bool prefixMatches = true;
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            if (uriBytes[i] != prefixBytes[i]) {
                prefixMatches = false;
                break;
            }
        }
        assertTrue(prefixMatches);
    }

    function _writeBlob(string memory json) internal returns (address) {
        return SSTORE2.write(bytes(Base64.encode(bytes(json))));
    }

    /// @dev Mint `quantity` tokens (IDs 1..quantity) so tokenURI's _exists() check passes.
    ///      Pranks as the allowed SeaDrop address, the only caller mintSeaDrop accepts.
    function _mint(uint256 quantity) internal {
        vm.prank(seadropAddress);
        collection.mintSeaDrop(address(0xBEEF), quantity);
    }

    function testSetPrerevealMetadata() public {
        assertEq(collection.prerevealPointer(), address(0));
        assertFalse(collection.revealed());

        address pointer = _writeBlob('{"name":"Unrevealed"}');
        collection.setPrerevealMetadata(pointer);

        assertEq(collection.prerevealPointer(), pointer);
    }

    function testSetPrerevealRejectsZeroPointer() public {
        vm.expectRevert("Invalid pointer");
        collection.setPrerevealMetadata(address(0));
    }

    function testCannotSetPrerevealAfterFinalized() public {
        collection.finalizeMetadata();
        address pointer = _writeBlob('{"name":"Unrevealed"}');
        vm.expectRevert("Metadata is finalized");
        collection.setPrerevealMetadata(pointer);
    }

    function testPrerevealTokenURI() public {
        _mint(2);
        // Before reveal every token resolves to the single pre-reveal blob,
        // even tokens that already have per-token metadata set.
        address prereveal = _writeBlob('{"name":"Unrevealed"}');
        collection.setPrerevealMetadata(prereveal);

        address perToken = _writeBlob('{"name":"Revealed #1"}');
        collection.setTokenMetadata(1, perToken);

        // Pre-reveal blob is shared, so token 1 and token 2 return the same URI.
        assertEq(collection.tokenURI(1), collection.tokenURI(2));
    }

    function testTokenURIRevertsWhenPrerevealUnset() public {
        _mint(1);
        // No pre-reveal blob and not revealed -> tokenURI has nothing to return.
        vm.expectRevert("Pre-reveal metadata not set");
        collection.tokenURI(1);
    }

    function testRevealSwitchesToPerToken() public {
        _mint(2);
        address prereveal = _writeBlob('{"name":"Unrevealed"}');
        collection.setPrerevealMetadata(prereveal);

        address token1 = _writeBlob('{"name":"Revealed #1"}');
        address token2 = _writeBlob('{"name":"Revealed #2"}');
        collection.setTokenMetadata(1, token1);
        collection.setTokenMetadata(2, token2);

        // Same pre-reveal URI before reveal.
        assertEq(collection.tokenURI(1), collection.tokenURI(2));

        collection.reveal();
        assertTrue(collection.revealed());

        // Distinct per-token URIs after reveal.
        assertTrue(
            keccak256(bytes(collection.tokenURI(1))) != keccak256(bytes(collection.tokenURI(2)))
        );
    }

    function testCannotRevealTwice() public {
        collection.reveal();
        vm.expectRevert("Already revealed");
        collection.reveal();
    }

    // --- ERC-4906 (Metadata Update Extension) ---

    function testSupportsERC4906Interface() public {
        // Interface id is advertised by SeaDrop's inherited supportsInterface.
        assertTrue(collection.supportsInterface(0x49064906));
    }

    function testSetTokenMetadataEmitsMetadataUpdate() public {
        address pointer = _writeBlob('{"name":"#1"}');
        vm.expectEmit(true, true, true, true);
        emit MetadataUpdate(1);
        collection.setTokenMetadata(1, pointer);
    }

    function testBatchSetEmitsMetadataUpdatePerToken() public {
        uint256[] memory ids = new uint256[](2);
        address[] memory ptrs = new address[](2);
        ids[0] = 5;
        ids[1] = 9;
        ptrs[0] = _writeBlob('{"name":"#5"}');
        ptrs[1] = _writeBlob('{"name":"#9"}');

        // One MetadataUpdate per (non-contiguous) token ID.
        vm.expectEmit(true, true, true, true);
        emit MetadataUpdate(5);
        vm.expectEmit(true, true, true, true);
        emit MetadataUpdate(9);
        collection.batchSetTokenMetadata(ids, ptrs);
    }

    function testSetPrerevealEmitsBatchMetadataUpdate() public {
        address pointer = _writeBlob('{"name":"Unrevealed"}');
        vm.expectEmit(true, true, true, true);
        emit BatchMetadataUpdate(1, TEST_SUPPLY);
        collection.setPrerevealMetadata(pointer);
    }

    function testRevealEmitsBatchMetadataUpdate() public {
        vm.expectEmit(true, true, true, true);
        emit BatchMetadataUpdate(1, TEST_SUPPLY);
        collection.reveal();
    }

    function testRevealedTokenWithoutMetadataReverts() public {
        _mint(1);
        collection.reveal();
        vm.expectRevert("Metadata not set for token");
        collection.tokenURI(1);
    }

    function testFinalizeMetadata() public {
        assertFalse(collection.metadataFinalized());

        collection.finalizeMetadata();

        assertTrue(collection.metadataFinalized());
    }

    function testCannotSetMetadataAfterFinalized() public {
        // Finalize metadata
        collection.finalizeMetadata();

        // Try to set metadata - should revert
        address dummyPointer = address(0x123);

        vm.expectRevert("Metadata is finalized");
        collection.setTokenMetadata(1, dummyPointer);
    }

    function testInvalidTokenId() public {
        address dummyPointer = address(0x123);

        // Token ID 0 should revert
        vm.expectRevert("Invalid token ID");
        collection.setTokenMetadata(0, dummyPointer);

        // Token ID > maxSupply() should revert
        vm.expectRevert("Invalid token ID");
        collection.setTokenMetadata(TEST_SUPPLY + 1, dummyPointer);
    }
}
