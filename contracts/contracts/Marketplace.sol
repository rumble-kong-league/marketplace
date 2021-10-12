//SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "../interfaces/IMarketplace.sol";
import "../interfaces/NFTContract.sol";

// todo: emit events
// todo: support for any NFT
// todo: batch operations
// todo: transfers will not work like in here
// todo: think about how on transfer we can delete the ask of prev owner
// might not be necessary if we bake in checks, and if checks fail: delete
// todo: make an interface for this contract and move structs events into there
// todo: check out 0.8.9 custom types
contract Marketplace is IMarketplace {
    mapping(address => mapping(uint256 => Ask)) public asks;
    mapping(address => mapping(uint256 => Bid)) public bids;
    mapping(address => uint256) public escrow;

    // ======= CREATE ASK OR BID =====================================

    function ask(
        NFTContract nft,
        uint256 tokenID,
        uint256 price,
        address to
    ) external override {
        require(
            nft.ownerOf(tokenID) != address(0),
            "Marketplace::does not exist or burned."
        );
        // to place an ask, you must be an owner
        require(
            nft.ownerOf(tokenID) == msg.sender,
            "Marketplace::not an owner of token."
        );
        // notice that this will overwrite any existing ask on this same NFT token ID
        // or creates a new one
        asks[address(nft)][tokenID] = Ask({
            exists: true,
            seller: msg.sender,
            price: price,
            to: to
        });

        emit AskCreated({
            nft: address(nft),
            tokenID: tokenID,
            price: price,
            to: to
        });
    }

    function bid(NFTContract nft, uint256 tokenID) external payable override {
        address nftAddress = address(nft);
        // no point in bidding on burned or non-existent NFT token ID
        require(nft.ownerOf(tokenID) != address(0), "");
        // no point in bidding on your own NFT token ID
        require(nft.ownerOf(tokenID) != msg.sender, "");
        // require that bid value larger than the existing bid (if exists)
        require(msg.value > bids[nftAddress][tokenID].price, "");

        // if there is an existing bid, then its bid price is lower
        // therefore, let the creator of that bid withdraw their bid
        if (bids[nftAddress][tokenID].exists) {
            escrow[bids[nftAddress][tokenID].buyer] += bids[nftAddress][tokenID]
                .price;
        }

        // overwrite an existing bid, or create a new one
        bids[nftAddress][tokenID] = Bid({
            exists: true,
            buyer: msg.sender,
            price: msg.value
        });

        emit BidCreated({nft: nftAddress, tokenID: tokenID, price: msg.value});
    }

    // ======= CANCEL ASK OR BID =====================================

    function cancelAsk(NFTContract nft, uint256 tokenID) external override {
        // to cancel the ask, you must be an owner of the NFT token ID
        require(nft.ownerOf(tokenID) == msg.sender, "");

        delete asks[address(nft)][tokenID];

        emit AskDeleted({nft: address(nft), tokenID: tokenID});
    }

    function cancelBid(NFTContract nft, uint256 tokenID) external override {
        address nftAddress = address(nft);
        require(bids[nftAddress][tokenID].buyer == msg.sender, "");

        escrow[msg.sender] += bids[nftAddress][tokenID].price;

        delete bids[nftAddress][tokenID];

        emit BidDeleted({nft: nftAddress, tokenID: tokenID});
    }

    // ======= ACCEPT ASK OR BID =====================================

    /**
     * @dev Seller placed ask, you are fine with the terms. You accept their
     * ask by sending the required msg.value and indicating the id of the token
     * you are purchasing. There is no outflow like in the acceptBid case, since
     * there is no bid that requires escrow adjusting. See acceptBid's function
     * body comments for details.
     */
    function acceptAsk(NFTContract nft, uint256 tokenID)
        external
        payable
        override
    {
        address nftAddress = address(nft);
        // ask must exist to accept
        require(asks[nftAddress][tokenID].exists, "");
        // if you are owner of the NFT, you can't accept your own ask
        require(asks[nftAddress][tokenID].seller != msg.sender, "");
        // if the ask is not meant for everyone to accept, check that msg.sender
        // can accept it
        if (asks[nftAddress][tokenID].to != address(0)) {
            require(asks[nftAddress][tokenID].to == msg.sender, "");
        }
        // ensure that the accepter has sent sufficient money
        require(msg.value == asks[nftAddress][tokenID].price, "");
        // ensure that the owner of the NFT is still the same person that created
        // the ask
        require(asks[nftAddress][tokenID].seller == nft.ownerOf(tokenID), "");

        // send NFT, receive money
        // todo: _transfer(asks[tokenID].seller, msg.sender, tokenID);
        escrow[asks[nftAddress][tokenID].seller] += msg.value;

        // if there is a bid from accepter, cancel and refund
        if (bids[nftAddress][tokenID].buyer == msg.sender) {
            escrow[bids[nftAddress][tokenID].buyer] += bids[nftAddress][tokenID]
                .price;
            delete bids[nftAddress][tokenID];
        }

        emit AskAccepted({
            nft: nftAddress,
            tokenID: tokenID,
            price: asks[nftAddress][tokenID].price,
            to: asks[nftAddress][tokenID].to
        });

        delete asks[nftAddress][tokenID];
    }

    function acceptBid(NFTContract nft, uint256 tokenID) external override {
        address nftAddress = address(nft);
        // owner of the NFT is allowed to accept a bid on that NFT token ID
        require(nft.ownerOf(tokenID) == msg.sender, "");

        // send NFT from accepter, receive money from bidder
        // todo: _transfer(msg.sender, bids[tokenID].buyer, tokenID);
        escrow[msg.sender] += bids[nftAddress][tokenID].price;

        emit BidAccepted({
            nft: nftAddress,
            tokenID: tokenID,
            price: bids[nftAddress][tokenID].price
        });

        delete asks[nftAddress][tokenID];
        delete bids[nftAddress][tokenID];
    }

    function withdraw() external override {
        uint256 amount = escrow[msg.sender];
        escrow[msg.sender] = 0;
        // todo: bool success, require success
        payable(address(msg.sender)).transfer(amount);
    }

    // ==============================================================
}

/*
 * 88888888ba  88      a8P  88
 * 88      "8b 88    ,88'   88
 * 88      ,8P 88  ,88"     88
 * 88aaaaaa8P' 88,d88'      88
 * 88""""88'   8888"88,     88
 * 88    `8b   88P   Y8b    88
 * 88     `8b  88     "88,  88
 * 88      `8b 88       Y8b 88888888888
 *
 * Marketplace: Marketplace.sol
 *
 * MIT License
 * ===========
 *
 * Copyright (c) 2022 Rumble League Studios Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 */
