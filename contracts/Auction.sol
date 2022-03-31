// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;
import "./NFTMarket.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract Auction is ReentrancyGuard{
    uint256 public endTime;
    uint256 public startTime;
    uint public maxBid;
    address public maxBidder;
    address payable public artist;
    address payable public admin;
    uint public shareOfArtist;
    Bid[] public bids;
    uint public itemId;
    bool public isCancelled;
    bool public isDirectBuy;
    uint public minIncrement;
    uint public directBuyPrice;
    uint public startPrice;
    address public nftAddress;
    mapping(address => uint) public refunds;
    NFTMarket public market;

    event NewBid(address bidder, uint bid);
    event WithdrawNFT(address withdrawer);
    event WithdrawFunds(address withdrawer, uint256 amount);
    event AuctionCanceled();

    enum AuctionState {
        OPEN,
        CANCELLED,
        ENDED,
        DIRECT_BUY
    }

    struct Bid {
        address sender;
        uint256 bid;
    }

    constructor(address _admin, address _artist,uint _endTime,uint _minIncrement,
    uint _directBuyPrice, uint _startPrice,address _nftAddress,uint _itemId, NFTMarket _market){
        admin = payable(_admin);
        artist = payable(_artist);
        endTime = block.timestamp +  _endTime;
        startTime = block.timestamp;
        minIncrement = _minIncrement;
        directBuyPrice = _directBuyPrice;
        startPrice = _startPrice;
        nftAddress = _nftAddress;
        itemId = _itemId;
        maxBidder = _artist;
        market = _market;
        shareOfArtist = 10; //in percentage
    }

    function allBids()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory addrs = new address[](bids.length);
        uint256[] memory bidPrice = new uint256[](bids.length);
        for (uint256 i = 0; i < bids.length; i++) {
            addrs[i] = bids[i].sender;
            bidPrice[i] = bids[i].bid;
        }
        return (addrs, bidPrice);
    }

    function placeBid() payable external nonReentrant returns(bool){
        require(msg.sender != artist && msg.sender != admin);
        require(getAuctionState() == AuctionState.OPEN);
        require(msg.value > startPrice);
        require(msg.value > maxBid + minIncrement);

        address lastHightestBidder = maxBidder;
        uint256 lastHighestBid = maxBid;
        maxBid = msg.value;
        maxBidder = msg.sender;
        if(msg.value >= directBuyPrice){
            isDirectBuy = true;
        }
        bids.push(Bid(msg.sender,msg.value));

        if(lastHighestBid != 0){
            //payable(lastHightestBidder).transfer(lastHighestBid);
            refunds[lastHightestBidder] += lastHighestBid;
        }
        emit NewBid(msg.sender,msg.value);
        return true;
    }


    function withdrawNFT() external nonReentrant returns(bool){
        require(getAuctionState() == AuctionState.ENDED || getAuctionState() == AuctionState.DIRECT_BUY);
        require(msg.sender == maxBidder);
        market.sellItemAndTransferOwnership(nftAddress, itemId, maxBidder);
        emit WithdrawNFT(maxBidder);
        return true;
    }


    function withdrawFunds() external nonReentrant returns(bool){
        require(getAuctionState() == AuctionState.ENDED || getAuctionState() == AuctionState.DIRECT_BUY);
        require(msg.sender == admin || msg.sender == artist);
        uint chargeOfCreator = maxBid * shareOfArtist / 100;
        artist.transfer(chargeOfCreator);
        admin.transfer(maxBid - chargeOfCreator);
        emit WithdrawFunds(msg.sender,maxBid);
        return true;
    }

    function cancelAuction() external nonReentrant returns(bool){
        require(msg.sender == admin);
        require(getAuctionState() == AuctionState.OPEN);
        require(maxBid == 0);
        isCancelled = true;
        market.sellItemAndTransferOwnership(nftAddress, itemId, artist);
        emit AuctionCanceled();
        return true;
    }


    function getAuctionState() public view returns(AuctionState) {
        if(isCancelled) return AuctionState.CANCELLED;
        if(isDirectBuy) return AuctionState.DIRECT_BUY;
        if(block.timestamp >= endTime) return AuctionState.ENDED;
        return AuctionState.OPEN;
    }
}
