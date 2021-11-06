//SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/IMarketplace.sol";
import "../interfaces/INFTContract.sol";
import "./NFTCommon.sol";

// todo: think about how on transfer we can delete the ask of prev owner
// might not be necessary if we bake in checks, and if checks fail: delete
// todo: check out 0.8.9 custom types
contract Marketplace is IMarketplace {
    using Address for address payable;
    using NFTCommon for INFTContract;

    mapping(address => mapping(uint256 => Ask)) public asks;
    mapping(address => mapping(uint256 => Bid)) public bids;
    mapping(address => uint256) public escrow;

    // =====================================================================

    address payable beneficiary;
    address admin;

    // =====================================================================

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

    // =====================================================================

    constructor(address payable newBeneficiary) {
        require(newBeneficiary != payable(address(0)), "");
        beneficiary = newBeneficiary;
        admin = msg.sender;
    }

    // ======= CREATE ASK / BID ============================================

    /**
     * @notice Creates an ask for (`nft`, `tokenID`) tuple for `price`, which can
     * be reserved for `to`, if `to` is not a zero address.
     *
     * @dev Creating an ask requires msg.sender to have at least one qty of
     * (`nft`, `tokenID`).
     *
     * @param nft     An array of ERC-721 and / or ERC-1155 addresses.
     * @param tokenID Token Ids of the NFTs msg.sender wishes to sell.
     * @param price   Prices at which the seller is willing to sell the NFTs.
     * @param to      Addresses for which the sale is reserved. If zero address,
     *                then anyone can accept.
     */
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
            // if feecollector extension applied, this ensures math is correct
            require(price[i] > 10_000, "");

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

    /**
     * @notice Creates a bid on (`nft`, `tokenID`) tuple for `price`.
     *
     * @param nft     An array of ERC-721 and / or ERC-1155 addresses.
     * @param tokenID Token Ids of the NFTs msg.sender wishes to buy.
     * @param price   Prices at which the buyer is willing to buy the NFTs.
     */
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

    // ======= CANCEL ASK / BID ============================================

    /**
     * @notice Cancels ask(s) that the seller previously created.
     *
     * @param nft     An array of ERC-721 and / or ERC-1155 addresses.
     * @param tokenID Token Ids of the NFTs msg.sender wishes to cancel the
     *                asks on.
     */
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

    /**
     * @notice Cancels bid(s) that the msg.sender previously created.
     *
     * @param nft     An array of ERC-721 and / or ERC-1155 addresses.
     * @param tokenID Token Ids of the NFTs msg.sender wishes to cancel the
     *                bids on.
     */
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

    // ======= ACCEPT ASK / BID ===========================================

    /**
     * @notice Seller placed ask(s), you (buyer) are fine with the terms. You accept
     * their ask by sending the required msg.value and indicating the id of the
     * token(s) you are purchasing.
     *
     * @param nft     An array of ERC-721 and / or ERC-1155 addresses.
     * @param tokenID Token Ids of the NFTs msg.sender wishes to accept the
     *                asks on.
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

            escrow[asks[nftAddress][tokenID[i]].seller] += _takeFee(
                asks[nftAddress][tokenID[i]].price
            );

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
     * @notice You are the owner of the NFTs, someone submitted the bids on them.
     * You accept one or more of these bids.
     *
     * @param nft     An array of ERC-721 and / or ERC-1155 addresses.
     * @param tokenID Token Ids of the NFTs msg.sender wishes to accept the
     *                bids on.
     */
    function acceptBid(INFTContract[] calldata nft, uint256[] calldata tokenID)
        external
        override
    {
        uint256 escrowDelta = 0;
        for (uint256 i = 0; i < nft.length; i++) {
            require(
                nft[i].quantityOf(msg.sender, tokenID[i]) > 0,
                REVERT_NOT_OWNER_OF_TOKEN_ID
            );

            address nftAddress = address(nft[i]);

            escrowDelta += bids[nftAddress][tokenID[i]].price;
            // escrow[msg.sender] += bids[nftAddress][tokenID[i]].price;

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

        uint256 remaining = _takeFee(escrowDelta);
        escrow[msg.sender] = remaining;
    }

    /**
     * @notice Sellers can receive their payment by calling this function.
     */
    function withdraw() external override {
        uint256 amount = escrow[msg.sender];
        escrow[msg.sender] = 0;
        payable(address(msg.sender)).sendValue(amount);
    }

    // ============ ADMIN ==================================================

    /**
     * @dev Used to change the address of the trade fee receiver.
     */
    function changeBeneficiary(address payable newBeneficiary) external {
        require(msg.sender == admin, "");
        require(newBeneficiary != payable(address(0)), "");
        beneficiary = newBeneficiary;
    }

    /**
     * @dev sets the admin to the zero address. This implies that beneficiary
     * address and other admin only functions are disabled.
     */
    function revokeAdmin() external {
        require(msg.sender == admin, "");
        admin = address(0);
    }

    // ============ EXTENSIONS =============================================

    /**
     * @dev Hook that is called to collect the fees in FeeCollector extension.
     * Plain implementation of marketplace (without the FeeCollector extension)
     * has no fees.
     *
     * @param totalPrice Total price payable for the trade(s).
     */
    function _takeFee(uint256 totalPrice) internal virtual returns (uint256) {
        return totalPrice;
    }
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
