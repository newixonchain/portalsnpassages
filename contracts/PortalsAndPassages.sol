// SPDX-License-Identifier: CC0-1.0

/// @title Enchanted Portals & Passages

/* Description to be written

Description to be written
Description to be written
Description to be written
Description to be written

The portal API aims to be simple and is aimed at smart contract developers wanting to create onchain games:

getLineage(uint256 tokenId) - Returns ...
getGem(uint256 tokenId) - Returns ...
getNumFacets(uint256 tokenId) - Returns ...
getNumAncientImprints(uint256 tokenId) - Returns ...
getLocation(uint256 tokenId) - Returns ...
getType(uint256 tokenId) - Returns ...
getName(uint256 tokenId) - Returns a string with the portal name. Names may be repeated across portals.
getSvg(uint256 tokenId) - Returns a base64 encrypted svg with a visual representation of the portal.

// To do
- isInAllowList() -> check okpc MerkleProof usage https://etherscan.io/address/0x7183209867489E1047f3A7c23ea1Aed9c4E236E8#code
- what happens if a mintMany() goes through only for some and not for all?!


*/

pragma solidity ^0.8.0;

/* OpenZeppelin reference contracts */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/* Dependencies */
import {IPortals} from "../interfaces/IPortals.sol";

interface CryptsAndCavernsInterface {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

interface RealmsInterface {
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract PortalsAndPassages is
    IPortals,
    ERC721,
    IERC2981,
    ReentrancyGuard,
    Ownable
{
    // —————————————— //
    // ——— Global ——— //
    // —————————————— //

    // Using for
    using Counters for Counters.Counter;

    // Contracts
    CryptsAndCavernsInterface internal cncContract =
        CryptsAndCavernsInterface(0x86f7692569914b5060ef39aab99e62ec96a6ed45);
    RealmsInterface internal realmsContract =
        RealmsInterface(0x7afe30cb3e53dba6801aa0ea647a0ecea7cbe18d);
    IPortalsSeeder public seeder;

    // Project info
    uint16 public constant TOTAL_PUBLIC_SUPPLY = 966;
    uint16 public constant TOTAL_SUPPLY = 999;
    uint256 public constant MINT_PRICE = 0.05 ether;
    uint8 public constant MAX_MINT_PER_TRANSACTION = 20;

    // Royalty
    uint256 public royaltyPercentage;
    address public royaltyAddress;

    // Contract's state
    SalePhase public saleStatus = SalePhase.NotOpen;
    Counters.Counter private countMinted;
    Counters.Counter private countClaimed;
    bool public isLocationChangeable = false;

    // Portals inventory
    mapping(uint16 => uint256) public seeds; // Store seeds for the portals

    // Compatible ecosystems and portals locations
    Ecosystem[] public compatibleEcosystems;
    mapping(uint16 => PortalLocationsStore) public locationsInventory; // Store portals locations in each ecosystem

    // —————————————— //
    // ——— Events ——— //
    // —————————————— //

    event UnearthingInitialized();
    event SalePhaseChanged(SalePhase _saleStatus);
    event Minted(address indexed _account, uint16 _tokenId);
    event Claimed(address indexed _account, uint16 _tokenId);
    event IsLocationChangeableToggled(bool _status);
    event IsEcosystemEnabledChanged(uint8 _ecosystemId, bool _enableState);
    event EcosystemAdded(
        string _name,
        uint16 _minTokenId,
        uint16 _maxTokenId,
        bool _isEnabled
    );
    event LocationChanged(
        uint16 _tokenId,
        uint8 _previousEcosystemId,
        uint16 _previousLocationId,
        uint8 _newEcosystemId,
        uint16 _newLocationId
    );

    // —————————————— //
    // ——— Errors ——— //
    // —————————————— //

    // Sale phases, amounts, supply
    error SaleNotOpenedYet();
    error SenderNotInPreSaleAllowList();
    error AmountToMintInvalid(
        uint16 _amountToMint,
        uint8 _maxMintPerTransaction
    );
    error EthAmountInsufficient(
        uint256 _ethAmountSent,
        uint256 _ethAmountRequired
    );
    error NotEnoughSupplyLeft(uint16 _amountToMint, uint16 _supplyLeft);

    // Mint
    error ArraysLengthsMustBeEqual(
        uint8 _amount,
        uint8 _ecosystemIdArray,
        uint16 _locationIdArray
    );

    // Locations
    error LocationInvalidInEcosystem(
        uint8 _ecosystemId,
        uint16 _locationId,
        uint16 _minTokenId,
        uint16 _maxTokenId
    );
    error EcosystemCurrentlyNotEnabled(uint8 _ecosystemId);
    error LocationCurrentlyNotChangeable();
    error SenderIsNotOwnerOfToken(address _sender, uint16 _tokenId);
    error TokenIdInvalid(uint16 _tokenId);
    error PortalNotUnearthedYet(uint16 _tokenId);
    error CannotMoveWithinSameEcosystem();
    error CannotChangeLocationWhenGoingBackToPreviousEcosystem(
        uint16 _previousLocationIdInEcosystem,
        uint16 _requestedLocationIdInEcosystem
    );

    // ————————————————— //
    // ——— Modifiers ——— //
    // ————————————————— //

    modifier isSaleOpened() {
        if (saleStatus == SalePhase.NotOpen) revert SaleNotOpenedYet();
        _;
    }

    modifier isSenderAllowed() {
        assert(saleStatus != SalePhase.NotOpen);
        if (saleStatus == SalePhase.PreSale && !isInAllowList(msg.sender))
            revert SenderNotInPreSaleAllowList();
        _;
    }

    modifier isPaymentValid(uint256 _amount) {
        if (_amount > MAX_MINT_PER_TRANSACTION)
            revert AmountToMintInvalid(_amount, MAX_MINT_PER_TRANSACTION);
        if (MINT_PRICE * _amount != msg.value)
            revert EthAmountInsufficient(msg.value, MINT_PRICE * _amount);
        _;
    }

    modifier isEnoughSupplyLeft(uint256 _amount) {
        if (countMinted.current() + _amount <= TOTAL_PUBLIC_SUPPLY)
            revert NotEnoughSupplyLeft(
                _amount,
                TOTAL_PUBLIC_SUPPLY - countMinted.current()
            );
        _;
    }

    modifier isLocationValid(uint8 _ecosystemId, uint16 _locationId) {
        if (!checkLocationValidity(_ecosystemId, _locationId))
            revert LocationInvalidInEcosystem(
                _ecosystemId,
                _locationId,
                compatibleEcosystems[_ecosystemId].minTokenId,
                compatibleEcosystems[_ecosystemId].maxTokenId
            );
        if (!checkEcosystemEnabled(_ecosystemId))
            revert EcosystemCurrentlyNotEnabled(_ecosystemId);
        _;
    }

    modifier isLocationChangeable() {
        if (!isLocationChangeable) revert LocationCurrentlyNotChangeable();
        _;
    }

    // —————————————————————————————————— //
    // ——— Public/Community Functions ——— //
    // —————————————————————————————————— //

    /* Write Functions */

    /**
     * @dev Allow a user to mint a token under conditions specific to the sale phase status.
     *       e.g. mint(1, 42);
     */
    function mint(uint8 _ecosystemId, uint16 _locationId)
        public
        payable
        override
        nonReentrant
        isSaleOpened
        isSenderAllowed
        isEnoughSupplyLeft(1)
        isPaymentValid(1)
        isLocationValid(_ecosystemId, _locationId)
    {
        mintEvent(_ecosystemId, _locationId);
    }

    /**
     * @dev Allow a user to mint several tokens at once during the Public Sale phase.
     *      e.g. mintMany(3, [1, 1, 2], [42, 1337, 42]);
     */
    function mintMany(
        uint8 _amount,
        uint8[] calldata _ecosystemIdArray,
        uint16[] calldata _locationIdArray
    )
        public
        payable
        override
        nonReentrant
        isSaleOpened
        isSenderAllowed
        publicSaleActive
        isEnoughSupplyLeft(_amount)
        isPaymentValid(_amount)
    {
        if (
            _ecosystemIdArray.length != _amount ||
            _locationIdArray.length != _amount
        )
            revert ArraysLengthsMustBeEqual(
                _amount,
                _ecosystemIdArray,
                _locationIdArray
            );
        for (uint256 i = 0; i < _amount; i++) {
            uint8 _ecosystemId = _ecosystemIdArray[i];
            uint16 _locationId = _locationIdArray[i];
            if (!checkEcosystemEnabled(_ecosystemId))
                revert EcosystemCurrentlyNotEnabled(_ecosystemId);
            if (!checkLocationValidity(_ecosystemId, _locationId))
                revert LocationInvalidInEcosystem(
                    _ecosystemId,
                    _locationId,
                    compatibleEcosystems[ecosystemId].minTokenId,
                    compatibleEcosystems[ecosystemId].maxTokenId
                );
        }
        for (uint256 i = 0; i < _amount; i++) {
            mintEvent(_ecosystemId, _locationId);
        }
    }

    /**
     * @dev Allow a user to change the location of their portal.
     *      e.g. changeLocation(1337, 3, 42)
     */
    function changeLocation(
        uint16 _tokenId,
        uint8 _newEcosystemId,
        uint16 _newLocationId
    )
        public
        nonReentrant
        isLocationChangeable
        isLocationValid(_newEcosystemId, _newLocationId)
    {
        isValid(_tokenId);
        if ((this).ownerOf(_tokenId) != msg.sender)
            revert SenderIsNotOwnerOfToken(msg.sender, _tokenId);
        (uint8 _oldEcosystemId, uint16 _oldLocationId) = (this).getLocation(
            _tokenId
        );
        // Check if the portal is already located in this ecosystem
        if (_oldEcosystemId == _newEcosystemId)
            revert CannotMoveWithinSameEcosystem();
        // Check if the portal already has a location in newEcosystem
        uint16 _previousLocationIdInEcosystem = locationsInventory[_tokenId]
            .locationMapping[_ecosystemId];
        if (
            _previousLocationIdInEcosystem != 0 &&
            _previousLocationIdInEcosystem != _newLocationId
        )
            revert CannotChangeLocationWhenGoingBackToPreviousEcosystem(
                _previousLocationIdInEcosystem,
                _newLocationId
            );
        // Set new location
        setLocation(_tokenId, _newEcosystemId, _newLocationId);
        emit LocationChanged(
            _tokenId,
            _oldEcosystemId,
            _oldLocationId,
            _newEcosystemId,
            _newLocationId
        );
    }

    // ———————————————————————— //
    // ——— Helper Functions ——— //
    // ———————————————————————— //

    function mintEvent(uint8 _ecosystemId, uint16 _locationId) internal {
        countMinted.increment();
        uint16 _tokenId = countMinted.current();
        seeds[_tokenId] = seeder.getSeed(_tokenId);
        setLocation(_tokenId, _ecosystemId, _locationId);
        _safeMint(_msgSender(), _tokenId);
        emit Minted(_msgSender(), _tokenId);
    }

    function setLocation(
        uint16 _tokenId,
        uint8 _ecosystemId,
        uint16 _locationId
    ) internal isLocationValid(_ecosystemId, _locationId) {
        locationsInventory[_tokenId].currentEcosystemId = _ecosystemId;
        locationsInventory[_tokenId].locationMapping[
            _ecosystemId
        ] = _locationId;
    }

    function isInAllowList(address _sender) internal view returns (bool) {
        // To do
        return false;
    }

    function isValid(uint16 _tokenId) internal view {
        if (!(_tokenId > 0 && _tokenId < TOTAL_SUPPLY))
            revert TokenIdInvalid(_tokenId);
        if (!_exists(_tokenId)) revert PortalNotUnearthedYet(_tokenId);
    }

    function totalUnearthed() public view returns (uint16) {
        return countMinted.current() + countClaimed.current();
    }

    function checkEcosystemEnabled(uint8 _ecosystemId) internal view {
        return compatibleEcosystems[_ecosystemId].isEnabled;
    }

    function checkLocationValidity(uint8 _ecosystemId, uint16 _locationId)
        internal
        view
    {
        return (locationId >= compatibleEcosystems[_ecosystemId].minTokenId &&
            locationId <= compatibleEcosystems[_ecosystemId].maxTokenId);
    }

    // —————————————————————————— //
    // ——— Portals generation ——— //
    // —————————————————————————— //

    // ——————————————————— //
    // ——— Portals API ——— //
    // ——————————————————— //

    function tokenURI(uint16 _tokenId)
        public
        view
        override(ERC721, PortalsInterface)
        returns (string memory)
    {
        isValid(_tokenId);
    }

    /**
     * @dev Returns the current ecosystem and location of the Portal
     * Example: (uint256 ecosystemId, uint256 locationId) = (1, 42);
     */
    function getLocation(uint16 _tokenId)
        public
        view
        override
        returns (uint8, uint16)
    {
        isValid(_tokenId);
        _ecosystemId = locationsInventory[_tokenId].currentEcosystemId;
        return (
            _ecosystemId,
            locationsInventory[_tokenId].locationMapping[_ecosystemId]
        );
    }

    /**
     * @dev Returns the Portal's Enchantment Lineage id
     * Example: uint256 lineageId = 6;
     */
    function getLineage(uint16 _tokenId) public view override returns (uint8) {
        isValid(_tokenId);
    }

    /**
     * @dev Returns the Portal's Enchantment Gem id
     * Example: uint256 gemId = 21;
     */
    function getGem(uint16 _tokenId) public view override returns (uint8) {
        isValid(_tokenId);
    }

    /**
     * @dev Returns the number of facets of the Portal
     * Example: uint256 numFacets = 1;
     */
    function getNumFacets(uint16 _tokenId)
        public
        view
        override
        returns (uint8)
    {
        isValid(_tokenId);
    }

    /**
     * @dev Returns the number of ancients imprints of the Portal
     * Example: uint256 numImprints = 2;
     */
    function getNumAncientImprints(uint16 _tokenId)
        public
        view
        override
        returns (uint8)
    {
        isValid(_tokenId);
    }

    /**
     * @dev Returns the Portal's type id, 0 for man-made artifact, 1 for natural point of interest
     * Example: uint256 typeId = 0;
     */
    function getType(uint16 _tokenId) public view override returns (uint8) {
        isValid(_tokenId);
    }

    /**
     * @dev Returns the Portal's name
     * Example: string name = 'Shimmering Cromlech of Hoj';
     */
    function getName(uint16 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        isValid(_tokenId);
    }

    /**
     * @dev Returns a string containing a valid SVG representing the dungeon
     * The SVG is pixel-art resolution so the game developer can interpret it as they see fit
     * Colors are based on 'getEnvironment()'
     * Example: string svg = "<svg><rect x='100' y='20' height='10' widdth='10' /></svg>"
     */
    function getSvg(uint16 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        isValid(_tokenId);
    }

    // ————————————————————————————— //
    // ——— Admin/Owner Functions ——— //
    // ————————————————————————————— //

    /**
     * @dev Enables owner to update the sale phase status
     */
    function updateSalePhase(SalePhase _saleStatus) external onlyOwner {
        saleStatus = _saleStatus;
        emit SalePhaseChanged(_saleStatus);
    }

    /**
     * @dev Enables owner to toggle the possibility to change a portal location
     */
    function toggleIsLocationChangeable(bool _status) external onlyOwner {
        isLocationChangeable = _status;
        emit IsLocationChangeableToggled(_status);
    }

    /**
     * @dev Enables owner to enable or disable location in an ecosystem
     */
    function toggleIsEcosystemEnabled(uint8 _ecosystemId, bool _enableState)
        external
        onlyOwner
    {
        compatibleEcosystems[_ecosystemId].isEnabled = _enableState;
        emit IsEcosystemEnabledChanged(_ecosystemId, _enableState);
    }

    /**
     * @dev Enables owner to add compatible ecosystems
     */
    function addEcosystem(
        string calldata _name,
        uint16 _minTokenId,
        uint16 _maxTokenId,
        bool _isEnabled
    ) external onlyOwner {
        compatibleEcosystems.push(
            Ecosystem(_name, _minTokenId, _maxTokenId, _isEnabled)
        );
        emit EcosystemAdded(_name, _minTokenId, _maxTokenId, _isEnabled);
    }

    /**
     * @dev   Allows newix to mint a set of portals to hold for promotional purposes and to reward contributors.
     *        e.g. ownerClaim(5555, 1, 42);
     */
    function ownerClaim(
        uint16 _tokenId,
        uint8 _ecosystemId,
        uint16 _locationId
    )
        public
        payable
        override
        nonReentrant
        onlyOwner
        isLocationValid(_ecosystemId, _locationId)
    {
        if (!(_tokenId > TOTAL_PUBLIC_SUPPLY && _tokenId <= TOTAL_SUPPLY))
            revert TokenIdInvalid(_tokenId);
        seeds[_tokenId] = seeder.getSeed(_tokenId);
        setLocation(_tokenId, _ecosystemId, _locationId);
        _safeMint(owner(), _tokenId);
        countClaimed.increment();
        emit Claimed(owner(), _tokenId);
    }

    // To do: decide what to do here
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(ERC721, IERC165)
        returns (bool)
    {
        return (_interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(_interfaceId));
    }

    /**
     * @dev  Allows the owner to set royalty parameters
     */
    function setRoyalty(uint256 _percentage, address _receiver)
        external
        onlyOwner
    {
        royaltyPercentage = _percentage;
        royaltyAddress = _receiver;
    }

    /**
     * @dev  Allows third party (e.g. marketplaces) to retrieve royalty information
     */
    function royaltyInfo(uint16 _tokenId, uint256 _salePrice)
        external
        view
        override
        returns (address, uint256)
    {
        return (royaltyAddress, (_salePrice * royaltyPercentage) / 10000);
    }

    /**
     * @dev  Allows the owner to withdraw eth to another wallet
     */
    function withdraw(address payable _recipient) external onlyOwner {
        payable(_recipient).transfer(address(this).balance);
    }

    /**
     * @dev  Allows the owner to withdraw any ERC20 to another wallet
     */
    function withdrawERC20(IERC20 _erc20Token, address payable _recipient)
        external
        onlyOwner
    {
        _erc20Token.transfer(_recipient, _erc20Token.balanceOf(address(this)));
    }

    constructor() ERC721("Portals & Passages", "PORTAL") {
        // Initialize compatible ecosystems
        compatibleEcosystems.push(Ecosystem(0, "Realms", 1, 8000));
        compatibleEcosystems.push(Ecosystem(1, "Crypts & Caverns", 1, 9000));

        emit UnearthingInitialized();
    }
}
