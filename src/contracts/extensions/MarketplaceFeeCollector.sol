//SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "../Marketplace.sol";

// * discounts require proxy forwarding, but a problem with that is that
// * the contract checks the balances of the caller (i.e. proxy) instead
// * of the initializer. First version, plain same fee for everyone.

abstract contract MarketplaceFeeCollector is Marketplace {
    using Address for address payable;
    // 0.5% in basis points
    uint256 public fee = 500;
    uint256 public constant HUNDRED_PERCENT = 10_000;

    /**
     * @dev Hook that is called before any token transfer.
     */
    function _beforeTokenTransferTakeFee(uint256 totalPrice)
        internal
        returns (uint256)
    {
        uint256 cut = (totalPrice * fee) / HUNDRED_PERCENT;
        require(cut < totalPrice, "");
        beneficiary.sendValue(cut);
        uint256 left = totalPrice - cut;
        return left;
    }

    function changeFee(uint256 newFee) external {
        require(msg.sender == admin, "");
        require(newFee < HUNDRED_PERCENT, "");
        fee = newFee;
    }
}
