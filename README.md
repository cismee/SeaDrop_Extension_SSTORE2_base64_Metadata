## Overview

OnchainMetadataSeaDrop is an NFT collection that stores base64-encoded metadata directly on the blockchain using SSTORE2 for gas-efficient storage. The collection integrates with SeaDrop for marketplace functionality and creator fee enforcement.

Originally created for and implemented via (Fauvtoshi)[https://opensea.io/collection/fauvtoshi]

> FAUV•TOSHI is an experimental generative fauvist onchain NFT collection linking to fully inscribed Bitcoin Ordinals, with contract-level metadata Base. Each token renders a 3600×3600px recursive SVG outputting an immutable print-ready 300DPI PNG.

> It’s both an NFT and an Ordinal: the token, and its metadata, lives onchain on Base for speed and accessibility, while the artwork lives on Bitcoin for permanence and provenance. Two chains. 512 works. Onchain. Learn more @ fauvtoshi.xyz.

### Why On-Chain Metadata

Storing metadata on-chain isn't just the more decentralized and optimal choice — it has a concrete, practical payoff for how you pay for storage:

- **No dependency on a pinning service.** Metadata lives in contract bytecode via SSTORE2, so there's nothing to keep pinned, re-pin, or migrate. It persists as long as the chain does, with no recurring off-chain hosting.
- **It saves on file-count–based subscriptions.** Pinning providers like [Pinata](https://pinata.cloud/) price and limit plans by **file count**, not just total bytes. A traditional collection uploads one JSON file per token — a 4k collection is 4,000 files (8,000 if you also pin images) counting against your account before you've stored a single byte of "real" data. Moving metadata on-chain removes all of those files from your account, leaving that quota for assets that genuinely need off-chain hosting (or letting you drop to a smaller, cheaper tier).

> ⚠️ **On-chain metadata ≠ zero external dependencies — just fewer.** This contract stores the metadata **JSON** on-chain, but each token's `image` (and any `animation_url`) is still a URL *inside* that JSON. The artwork is only as durable as wherever it's hosted:
> - **Arweave** (`ar://…`) — pay-once permanent storage; gives the images on-chain-like permanence to match the metadata. Best choice for a fully durable collection.
> - **IPFS** (`ipfs://…`) — content-addressed, but **not** automatically permanent. You must keep it pinned (your own node or a pinning service) or the content can disappear.
> - **Centralized HTTP** (`https://…`) — convenient but a single point of failure; it lasts only as long as you keep paying to host it.
>
> So putting metadata on-chain removes the per-token JSON hosting dependency, but unless you also host the assets on Arweave (or encode small/SVG art on-chain), the JSON will be permanent while the artwork remains as durable as your pinning/hosting. The mock metadata in this repo uses placeholder `ipfs://` image URLs — swap in your real, durably-hosted asset URIs before deploying.

### Key Features

- **Fully On-Chain**: All metadata stored permanently on Base Mainnet  
- **Pre-Reveal / Reveal**: Single shared placeholder blob until a one-way on-chain reveal  
- **ERC-4906**: Emits `MetadataUpdate` / `BatchMetadataUpdate` so marketplaces auto-refresh on changes and reveal  
- **Gas-Optimized**: SSTORE2 storage pattern for efficient on-chain data  
- **SeaDrop Integration**: Built-in marketplace protocol support  
- **Immutable**: Optional metadata finalization for permanent locking  
- **Configurable Supply**: Collection size is set at deploy via the inherited `setMaxSupply()`; token IDs start at 1  

## Technical Architecture

### Storage Pattern

```
JSON Metadata → Base64 Encode → SSTORE2 Deploy → Pointer Stored in Contract
```

Each token's metadata is:
1. Base64 encoded for obfuscation  
2. Deployed as bytecode via SSTORE2  
3. Referenced by pointer address in main contract  
4. Retrieved via `tokenURI()` as data URI  

### Contract Components

- **OnchainMetadataSeaDrop.sol** – Main ERC721 contract with metadata management  
- **SSTORE2** – Gas-efficient on-chain storage library (Solmate); used by the contract to read blobs and by the scripts to write them  
- **Base64** – Encoding library (OpenZeppelin v4.7.0, bundled with SeaDrop); used by the scripts to encode JSON before storage  
- **ERC721SeaDrop** – Base NFT implementation with marketplace integration (supplies minting, ownership, `maxSupply()`, ownership/royalty admin)  

### Pre-Reveal / Reveal

The collection ships in a **pre-reveal** state and is flipped to **revealed** by a one-way owner call:

```
Pre-reveal:  every tokenURI(id) → single shared `prerevealPointer` blob
reveal()  →  one-way switch (revealed = true)
Revealed:    every tokenURI(id) → that token's own `tokenMetadata[id]` blob
```

- `setPrerevealMetadata(pointer)` – owner sets the single shared placeholder blob. While `revealed == false`, **every** token returns this blob, so nothing about the final art/traits is exposed.
- `reveal()` – one-way switch; after it, `tokenURI` resolves each token to its own pointer. Upload all per-token metadata **before** calling this, or revealed tokens without metadata will revert in `tokenURI`.
- `finalizeMetadata()` – optional, locks both the pre-reveal pointer and per-token metadata against further changes.

### Configurable Supply

The collection has **no hard-coded supply**. Rather than defining its own constant, the contract uses the `maxSupply()` / `setMaxSupply()` mechanism it already inherits from SeaDrop's `ERC721ContractMetadata`, so there's a single source of truth and no second value to keep in sync.

- **Set at deploy.** `Deploy.s.sol` reads the `MAX_SUPPLY` env var and calls `setMaxSupply(MAX_SUPPLY)` right after deployment — set it to any value (512, 4000, 10000, …).
- **Changeable later.** As the owner you can call `setMaxSupply(newSupply)` again at any time (SeaDrop only forbids lowering it below the number already minted).
- **Used everywhere consistently.** Token-ID validation in `setTokenMetadata` / `batchSetTokenMetadata` and the `getMetadataCount` / `getTokensWithMetadata` loops all read `maxSupply()`, so changing supply automatically adjusts the valid token-ID range — no redeploy needed.
- **Token IDs start at 1** and run to `maxSupply()` inclusive.

> Make sure `maxSupply()` is set before uploading per-token metadata — with supply `0`, every `setTokenMetadata` call reverts with `Invalid token ID`.

## Contract Reference

`OnchainMetadataSeaDrop` extends `ERC721SeaDrop`, so it has the full SeaDrop/ERC721A surface (minting, transfers, ownership, royalties) plus the on-chain-metadata and reveal logic documented here.

### State

| Variable | Type | Meaning |
| --- | --- | --- |
| `tokenMetadata(uint256)` | `address` | Per-token SSTORE2 pointer to that token's base64-encoded JSON. `address(0)` = unset. |
| `prerevealPointer` | `address` | SSTORE2 pointer to the single shared pre-reveal blob. |
| `revealed` | `bool` | `false` → `tokenURI` serves the pre-reveal blob; `true` → per-token metadata. One-way. |
| `metadataFinalized` | `bool` | When `true`, metadata is permanently locked (no further pointer changes). |
| `maxSupply()` | `uint256` | Collection size (inherited from SeaDrop; set via `setMaxSupply()`). |

### Events

| Event | Emitted when |
| --- | --- |
| `PrerevealMetadataSet(address indexed pointer)` | `setPrerevealMetadata` sets the shared blob. |
| `Revealed()` | `reveal()` flips the collection to revealed. |
| `MetadataUpdate(uint256 _tokenId)` *(ERC-4906)* | A single token's pointer is set/changed via `setTokenMetadata` (one per token in `batchSetTokenMetadata`). |
| `BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId)` *(ERC-4906, inherited)* | A collection-wide change: `setPrerevealMetadata` and `reveal()` emit `(1, maxSupply())`. |
| `MaxSupplyUpdated(uint256)` *(inherited)* | `setMaxSupply()` changes the supply. |

> **ERC-4906 (Metadata Update Extension).** The contract emits these standard events whenever on-chain metadata changes so marketplaces auto-refresh `tokenURI` — single-token `MetadataUpdate` on per-token sets, and a full-range `BatchMetadataUpdate(1, maxSupply())` on pre-reveal changes and on reveal. `supportsInterface(0x49064906)` returns `true` (advertised via SeaDrop's inherited implementation).

### Owner functions (metadata & config)

All are `onlyOwner`. The four metadata setters also require `metadataFinalized == false`.

| Function | Description | Key reverts |
| --- | --- | --- |
| `setMaxSupply(uint256 newMaxSupply)` *(inherited)* | Set/raise collection size. | `< totalMinted` (SeaDrop) |
| `setTokenMetadata(uint256 tokenId, address pointer)` | Point one token at its SSTORE2 blob. | `Metadata is finalized`; `Invalid token ID` (outside `1..maxSupply()`) |
| `batchSetTokenMetadata(uint256[] tokenIds, address[] pointers)` | Set up to **3** tokens per call. | `Array length mismatch`; `Batch too large` (>3); `Invalid token ID` |
| `setPrerevealMetadata(address pointer)` | Set the single shared pre-reveal blob. | `Metadata is finalized`; `Invalid pointer` (zero address) |
| `reveal()` | One-way switch to per-token metadata. | `Already revealed` |
| `finalizeMetadata()` | Permanently lock all metadata. | — |

### View functions

| Function | Returns |
| --- | --- |
| `tokenURI(uint256 tokenId)` | `data:application/json;base64,<blob>` — the pre-reveal blob before reveal, the per-token blob after. Reverts `Token does not exist` (unminted), `Pre-reveal metadata not set`, or `Metadata not set for token`. |
| `hasMetadata(uint256 tokenId)` | `bool` — whether that token has a per-token pointer. |
| `getMetadataCount()` | `uint256` — number of tokens (1..`maxSupply()`) with a per-token pointer set. O(n) loop; view-only. |
| `getTokensWithMetadata()` | `uint256[]` — the token IDs that have a per-token pointer. O(n) loop; view-only. |
| `maxSupply()` *(inherited)* | `uint256` — current collection size. |
| `name()` / `symbol()` / `owner()` / `totalSupply()` / `ownerOf()` / `balanceOf()` *(inherited)* | Standard ERC721/SeaDrop reads. |

### Minting

Minting is handled by SeaDrop, not this contract directly:

| Function | Access | Description |
| --- | --- | --- |
| `mintSeaDrop(address minter, uint256 quantity)` *(inherited)* | `onlySeaDrop` | Called by the SeaDrop protocol contract during an active drop; mints sequential IDs starting at 1, bounded by `maxSupply()`. |

Public/allowlist/token-gated drop parameters (price, mint windows, allowlists) are configured on the SeaDrop contract via SeaDrop's own admin calls — see the [SeaDrop docs](https://github.com/ProjectOpenSea/seadrop). This repo focuses on the metadata/reveal layer.

## Lifecycle & Flows

### `tokenURI(id)` resolution

```
tokenURI(id)
  ├─ require token id minted ............................ else "Token does not exist"
  ├─ revealed == false ?
  │     → pointer = prerevealPointer ................... else "Pre-reveal metadata not set"
  │     → return data URI of the SHARED blob (same for every id)
  └─ revealed == true ?
        → pointer = tokenMetadata[id] ................... else "Metadata not set for token"
        → return data URI of THIS token's blob
```

### Operator launch flow (end to end)

```
1. deploy            new OnchainMetadataSeaDrop(name, symbol, seaDrop)   → Deploy.s.sol
2. set supply        setMaxSupply(N)                                     → Deploy.s.sol (from MAX_SUPPLY)
3. set pre-reveal    setPrerevealMetadata(blob)                          → SetPrereveal.s.sol
4. configure drop    (price / mint window / allowlist on SeaDrop)        → SeaDrop admin (out of scope here)
5. mint window       buyers mint → mintSeaDrop(...) → all show placeholder
6. upload reveal      setTokenMetadata / batchSetTokenMetadata (×N)      → UploadMetadata.s.sol
7. reveal            reveal()  (one-way)                                 → Reveal.s.sol
8. (optional) lock   finalizeMetadata()  (permanent)                     → cast send
```

Steps 3 and 6 can each be done before or after minting; the only ordering rule is **finish step 6 before step 7**, or revealed tokens that lack a pointer will revert in `tokenURI`. After step 8, none of the metadata (pre-reveal pointer or per-token pointers) can change again.

### Holder / marketplace view

A wallet or marketplace only ever calls `tokenURI(id)`:

- **Before `reveal()`** → every token returns the identical pre-reveal placeholder.
- **After `reveal()`** → each token returns its own fully on-chain metadata, served directly as a base64 data URI (no IPFS/HTTP fetch).

### Correcting Metadata (typos & re-uploads)

**Metadata stays editable until you call `finalizeMetadata()`.** Calling `reveal()` does *not* lock anything — it only changes which pointer `tokenURI` reads. So a typo can be fixed at any point before finalize, whether the collection is still pre-reveal or already revealed.

Each correction writes a **new** SSTORE2 blob and repoints the contract at it; the old blob stays on-chain but unreferenced (orphaned). That's expected and harmless — it just costs the gas of the new write. Every correction also emits the relevant ERC-4906 event (`MetadataUpdate` for a single token, `BatchMetadataUpdate` for a pre-reveal change), so compliant marketplaces refresh the affected `tokenURI`(s) automatically — no manual "refresh metadata" click needed.

> ⚠️ `UploadMetadata.s.sol` is resume-only: it **skips** any token that already has a pointer, so it will not overwrite a typo. Use the targeted scripts below to make corrections.

**Fix the pre-reveal placeholder** (only affects what's shown before reveal):

```bash
# 1. edit data/prereveal.json
# 2. re-run SetPrereveal — it overwrites prerevealPointer unconditionally
forge script script/SetPrereveal.s.sol:SetPrereveal \
  --broadcast --rpc-url $BASE_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY --chain 8453
```

**Fix a single token** (works the same before or after reveal):

```bash
# 1. edit data/nfts/token_042.json
# 2. overwrite just that token via FixMetadata (TOKEN_ID selects which one)
TOKEN_ID=42 forge script script/FixMetadata.s.sol:FixMetadata \
  --broadcast --rpc-url $BASE_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY --chain 8453
```

Need to correct many tokens at once? Either run `FixMetadata` per token ID, or call `batchSetTokenMetadata` (up to 3 tokens per call) with freshly written pointers.

> ⚠️ After `finalizeMetadata()` **no correction is possible** — the pre-reveal pointer and every per-token pointer are permanently locked. Only finalize once you're confident the metadata is correct (ideally verify a sample of `tokenURI` outputs first).

## Scripts

All scripts live in `script/` and read `DEPLOYER` / `CONTRACT_ADDRESS` (and `MAX_SUPPLY` for deploy) from the environment.

| Script | Purpose | Notes |
| --- | --- | --- |
| `Deploy.s.sol` | Deploy the contract and apply `setMaxSupply(MAX_SUPPLY)`. | Mainnet safety checks (chain id 8453, deployer balance ≥ 0.05 ETH). |
| `SetPrereveal.s.sol` | Encode `data/prereveal.json`, write to SSTORE2, call `setPrerevealMetadata`. | Run once before reveal. |
| `UploadMetadata.s.sol` | Encode each `data/nfts/token_NNN.json`, write to SSTORE2, call `setTokenMetadata`. | Resume-only — **skips** tokens that already have a pointer; safe to re-run, but won't overwrite. |
| `FixMetadata.s.sol` | Overwrite **one** token's metadata to fix a typo. | `TOKEN_ID=<n> forge script ...`. Always overwrites; works pre- and post-reveal; blocked by `finalizeMetadata()`. |
| `Reveal.s.sol` | Call `reveal()` (one-way). | Warns if `getMetadataCount() < maxSupply()`. |
| `TestSingleUpload.s.sol` | Upload just token 1 as a smoke test. | Useful for verifying gas/permissions on a fresh deploy. |
| `gen_mock_metadata.py` | Generate mock `data/prereveal.json` + `data/nfts/token_NNN.json`. | `MAX_SUPPLY=<n> python3 script/gen_mock_metadata.py`; deterministic. |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed  
- Base Mainnet RPC URL  
- Private key with sufficient ETH (≥0.05 ETH recommended)  
- BaseScan API key (for verification)  

## Installation

```bash
# Clone repository
git clone <your-repo-url>
cd onchain-metadata-seadrop

# Install dependencies
forge install

# Create environment file
cp .env.example .env
```
## Deployment
```
DEPLOYER=0xYourDeployerAddress
PRIVATE_KEY=your_private_key_here
```

## Network
```
BASE_MAINNET_RPC_URL=https://mainnet.base.org
BASESCAN_API_KEY=your_basescan_api_key
```

## Contract (set after deployment)
```
CONTRACT_ADDRESS=
```

## Deployment Guide

> 💡 **Do a full dry-run on a cheap L2 first.** Before your real production deployment, run this entire flow — deploy, `setMaxSupply`, set pre-reveal, upload **all** per-token metadata, reveal, and a few `tokenURI` spot-checks — on a low-cost network (a testnet like **Base Sepolia** / **OP Sepolia**, or a cheap L2 mainnet like **Base** or **Optimism**). On-chain metadata means one SSTORE2 deploy per token, so a large collection is hundreds/thousands of transactions; a dry-run surfaces gas costs, batch sizing, and any bad metadata files before you commit real funds on your production chain. The included `base-sepolia` RPC in `foundry.toml` is a good target — just point `--rpc-url` and `--chain` at it.

### Step 1: Run Tests

```
forge test -vv
```

### Step 2: Deploy Contract

Set `MAX_SUPPLY` to your collection size first (any value) — the deploy script applies it via `setMaxSupply()`:

```
export MAX_SUPPLY=512   # or 4000, 10000, ... whatever your collection is

forge script script/Deploy.s.sol:Deploy \
  --broadcast \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --chain 8453
```

### Safety Checks:

- Checks deployer balance (≥0.05 ETH required)
- Applies the configured `MAX_SUPPLY` via `setMaxSupply()`
- Displays deployment info and next steps
- Save the contract address displayed in the output.

### Step 3: Update Environment

```
export CONTRACT_ADDRESS=<deployed_contract_address>
```

### Step 4: Verify Contract

```
forge verify-contract \
  --chain-id 8453 \
  --rpc-url $BASE_MAINNET_RPC_URL \
  --etherscan-api-key $BASESCAN_API_KEY \
  <contract_address> \
  src/OnchainMetadataSeaDrop.sol:OnchainMetadataSeaDrop \
  --constructor-args $(cast abi-encode "constructor(string,string,address)" "OnchainMetadataSeaDrop" "NFT" "0x00005EA00Ac477B1030CE78506496e8C2dE24bf5")
```

### Step 5: Set Pre-Reveal Metadata

Deploy the single shared placeholder blob (from `data/prereveal.json`) and point the contract at it. Every token returns this until reveal.

```
forge script script/SetPrereveal.s.sol:SetPrereveal \
  --broadcast --rpc-url $BASE_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY --chain 8453
```

### Step 6: Upload Per-Token Metadata

Push each token's revealed blob (from `data/nfts/token_XXX.json`). Safe to run repeatedly — it resumes from the last uploaded token.

```
forge script script/UploadMetadata.s.sol:UploadMetadata \
  --broadcast --rpc-url $BASE_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY --chain 8453
```

> This script is **resume-only**: it skips tokens that already have a pointer, so re-running it will *not* overwrite a token that was uploaded with a typo. To correct an already-uploaded token, use `FixMetadata.s.sol` — see [Correcting Metadata](#correcting-metadata-typos--re-uploads).

### Step 7: Reveal

One-way switch from the pre-reveal blob to per-token metadata. Run **after** all per-token metadata is uploaded (the script warns if any is missing).

```
forge script script/Reveal.s.sol:Reveal \
  --broadcast --rpc-url $BASE_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY --chain 8453
```

> Revealing does **not** lock metadata — you can still correct typos after this step (see below). It only changes which pointer `tokenURI` reads.

### Step 8: Verify, Fix, and (Optionally) Finalize

Before locking anything, spot-check a few tokens:

```
cast call <contract_address> "tokenURI(uint256)(string)" 1 --rpc-url $BASE_MAINNET_RPC_URL
```

If you spot a mistake, fix it — this works whether or not you've already revealed (full details in [Correcting Metadata](#correcting-metadata-typos--re-uploads)):

```
# pre-reveal placeholder: edit data/prereveal.json, then re-run SetPrereveal
# a single token:         edit data/nfts/token_NNN.json, then:
TOKEN_ID=<n> forge script script/FixMetadata.s.sol:FixMetadata \
  --broadcast --rpc-url $BASE_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY --chain 8453
```

Once everything is correct, optionally lock metadata **permanently** (irreversible — no further corrections possible):

```
cast send <contract_address> "finalizeMetadata()" \
  --rpc-url $BASE_MAINNET_RPC_URL --private-key $PRIVATE_KEY
```

## Metadata Preparation

The mock metadata under `data/` is generated by `script/gen_mock_metadata.py` (`python3 script/gen_mock_metadata.py`). Replace it with your real metadata before deploying. The generator emits one file per token up to `MAX_SUPPLY`, so update it to match your configured supply.

> The generated files use placeholder `ipfs://…` `image` URLs. These point to **off-chain** assets — make sure they resolve to your real artwork and that it's durably hosted (Arweave for permanence, or a reliably-pinned IPFS CID). See the dependency note under [Why On-Chain Metadata](#why-on-chain-metadata). The metadata JSON being on-chain does not make the images on-chain.

Single shared pre-reveal placeholder:
```
data/prereveal.json
```

Per-token revealed metadata in data/nfts/ directory, one zero-padded file per token (1 … `MAX_SUPPLY`):
```
data/nfts/token_001.json
data/nfts/token_002.json
...
```
