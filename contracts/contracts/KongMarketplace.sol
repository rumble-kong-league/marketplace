//SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// todo: emit events
// todo: support for any NFT
// todo: batch operations
// todo: transfers will not work like in here
// todo: think about how on transfer we can delete the ask of prev owner
// might not be necessary if we bake in checks, and if checks fail: delete
// todo: make an interface for this contract and move structs events into there
// todo: check out 0.8.9 custom types
contract KongMarketplace {
    struct Ask {
        bool exists;
        address seller;
        uint256 price;
        address to;
    }

    struct Bid {
        bool exists;
        address buyer;
        uint256 price;
    }

    mapping(uint256 => Ask) public asks;
    mapping(uint256 => Bid) public bids;
    mapping(address => uint256) public escrow;

    // todo: will delete
    IERC721 public constant KONG_CONTRACT =
        IERC721(0xEf0182dc0574cd5874494a120750FD222FdB909a);

    // ======= CREATE ASK OR BID =====================================

    function ask(
        uint256 kongID,
        uint256 price,
        address to
    ) external {
        // to place an ask, you must be an owner
        require(KONG_CONTRACT.ownerOf(kongID) == msg.sender, "");
        // notice that this will overwrite any existing ask on this same NFT token ID
        // or creates a new one
        asks[kongID] = Ask(true, msg.sender, price, to);
    }

    function bid(uint256 kongID) external payable {
        // no point in bidding on burned NFT token ID
        require(KONG_CONTRACT.ownerOf(kongID) != address(0), "");
        // no point in bidding on your own NFT token ID
        require(KONG_CONTRACT.ownerOf(kongID) != msg.sender, "");
        // require that bid value larger than the existing bid (if exists)
        require(msg.value > bids[kongID].price, "");

        // if there is an existing bid, then its bid price is lower
        // therefore, let the creator of that bid withdraw their bid
        if (bids[kongID].exists) {
            escrow[bids[kongID].buyer] += bids[kongID].price;
        }

        // overwrite an existing bid, or create a new one
        bids[kongID] = Bid(true, msg.sender, msg.value);
    }

    // ======= CANCEL ASK OR BID =====================================

    function cancelAsk(uint256 kongID) external {
        // to cancel the ask, you must be an owner of the NFT token ID
        require(KONG_CONTRACT.ownerOf(kongID) == msg.sender, "");
        delete asks[kongID];
    }

    function cancelBid(uint256 kongID) external {
        require(bids[kongID].buyer == msg.sender, "");

        escrow[msg.sender] += bids[kongID].price;

        delete bids[kongID];
    }

    // ======= ACCEPT ASK OR BID =====================================

    /**
     * @dev Seller placed ask, you are fine with the terms. You accept their
     * ask by sending the required msg.value and indicating the id of the token
     * you are purchasing. There is no outflow like in the acceptBid case, since
     * there is no bid that requires escrow adjusting. See acceptBid's function
     * body comments for details.
     */
    function acceptAsk(uint256 kongID) external payable {
        // ask must exist to accept
        require(asks[kongID].exists, "");
        // if you are owner of the NFT, you can't accept your own ask
        require(asks[kongID].seller != msg.sender, "");
        // if the ask is not meant for everyone to accept, check that msg.sender
        // can accept it
        if (asks[kongID].to != address(0)) {
            require(asks[kongID].to == msg.sender, "");
        }
        // ensure that the accepter has sent sufficient money
        require(msg.value == asks[kongID].price, "");
        // ensure that the owner of the NFT is still the same person that created
        // the ask
        require(asks[kongID].seller == KONG_CONTRACT.ownerOf(kongID), "");

        // send NFT, receive money
        // todo: _transfer(asks[kongID].seller, msg.sender, kongID);
        escrow[asks[kongID].seller] += msg.value;

        // if there is a bid from accepter, cancel and refund
        if (bids[kongID].buyer == msg.sender) {
            escrow[bids[kongID].buyer] += bids[kongID].price;
            delete bids[kongID];
        }

        delete asks[kongID];
    }

    function acceptBid(uint256 kongID) external {
        // owner of the NFT is allowed to accept a bid on that NFT token ID
        require(KONG_CONTRACT.ownerOf(kongID) == msg.sender, "");

        // send NFT from accepter, receive money from bidder
        // todo: _transfer(msg.sender, bids[kongID].buyer, kongID);
        escrow[msg.sender] += bids[kongID].price;

        delete asks[kongID];
        delete bids[kongID];
    }

    function withdraw() external {
        uint256 amount = escrow[msg.sender];
        escrow[msg.sender] = 0;
        // todo: bool success, require success
        payable(address(msg.sender)).transfer(amount);
    }

    // ==============================================================
}
