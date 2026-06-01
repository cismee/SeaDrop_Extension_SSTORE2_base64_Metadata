// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDrop} from "seadrop/ERC721SeaDrop.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

contract OnchainMetadataSeaDrop is ERC721SeaDrop {
    // O(1) mapping: tokenId => SSTORE2 address containing base64 encoded JSON metadata
    mapping(uint256 => address) public tokenMetadata;

    // Collection size is the inherited SeaDrop maxSupply() (set via setMaxSupply()).
    // No separate constant here, so supply is configured per-deploy and can be any value.
    bool public metadataFinalized;

    // Pre-reveal: a single SSTORE2 blob every token resolves to until reveal() is called.
    address public prerevealPointer;
    // One-way switch: false => tokenURI returns the pre-reveal blob; true => per-token metadata.
    bool public revealed;

    event PrerevealMetadataSet(address indexed pointer);
    event Revealed();

    // ERC-4906 (Metadata Update Extension). SeaDrop's ERC721ContractMetadata already
    // declares BatchMetadataUpdate and advertises interface 0x49064906; only the
    // single-token MetadataUpdate event is missing, so we declare it here.
    event MetadataUpdate(uint256 _tokenId);

    constructor(
        string memory name,
        string memory symbol,
        address allowedSeaDrop
    ) ERC721SeaDrop(name, symbol, _toDynamic(allowedSeaDrop)) {}

    /// @notice Add metadata for a specific token ID
    /// @param tokenId The token ID (1 .. maxSupply())
    /// @param metadataPointer SSTORE2 address containing base64 encoded JSON
    function setTokenMetadata(uint256 tokenId, address metadataPointer) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        require(tokenId >= 1 && tokenId <= maxSupply(), "Invalid token ID");
        tokenMetadata[tokenId] = metadataPointer;
        emit MetadataUpdate(tokenId);  // ERC-4906
    }

    /// @notice Batch set metadata for multiple tokens (gas optimization)
    /// @param tokenIds Array of token IDs
    /// @param metadataPointers Array of SSTORE2 addresses
    function batchSetTokenMetadata(
        uint256[] calldata tokenIds,
        address[] calldata metadataPointers
    ) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        require(tokenIds.length == metadataPointers.length, "Array length mismatch");
        require(tokenIds.length <= 3, "Batch too large"); // Reduced for mainnet stability

        uint256 supply = maxSupply();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(tokenIds[i] >= 1 && tokenIds[i] <= supply, "Invalid token ID");
            tokenMetadata[tokenIds[i]] = metadataPointers[i];
            emit MetadataUpdate(tokenIds[i]);  // ERC-4906 (IDs may be non-contiguous)
        }
    }

    /// @notice Check if token has metadata set
    function hasMetadata(uint256 tokenId) external view returns (bool) {
        return tokenMetadata[tokenId] != address(0);
    }

    /// @notice Get count of tokens with metadata set
    function getMetadataCount() public view returns (uint256 count) {
        uint256 supply = maxSupply();
        for (uint256 i = 1; i <= supply; i++) {
            if (tokenMetadata[i] != address(0)) {
                count++;
            }
        }
    }

    /// @notice Get all tokens that have metadata set
    function getTokensWithMetadata() external view returns (uint256[] memory tokens) {
        uint256 count = getMetadataCount();
        tokens = new uint256[](count);

        uint256 supply = maxSupply();
        uint256 index = 0;
        for (uint256 i = 1; i <= supply; i++) {
            if (tokenMetadata[i] != address(0)) {
                tokens[index] = i;
                index++;
            }
        }
    }

    /// @notice Set the single pre-reveal metadata blob shown for every token before reveal
    /// @param pointer SSTORE2 address containing the base64 encoded pre-reveal JSON
    function setPrerevealMetadata(address pointer) external onlyOwner {
        require(!metadataFinalized, "Metadata is finalized");
        require(pointer != address(0), "Invalid pointer");
        prerevealPointer = pointer;
        emit PrerevealMetadataSet(pointer);
        _emitBatchMetadataUpdate();  // ERC-4906: every token's pre-reveal blob changed
    }

    /// @notice Reveal the collection. One-way: tokenURI switches from the single
    ///         pre-reveal blob to each token's own metadata pointer.
    /// @dev Upload all per-token metadata (setTokenMetadata / batchSetTokenMetadata)
    ///      before calling this, or revealed tokens without metadata will revert in tokenURI.
    function reveal() external onlyOwner {
        require(!revealed, "Already revealed");
        revealed = true;
        emit Revealed();
        _emitBatchMetadataUpdate();  // ERC-4906: every token flips to its own metadata
    }

    function finalizeMetadata() external onlyOwner {
        metadataFinalized = true;
    }

    /// @dev Emit an ERC-4906 BatchMetadataUpdate over the whole collection (token IDs 1..maxSupply()).
    function _emitBatchMetadataUpdate() internal {
        uint256 supply = maxSupply();
        if (supply > 0) {
            emit BatchMetadataUpdate(1, supply);
        }
    }

    function _toDynamic(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    /// @notice Returns base64 encoded JSON metadata - anti-sniping protection!
    /// @dev Each token has base64 encoded JSON stored in SSTORE2, returned as data URI
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");

        // Before reveal every token resolves to the single pre-reveal blob;
        // after reveal each token resolves to its own per-token pointer.
        address metadataPointer = revealed ? tokenMetadata[tokenId] : prerevealPointer;
        require(
            metadataPointer != address(0),
            revealed ? "Metadata not set for token" : "Pre-reveal metadata not set"
        );

        // Read base64 encoded JSON from SSTORE2
        bytes memory base64EncodedJson = SSTORE2.read(metadataPointer);

        // Return as data URI with base64 prefix
        return string.concat(
            "data:application/json;base64,",
            string(base64EncodedJson)
        );
    }
    // NOTE: ERC-4906's interface id (0x49064906) is already advertised by SeaDrop's
    // inherited supportsInterface(), so no override is needed here.
}
