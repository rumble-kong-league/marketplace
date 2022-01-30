//SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "../interfaces/INFTContract.sol";

// helps with sending the NFTs, will be particularly useful for batch operations
library NFTCommon {
    /**
     @notice Transfers the NFT tokenID from to.
     @dev safuTransferFrom name to avoid collision with the interface signature definitions. The reason it is implemented the way it is,
      is because some NFT contracts implement both the 721 and 1155 standard at the same time. Sometimes, 721 or 1155 function does not work.
      So instead of relying on the user's input, or asking the contract what interface it implements, it is best to just make a good assumption
      about what NFT type it is (here we guess it is 721 first), and if that fails, we use the 1155 function to tranfer the NFT.
     @param nft     NFT address
     @param from    Source address
     @param to      Target address
     @param tokenID ID of the token type
     @param data    Additional data with no specified format, MUST be sent unaltered in call to `onERC1155Received` on `_to`
    */
    function safeTransferFrom_(
        INFTContract nft,
        address from,
        address to,
        uint256 tokenID,
        bytes memory data
    ) internal returns (bool) {
        // most are 721s, so we assume that that is what the NFT type is
        try nft.safeTransferFrom(from, to, tokenID, data) {
            return true;
            // on fail, use 1155s format
        } catch (bytes memory) {
            try nft.safeTransferFrom(from, to, tokenID, 1, data) {
                return true;
            } catch (bytes memory) {
                return false;
            }
        }
    }

    /**
     @notice Determines if potentialOwner is in fact an owner of at least 1 qty of NFT token ID.
     @param nft NFT address
     @param potentialOwner suspected owner of the NFT token ID
     @param tokenID id of the token
     @return quantity of held token, possibly zero
    */
    function quantityOf(
        INFTContract nft,
        address potentialOwner,
        uint256 tokenID
    ) internal view returns (uint256) {
        try nft.ownerOf(tokenID) returns (address owner) {
            if (owner == potentialOwner) {
                return 1;
            } else {
                return 0;
            }
        } catch (bytes memory) {
            try nft.balanceOf(potentialOwner, tokenID) returns (
                uint256 amount
            ) {
                return amount;
            } catch (bytes memory) {
                return 0;
            }
        }
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
 * Copyright (c) 2022 Marketplace
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
