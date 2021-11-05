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

    // ================

    string public constant REVERT_NOT_OWNER_OF_TOKEN_ID =
        "Marketplace::not an owner of token ID";
    string public constant REVERT_OWNER_OF_TOKEN_ID =
        "Marketplace::owner of token ID";
    string public constant REVERT_BID_TOO_LOW = "Marketplace::bid too low";
    string public constant REVERT_NOT_A_CREATOR_OF_BID =
        "Marketplace::not a creator of the bid";
    string public constant REVERT_NOT_A_CREATOR_OF_ASK =
        "Marketplace::not a creator of the ask";
    string public constant REVERT_ASK_DOES_NOT_EXIST =
        "Marketplace::ask does not exist";
    string public constant REVERT_CANT_ACCEPT_OWN_ASK =
        "Marketplace::cant accept own ask";
    string public constant REVERT_ASK_IS_RESERVED =
        "Marketplace::ask is reserved";
    string public constant REVERT_ASK_INSUFFICIENT_VALUE =
        "Marketplace::ask price higher than sent value";
    string public constant REVERT_ASK_SELLER_NOT_OWNER =
        "Marketplace::ask creator not owner";
    string public constant REVERT_NFT_NOT_SENT = "Marketplace::NFT not sent";
    string public constant REVERT_INSUFFICIENT_ETHER =
        "Marketplace::insufficient ether sent";

    // ======= CREATE ASK OR BID =====================================

    // creating ask requires you to have at least one amount of the NFT
    // 1. checking that the owner of the 721 NFT tokenID is not a msg.sender is redundant,
    // since there is a check that the owner is the msg.sender.
    // 2. what is the worst that can happen if the owner of the 1155 NFT is zero address?
    // that it calls this function. Which is not possible. If it did call this function,
    // it would be able to create asks that other agents could interact with. Which in itself,
    // isn't a bad scenario.

    function ask(
        INFTContract[] calldata nft,
        uint256[] calldata tokenID,
        uint256[] calldata price,
        address[] calldata to
    ) external override {
        for (uint256 i = 0; i < nft.length; i++) {
            require(
                nft[i].quantityOf(msg.sender, tokenID[i]) > 0,
                REVERT_NOT_OWNER_OF_TOKEN_ID
            );

            // overwristes or creates a new one
            asks[address(nft[i])][tokenID[i]] = Ask({
                exists: true,
                seller: msg.sender,
                price: price[i],
                to: to[i]
            });

            emit AskCreated({
                nft: address(nft[i]),
                tokenID: tokenID[i],
                price: price[i],
                to: to[i]
            });
        }
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

    function bid(
        INFTContract[] calldata nft,
        uint256[] calldata tokenID,
        uint256[] calldata price
    ) external payable override {
        uint256 totalPrice = 0;

        for (uint256 i = 0; i < nft.length; i++) {
            address nftAddress = address(nft[i]);
            // bidding on own NFTs is possible. But then again, even if we wanted to disallow it,
            // it would not be an effective mechanism, since the agent can bid from his other
            // wallets
            require(
                msg.value > bids[nftAddress][tokenID[i]].price,
                REVERT_BID_TOO_LOW
            );

            // if bid existed, let the prev. creator withdraw their bid. new overwrites
            if (bids[nftAddress][tokenID[i]].exists) {
                escrow[bids[nftAddress][tokenID[i]].buyer] += bids[nftAddress][
                    tokenID[i]
                ].price;
            }

            // overwristes or creates a new one
            bids[nftAddress][tokenID[i]] = Bid({
                exists: true,
                buyer: msg.sender,
                price: price[i]
            });

            emit BidCreated({
                nft: nftAddress,
                tokenID: tokenID[i],
                price: price[i]
            });

            totalPrice += price[i];
        }

        require(totalPrice == msg.value, REVERT_INSUFFICIENT_ETHER);
    }

    // ======= CANCEL ASK OR BID =====================================

    function cancelAsk(INFTContract[] calldata nft, uint256[] calldata tokenID)
        external
        override
    {
        for (uint256 i = 0; i < nft.length; i++) {
            address nftAddress = address(nft[i]);
            require(
                asks[nftAddress][tokenID[i]].seller == msg.sender,
                REVERT_NOT_A_CREATOR_OF_ASK
            );

            delete asks[nftAddress][tokenID[i]];

            emit AskDeleted({nft: nftAddress, tokenID: tokenID[i]});
        }
    }

    function cancelBid(INFTContract[] calldata nft, uint256[] calldata tokenID)
        external
        override
    {
        for (uint256 i = 0; i < nft.length; i++) {
            address nftAddress = address(nft[i]);
            require(
                bids[nftAddress][tokenID[i]].buyer == msg.sender,
                REVERT_NOT_A_CREATOR_OF_BID
            );

            escrow[msg.sender] += bids[nftAddress][tokenID[i]].price;

            delete bids[nftAddress][tokenID[i]];

            emit BidDeleted({nft: nftAddress, tokenID: tokenID[i]});
        }
    }

    // ======= ACCEPT ASK OR BID =====================================

    /**
     * @dev Seller placed ask, you are fine with the terms. You accept their
     * ask by sending the required msg.value and indicating the id of the token
     * you are purchasing. There is no outflow like in the acceptBid case, since
     * there is no bid that requires escrow adjusting. See acceptBid's function
     * body comments for details. There is no batching, since the seller is
     * not required to be the same address across all the accepted asks.
     */
    function acceptAsk(INFTContract[] calldata nft, uint256[] calldata tokenID)
        external
        payable
        override
    {
        uint256 totalPrice = 0;

        for (uint256 i = 0; i < nft.length; i++) {
            address nftAddress = address(nft[i]);

            require(
                asks[nftAddress][tokenID[i]].exists,
                REVERT_ASK_DOES_NOT_EXIST
            );
            require(
                asks[nftAddress][tokenID[i]].seller != msg.sender,
                REVERT_CANT_ACCEPT_OWN_ASK
            );
            if (asks[nftAddress][tokenID[i]].to != address(0)) {
                require(
                    asks[nftAddress][tokenID[i]].to == msg.sender,
                    REVERT_ASK_IS_RESERVED
                );
            }
            require(
                nft[i].quantityOf(
                    asks[nftAddress][tokenID[i]].seller,
                    tokenID[i]
                ) > 0,
                REVERT_ASK_SELLER_NOT_OWNER
            );

            totalPrice += asks[nftAddress][tokenID[i]].price;

            escrow[asks[nftAddress][tokenID[i]].seller] += asks[nftAddress][
                tokenID[i]
            ].price;

            // if there is a bid for this tokenID from msg.sender, cancel and refund
            if (bids[nftAddress][tokenID[i]].buyer == msg.sender) {
                escrow[bids[nftAddress][tokenID[i]].buyer] += bids[nftAddress][
                    tokenID[i]
                ].price;
                delete bids[nftAddress][tokenID[i]];
            }

            emit AskAccepted({
                nft: nftAddress,
                tokenID: tokenID[i],
                price: asks[nftAddress][tokenID[i]].price,
                to: asks[nftAddress][tokenID[i]].to
            });

            bool success = nft[i].safeTransferFrom_(
                asks[nftAddress][tokenID[i]].seller,
                msg.sender,
                tokenID[i],
                new bytes(0)
            );
            require(success, REVERT_NFT_NOT_SENT);

            delete asks[nftAddress][tokenID[i]];
        }

        require(totalPrice == msg.value, REVERT_ASK_INSUFFICIENT_VALUE);
    }

    /**
     * @dev You are the owner of the NFTs, someone submitted the bids on them.
     * You accept one or more of these bids. Batching here does not work because
     * you are sending the NFTs to potentially different addresses.
     */
    function acceptBid(INFTContract[] calldata nft, uint256[] calldata tokenID)
        external
        override
    {
        for (uint256 i = 0; i < nft.length; i++) {
            require(
                nft[i].quantityOf(msg.sender, tokenID[i]) > 0,
                REVERT_NOT_OWNER_OF_TOKEN_ID
            );

            address nftAddress = address(nft[i]);

            escrow[msg.sender] += bids[nftAddress][tokenID[i]].price;

            emit BidAccepted({
                nft: nftAddress,
                tokenID: tokenID[i],
                price: bids[nftAddress][tokenID[i]].price
            });

            bool success = nft[i].safeTransferFrom_(
                msg.sender,
                bids[nftAddress][tokenID[i]].buyer,
                tokenID[i],
                new bytes(0)
            );
            require(success, REVERT_NFT_NOT_SENT);

            delete asks[nftAddress][tokenID[i]];
            delete bids[nftAddress][tokenID[i]];
        }
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
