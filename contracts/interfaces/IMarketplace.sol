//SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "./NFTContract.sol";

interface IMarketplace {
    // ======================= EVENTS ================================

    event AskCreated(
        address indexed nft,
        uint256 indexed tokenID,
        uint256 price,
        address indexed to
    );
    event AskDeleted(address indexed nft, uint256 indexed tokenID);
    event AskAccepted(
        address indexed nft,
        uint256 indexed tokenID,
        uint256 price,
        address indexed to
    );

    event BidCreated(
        address indexed nft,
        uint256 indexed tokenID,
        uint256 price
    );
    event BidDeleted(address indexed nft, uint256 indexed tokenID);
    event BidAccepted(
        address indexed nft,
        uint256 indexed tokenID,
        uint256 price
    );

    // ========================= STRUCTS ==============================

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

    // ===============================================================

    function ask(
        NFTContract nft,
        uint256 tokenID,
        uint256 price,
        address to
    ) external;

    function bid(NFTContract nft, uint256 tokenID) external payable;

    // ======= CANCEL ASK OR BID =====================================

    function cancelAsk(NFTContract nft, uint256 tokenID) external;

    function cancelBid(NFTContract nft, uint256 tokenID) external;

    /**
     * @dev Seller placed ask, you are fine with the terms. You accept their
     * ask by sending the required msg.value and indicating the id of the token
     * you are purchasing. There is no outflow like in the acceptBid case, since
     * there is no bid that requires escrow adjusting. See acceptBid's function
     * body comments for details.
     */
    function acceptAsk(NFTContract nft, uint256 tokenID) external payable;

    function acceptBid(NFTContract nft, uint256 tokenID) external;

    /**
     * @dev Sellers will be able to withdraw their payment by calling this function.
     * Unsuccessful bidders will be able to withdraw their bid calling this function.
     */
    function withdraw() external;
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
 * Marketplace: interfaces/IMarketplace.sol
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
