// SPDX-License-Identifier: CC0-1.0

/// @title Interface for Portals & Passages seeder contract

pragma solidity ^0.8.0;

interface IPortalsSeeder {
    function getSeed(uint256 tokenId) external view returns (uint256);

    function getSize(uint256 seed) external view returns (uint8);

    function getEnvironment(uint256 seed) external view returns (uint8);

    function getName(uint256 seed)
        external
        view
        returns (
            string memory,
            string memory,
            uint8
        );
}
