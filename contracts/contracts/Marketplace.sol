//SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IMarketplace.sol";
import "../interfaces/INFTContract.sol";
import "./NFTCommon.sol";

// todo: batch operations
// todo: transfers will not work like in here
// todo: think about how on transfer we can delete the ask of prev owner
// might not be necessary if we bake in checks, and if checks fail: delete
// todo: check out 0.8.9 custom types
contract Marketplace is IMarketplace {
    using Address for address payable;
    using NFTCommon for INFTContract;

    mapping(address => mapping(uint256 => Ask)) public asks;
    mapping(address => mapping(uint256 => Bid)) public bids;
    mapping(address => uint256) public escrow;

    // to avoid extra gas that comes with storing signatures on-chain, they have to be stored in a db
    // this means that we require redundancy and replication across our cloud servers. Different zones
    // would be ideal
    // 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9
    bytes32 public immutable ASK_TYPEHASH =
        keccak256(
            "Ask(address nft,uint256 tokenID,uint256 price,address to,uint256 nonce,uint256 deadline)"
        );

    // ================

    string private constant REVERT_NOT_OWNER_OF_TOKEN_ID =
        "Marketplace::not an owner of token ID";
    string private constant REVERT_OWNER_OF_TOKEN_ID =
        "Marketplace::owner of token ID";
    string private constant REVERT_BID_TOO_LOW = "Marketplace::bid too low";
    string private constant REVERT_NOT_A_CREATOR_OF_BID =
        "Marketplace::not a creator of the bid";
    string private constant REVERT_ASK_DOES_NOT_EXIST =
        "Marketplace::ask does not exist";
    string private constant REVERT_CANT_ACCEPT_OWN_ASK =
        "Marketplace::cant accept own ask";
    string private constant REVERT_ASK_IS_RESERVED =
        "Marketplace::ask is reserved";
    string private constant REVERT_ASK_INSUFFICIENT_VALUE =
        "Marketplace::ask price higher than sent value";
    string private constant REVERT_ASK_SELLER_NOT_OWNER =
        "Marketplace::ask creator not owner";
    string private constant REVERT_NFT_NOT_SENT = "Marketplace::NFT not sent";

    // ======= CREATE ASK OR BID =====================================

    // creating ask requires you to have at least one amount of the NFT
    // 1. checking that the owner of the 721 NFT tokenID is not a msg.sender is redundant,
    // since there is a check that the owner is the msg.sender.
    // 2. what is the worst that can happen if the owner of the 1155 NFT is zero address?
    // that it calls this function. Which is not possible. If it did call this function,
    // it would be able to create asks that other agents could interact with. Which in itself,
    // isn't a bad scenario.

    function ask(
        INFTContract nft,
        uint256 tokenID,
        uint256 price,
        address to
    ) external override {
        require(
            nft.quantityOf(msg.sender, tokenID) > 0,
            REVERT_NOT_OWNER_OF_TOKEN_ID
        );

        // overwristes or creates a new one
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

    // what happens if you do bid on an NFT that is in zero address
    // what is the worst that can happen?
    //   two modes of interacting with an existing bid: cancel bid or accept bid
    // - you can cancel the bid any time, so you will get your money back
    // - outside of your control: someone accepts the bid (if 1155, and 1 unit in zero address, but someone else
    //     also has some qty of the NFT in their wallet). This will be a normal flow of accepting a bid.
    //     Therefore, when someone bids on a single unit of 1155, they are bidding on all the 1155s
    //     If someone is bidding on a certain qty of 1155, they are bidding on all the holders of the 1155
    //        that hold that qty of 1155 or more.
    // Therefore, it is not a problem if zero address has some quantity of 1155

    function bid(INFTContract nft, uint256 tokenID) external payable override {
        address nftAddress = address(nft);
        // ! this will disallow bidding on 1155s that you already hold. Is this desired?
        // ! can this be ignored and agents be allowed to bid on what they have?
        require(
            nft.quantityOf(msg.sender, tokenID) == 0,
            REVERT_OWNER_OF_TOKEN_ID
        );
        // require bid larger than existing bid or 0 (if exists or doesn't)
        require(
            msg.value > bids[nftAddress][tokenID].price,
            REVERT_BID_TOO_LOW
        );

        // if bid existed, let the prev. creator withdraw their bid. new overwrites
        if (bids[nftAddress][tokenID].exists) {
            escrow[bids[nftAddress][tokenID].buyer] += bids[nftAddress][tokenID]
                .price;
        }

        // overwristes or creates a new one
        bids[nftAddress][tokenID] = Bid({
            exists: true,
            buyer: msg.sender,
            price: msg.value
        });

        emit BidCreated({nft: nftAddress, tokenID: tokenID, price: msg.value});
    }

    // ======= CANCEL ASK OR BID =====================================

    function cancelAsk(INFTContract nft, uint256 tokenID) external override {
        require(
            nft.quantityOf(msg.sender, tokenID) > 0,
            REVERT_NOT_OWNER_OF_TOKEN_ID
        );

        delete asks[address(nft)][tokenID];

        emit AskDeleted({nft: address(nft), tokenID: tokenID});
    }

    function cancelBid(INFTContract nft, uint256 tokenID) external override {
        address nftAddress = address(nft);
        require(
            bids[nftAddress][tokenID].buyer == msg.sender,
            REVERT_NOT_A_CREATOR_OF_BID
        );

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
    function acceptAsk(INFTContract nft, uint256 tokenID)
        external
        payable
        override
    {
        address nftAddress = address(nft);

        require(asks[nftAddress][tokenID].exists, REVERT_ASK_DOES_NOT_EXIST);
        require(
            asks[nftAddress][tokenID].seller != msg.sender,
            REVERT_CANT_ACCEPT_OWN_ASK
        );
        if (asks[nftAddress][tokenID].to != address(0)) {
            require(
                asks[nftAddress][tokenID].to == msg.sender,
                REVERT_ASK_IS_RESERVED
            );
        }
        require(
            msg.value == asks[nftAddress][tokenID].price,
            REVERT_ASK_INSUFFICIENT_VALUE
        );
        require(
            nft.quantityOf(asks[nftAddress][tokenID].seller, tokenID) > 0,
            REVERT_ASK_SELLER_NOT_OWNER
        );

        // send NFT, receive money
        // * to send the NFT from seller, we need his signature
        // todo: _transfer(asks[tokenID].seller, msg.sender, tokenID);
        escrow[asks[nftAddress][tokenID].seller] += msg.value;

        // if there is a bid for this tokenID from msg.sender, cancel and refund
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

    function acceptBid(INFTContract nft, uint256 tokenID) external override {
        address nftAddress = address(nft);
        require(
            nft.quantityOf(msg.sender, tokenID) > 0,
            REVERT_NOT_OWNER_OF_TOKEN_ID
        );

        bool success = nft.safeTransferFrom_(
            msg.sender,
            bids[nftAddress][tokenID].buyer,
            tokenID,
            new bytes(0)
        );
        require(success, REVERT_NFT_NOT_SENT);
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
        payable(address(msg.sender)).sendValue(amount);
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
