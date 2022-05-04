// SPDX-License-Identifier: CC0-1.0

/// @title Seeder contract for Enchanted Portals & Passages

/* Description to be written

Description to be written
Description to be written
Description to be written

// To do
- ...


*/

pragma solidity ^0.8.0;

contract PortalsSeeder {
    // —————————————— //
    // ——— Global ——— //
    // —————————————— //

    // —————————————————— //
    // ——— Main logic ——— //
    // —————————————————— //

    /**
     * @dev Generates a random seed from a tokenId + blockhash for each mint.
     *      There are more unpredictable approaches but this should be sufficient for initial mint/claim.
     *      We'll bitshift this seed to get pseudorandom numbers
     */
    function getSeed(uint256 tokenId) external view returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(block.timestamp, tokenId))));
    }

    // ———————————————————————— //
    // ——— Helper Functions ——— //
    // ———————————————————————— //

    /**
     * @dev Returns a random (deterministic) seed between 0-range based on an arbitrary set of inputs
     */
    function random(
        uint256 input,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        uint256 output = (uint256(keccak256(abi.encodePacked(input))) %
            (max - min)) + min;
        return output;
    }
}
