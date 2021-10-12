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
