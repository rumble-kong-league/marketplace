//SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

interface NFTContract {
    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);
}
