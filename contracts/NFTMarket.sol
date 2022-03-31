// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./Auction.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFT is ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    address contractAddress;

    constructor(address marketplaceAddress) ERC721("Digital Marketplace", "DMP") {
        contractAddress = marketplaceAddress;
    }

    function createToken(string memory tokenURI) public returns (uint) {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();

        _safeMint(msg.sender, newItemId);
        _setTokenURI(newItemId, tokenURI);
        setApprovalForAll(contractAddress, true);
        return newItemId;
    }

    function getTokenUri(uint _tokenId) public view returns(string memory){
        return tokenURI(_tokenId);
    }
}

contract PriceConsumerV3 {

    AggregatorV3Interface internal priceFeed;

    /**
     * Network: Polygon Testnet (Mumbai)
     * Aggregator: MATIC/USD
     * Address: 0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada
     */
    constructor() {
        priceFeed = AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e);
    }

    /**
     * Returns the latest price
     */
    function getLatestPrice() public view returns (uint256) {
        (
            ,int price,,,
        ) = priceFeed.latestRoundData();
        return uint256(price);
    }
}

contract NFTMarket is ReentrancyGuard, PriceConsumerV3, IERC721Receiver {
  using Counters for Counters.Counter;
  Counters.Counter public _itemIds;
  Counters.Counter private _itemsSold;

  address payable owner;
  uint256 listingPrice = 0 ether;

  uint _auctionIdCounter;
  mapping(uint => Auction) public auctions;
  mapping(address => bool) public auctionAllowance; 
  uint public len;

  constructor() PriceConsumerV3() {
    owner = payable(msg.sender);
  }

  modifier onlyAdmin(){
        require(msg.sender == owner);
        _;
   }

   

    function getAuctions() external view returns(address[] memory _auctions) {
        _auctions = new address[](_auctionIdCounter);
        for(uint i = 0; i < _auctionIdCounter; i++) {
            _auctions[i] = address(auctions[i]);
        }
        return _auctions;
    }

    function getAuctionInfo(address  _auctionAddr)
        external
        view
        returns (
            uint256,
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {

            uint256 directBuy = Auction(_auctionAddr).directBuyPrice();
            address maxBidder = Auction(_auctionAddr).maxBidder();
            uint256 highestBid = Auction(_auctionAddr).maxBid();
            uint256 itemId = Auction(_auctionAddr).itemId();
            uint256 endTime = Auction(_auctionAddr).endTime();
            uint256 startPrice = Auction(_auctionAddr).startPrice();
            uint256 auctionState = uint(Auction(_auctionAddr).getAuctionState());


        return (
            directBuy,
            maxBidder,
            highestBid,
            itemId,
            endTime,
            startPrice,
            auctionState
        );
    }

  function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) 
    virtual override public returns(bytes4) {
      return this.onERC721Received.selector;
  }

  struct MarketItem {
    uint itemId;
    address nftContract;
    uint256 tokenId;
    address payable seller;
    address payable owner;
    uint256 price;
    address auctionAddress;
    uint collectionId;
  }

  mapping(uint256 => MarketItem) private idToMarketItem;
  mapping(uint => uint[]) public collectionIdToItemId; // collectionId => list of itemIds
 
  event MarketItemCreated (
    uint indexed itemId,
    address nftContract,
    uint256 tokenId,
    address seller,
    address owner,
    uint256 price,
    address indexed auctionAddress,
    uint indexed collectionId
  );
  

  function getMarketItemById(uint256 marketItemId) public view returns (MarketItem memory) {
    MarketItem memory item = idToMarketItem[marketItemId];
    return item;
  }

  function createAuction(address artist, uint _endTime, uint _minIncrement, uint _directBuyPrice,
  uint _startPrice,address _nftAddress,uint _itemId)  
  private returns (address) {
        require(_directBuyPrice > 0);
        require(_endTime > 3600);
        uint auctionId = _auctionIdCounter;
        _auctionIdCounter++;
        Auction auction = new Auction(msg.sender, artist, _endTime , _minIncrement, _directBuyPrice, 
        _startPrice, _nftAddress, _itemId, this);
        auctions[auctionId] = auction;
        auctionAllowance[address(auction)] = true;
        emit SaleStarted(auctionId,_nftAddress, _itemId, address(auction));
        return address(auction);
    }

  function addItemToMarketAndStartAuction(
    address nftContract,
    uint256 tokenId,
    address artist,
    uint _endTime,
    uint _minIncrement,
    uint _directBuyPrice,
    uint _startPrice,
    uint collectionId
  ) public payable nonReentrant {

    require(msg.value == listingPrice, "Price must be equal to listing price");
    _itemIds.increment();
    uint256 itemId = _itemIds.current();
  
    len  = collectionIdToItemId[collectionId].length;
    //uint[] storage itemIdArray = collectionIdToItemId[collectionId];
    //itemIdArray[itemIdArray.length] = collectionId;
    //collectionIdToItemId[collectionId] = itemIdArray;

    IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
    address auctionAddress = createAuction(artist, _endTime, _minIncrement, _directBuyPrice, _startPrice, nftContract, itemId);

    idToMarketItem[itemId] =  MarketItem(
        itemId,
        nftContract,
        tokenId,
        payable(msg.sender),
        payable(address(0)),
        _startPrice,
        auctionAddress,
        collectionId
    );

    emit MarketItemCreated( itemId, nftContract, tokenId,msg.sender,address(0), _startPrice, auctionAddress, collectionId);
  }

  function sellItemAndTransferOwnership(
    address nftContract,
    uint256 itemId,
    address to
    ) public payable nonReentrant {
    require(auctionAllowance[msg.sender]);

    uint tokenId = idToMarketItem[itemId].tokenId;
    idToMarketItem[itemId].seller.transfer(msg.value);
    IERC721(nftContract).transferFrom(address(this), to, tokenId);
    idToMarketItem[itemId].owner = payable(to);
    _itemsSold.increment();
    payable(owner).transfer(listingPrice);
  }

  function getUnsoldItems() public view returns (MarketItem[] memory) {
    uint itemCount = _itemIds.current();
    uint unsoldItemCount = _itemIds.current() - _itemsSold.current();
    uint currentIndex = 0;

    MarketItem[] memory items = new MarketItem[](unsoldItemCount);
    for (uint i = 0; i < itemCount; i++) {
      if (idToMarketItem[i + 1].owner == address(0)) {
        uint currentId = i + 1;
        MarketItem memory currentItem = idToMarketItem[currentId];
        items[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
   
    return items;
  }

  function getItemsByOwner() public view returns (MarketItem[] memory) {
    uint totalItemCount = _itemIds.current();
    uint itemCount = 0;
    uint currentIndex = 0;

    for (uint i = 0; i < totalItemCount; i++) {
      if (idToMarketItem[i + 1].owner == msg.sender) {
        itemCount += 1;
      }
    }

    MarketItem[] memory items = new MarketItem[](itemCount);
    for (uint i = 0; i < totalItemCount; i++) {
      if (idToMarketItem[i + 1].owner == msg.sender) {
        uint currentId = i + 1;
        MarketItem memory currentItem = idToMarketItem[currentId];
        items[currentIndex] = currentItem;
        currentIndex += 1;
      }
    }
   
    return items;
  }

  function getItemsByCollectionId(uint _collectionId) public view returns (MarketItem[] memory){
      uint[] memory itemIds = collectionIdToItemId[_collectionId];
      MarketItem[] memory items;
      for(uint i = 0; i < itemIds.length; i ++){
        items[i] = idToMarketItem[itemIds[i]];
      }
      return items;
  }

  event SaleStarted(
        uint indexed auctionId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address auctionAddress);
}