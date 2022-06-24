// SPDX-License-Identifier: CC0-1.0

/// @title Interface for Portals & Passages

pragma solidity ^0.8.0;

interface PortalsInterface {
    enum SalePhase {
        NotOpen,
        PreSale,
        PublicSale
    }
    struct Ecosystem {
        string name;
        uint16 minTokenId;
        uint16 maxTokenId;
        bool isEnabled;
    }
    struct PortalLocationsStore {
        uint8 currentEcosystemId;
        mapping(uint8 => uint16) locationMapping; // Maps each ecosystemId to the Portal locationId in this ecosystem
    }

    // Mint
    function updateSalePhase(SalePhase _saleStatus) external;

    function togglePublicSale(bool saleState) external;

    function mint(uint8 ecosystemId, uint16 locationId) external payable;

    function mintMany(
        uint8 amount,
        uint8[] memory ecosystemIdArray,
        uint16[] memory locationIdArray
    ) external payable;

    function ownerClaim(
        uint16 tokenId,
        uint8 ecosystemId,
        uint16 locationId
    ) external payable;

    function totalUnearthed() external;

    // Generation, location
    function toggleIsLocationChangeable() external;

    function toggleIsEcosystemEnabled(uint8 ecosystemId, bool enableState)
        external;

    function addEcosystem(
        string memory name,
        uint16 minTokenId,
        uint16 maxTokenId,
        bool isEnabled
    ) external;

    function changeLocation(
        uint16 tokenId,
        uint8 newEcosystemId,
        uint16 newLocationId
    ) external;

    // API
    function tokenURI(uint16 tokenId) external view returns (string memory);

    function getLocation(uint16 tokenId) external view returns (uint8, uint16);

    // Admin
    function setRoyalty(uint256 percentage, address receiver) external;

    function royaltyInfo(uint16 tokenId, uint256 salePrice) external view;

    function withdraw(address payable recipient) external;

    function deposit() external payable;
}
