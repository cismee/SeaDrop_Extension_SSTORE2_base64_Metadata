#!/usr/bin/env python3
"""Generate mock on-chain metadata for the OnchainMetadataSeaDrop collection.

Produces data/nfts/token_001.json ... token_<MAX_SUPPLY>.json, matching the file
naming expected by script/UploadMetadata.s.sol (3-digit zero-padded token IDs).

Supply is configurable to match the contract's runtime maxSupply():
    MAX_SUPPLY=4000 python3 script/gen_mock_metadata.py   # any value
Defaults to 512 when MAX_SUPPLY is unset.

Deterministic: re-running yields identical files (seeded per token ID).
"""

import json
import os

COLLECTION_NAME = "OnchainMetadataSeaDrop"
# Collection size — override via the MAX_SUPPLY env var to match your deploy.
MAX_SUPPLY = int(os.environ.get("MAX_SUPPLY", "512"))
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "nfts")

# Trait pools (trait_type -> list of possible values).
TRAITS = {
    "Background": ["Cobalt", "Sunset", "Mint", "Charcoal", "Lavender", "Sand", "Crimson", "Teal"],
    "Body": ["Bronze", "Silver", "Gold", "Obsidian", "Jade", "Ivory"],
    "Eyes": ["Calm", "Laser", "Sleepy", "Wide", "Visor", "Glowing"],
    "Mouth": ["Grin", "Frown", "Smirk", "Open", "Pipe", "Neutral"],
    "Headwear": ["None", "Crown", "Cap", "Halo", "Bandana", "Top Hat"],
    "Accessory": ["None", "Chain", "Earring", "Scarf", "Badge", "Cape"],
}

RARITY_TIERS = ["Common", "Common", "Common", "Uncommon", "Uncommon", "Rare", "Legendary"]


def trait_value(pool, token_id, salt):
    """Pick a deterministic value from a pool based on token id and a salt."""
    return pool[(token_id * 31 + salt * 7 + len(pool)) % len(pool)]


def build_metadata(token_id):
    attributes = []
    for salt, (trait_type, pool) in enumerate(TRAITS.items()):
        value = trait_value(pool, token_id, salt)
        if value == "None":
            continue  # Skip empty traits, per common marketplace convention.
        attributes.append({"trait_type": trait_type, "value": value})

    rarity = RARITY_TIERS[token_id % len(RARITY_TIERS)]
    attributes.append({"trait_type": "Rarity", "value": rarity})
    attributes.append({"display_type": "number", "trait_type": "Edition", "value": token_id})

    return {
        "name": f"{COLLECTION_NAME} #{token_id}",
        "description": (
            f"{COLLECTION_NAME} is a fully on-chain 512-piece collection with "
            "base64-encoded metadata stored via SSTORE2. This is mock metadata "
            "for token "
            f"#{token_id}."
        ),
        "image": f"ipfs://bafybeigdyrmockcidplaceholderxxxxxxxxxxxxxxxxxxxxxxxx/{token_id}.png",
        "external_url": f"https://example.com/token/{token_id}",
        "attributes": attributes,
    }


def build_prereveal():
    """Single placeholder shown for every token until reveal()."""
    return {
        "name": f"{COLLECTION_NAME} (Unrevealed)",
        "description": (
            f"This {COLLECTION_NAME} token has not been revealed yet. Metadata and "
            "artwork are revealed on-chain once the collection is unveiled."
        ),
        "image": "ipfs://bafybeigdyrmockcidplaceholderxxxxxxxxxxxxxxxxxxxxxxxx/prereveal.png",
        "attributes": [
            {"trait_type": "Status", "value": "Unrevealed"},
        ],
    }


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for token_id in range(1, MAX_SUPPLY + 1):
        meta = build_metadata(token_id)
        path = os.path.join(OUT_DIR, f"token_{token_id:03d}.json")
        with open(path, "w") as f:
            json.dump(meta, f, indent=2)
            f.write("\n")

    # Single shared pre-reveal blob, written alongside data/ (not in data/nfts/).
    prereveal_path = os.path.join(OUT_DIR, "..", "prereveal.json")
    with open(prereveal_path, "w") as f:
        json.dump(build_prereveal(), f, indent=2)
        f.write("\n")

    print(f"Wrote {MAX_SUPPLY} token files to {os.path.normpath(OUT_DIR)}")
    print(f"Wrote pre-reveal blob to {os.path.normpath(prereveal_path)}")


if __name__ == "__main__":
    main()
