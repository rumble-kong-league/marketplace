# pylint: disable=redefined-outer-name,invalid-name,no-name-in-module,unused-argument,too-few-public-methods,too-many-arguments
# type: ignore
from dataclasses import dataclass
from decimal import Decimal
from typing import List, Tuple
from brownie.network.account import Account
from decimal import Decimal

import json
import pytest
import brownie
from brownie import ZERO_ADDRESS, accounts, Marketplace, E721, E1155
from brownie.test import strategy

ANYONE_CAN_BUY = ZERO_ADDRESS


# reset state before each test
@pytest.fixture(autouse=True)
def shared_setup(fn_isolation):
    pass


class Accounts:
    def __init__(self, accounts):
        self.admin = accounts[0]
        self.bidder = accounts[1]
        self.asker = accounts[2]


@dataclass(frozen=True)
class NFTParams:
    token_id: int = 1
    price: str = "1 ether"
    qty_1155: int = 10


@dataclass(frozen=True)
class Setup:
    marketplace: Marketplace
    e721: E721
    e1155: E1155


@pytest.fixture(scope="module")
def A():
    A = Accounts(accounts)
    return A


@pytest.fixture(scope="module")
def setup(A, Marketplace, E721, E1155):
    marketplace = Marketplace.deploy({"from": A.admin})

    e721 = E721.deploy({"from": A.admin})
    e1155 = E1155.deploy({"from": A.admin})

    return Setup(marketplace, e721, e1155)


def test_accept_bid_721(setup, A):
    setup.e721.faucet({"from": A.asker})

    assert setup.e721.ownerOf(NFTParams.token_id) == A.asker
    assert setup.marketplace.escrow(A.asker) == 0

    setup.marketplace.bid(
        setup.e721, NFTParams.token_id, {"from": A.bidder, "value": NFTParams.price}
    )
    setup.e721.setApprovalForAll(setup.marketplace, True, {"from": A.asker})
    setup.marketplace.acceptBid(setup.e721, NFTParams.token_id, {"from": A.asker})

    assert setup.e721.ownerOf(NFTParams.token_id) == A.bidder
    assert setup.marketplace.escrow(A.asker) == NFTParams.price


def test_accept_bid_1155(setup, A):
    setup.e1155.faucet({"from": A.asker})

    assert setup.e1155.balanceOf(A.asker, NFTParams.token_id) == 10
    assert setup.marketplace.escrow(A.asker) == 0

    setup.marketplace.bid(
        setup.e1155, NFTParams.token_id, {"from": A.bidder, "value": NFTParams.price}
    )
    setup.e1155.setApprovalForAll(setup.marketplace, True, {"from": A.asker})
    setup.marketplace.acceptBid(setup.e1155, NFTParams.token_id, {"from": A.asker})

    assert setup.e1155.balanceOf(A.asker, NFTParams.token_id) == 9
    assert setup.e1155.balanceOf(A.bidder, NFTParams.token_id) == 1
    assert setup.marketplace.escrow(A.asker) == NFTParams.price


def test_accept_ask_721(setup, A):
    setup.e721.faucet({"from": A.asker})

    assert setup.e721.ownerOf(NFTParams.token_id) == A.asker
    assert setup.marketplace.escrow(A.asker) == 0

    setup.marketplace.ask(
        setup.e721,
        NFTParams.token_id,
        NFTParams.price,
        ANYONE_CAN_BUY,
        {"from": A.asker},
    )
    setup.e721.setApprovalForAll(setup.marketplace, True, {"from": A.asker})
    setup.marketplace.acceptAsk(
        setup.e721, NFTParams.token_id, {"from": A.bidder, "value": NFTParams.price}
    )

    assert setup.e721.ownerOf(NFTParams.token_id) == A.bidder
    assert setup.marketplace.escrow(A.asker) == NFTParams.price


def test_accept_ask_1155(setup, A):
    setup.e1155.faucet({"from": A.asker})

    assert setup.e1155.balanceOf(A.asker, NFTParams.token_id) == NFTParams.qty_1155
    assert setup.marketplace.escrow(A.asker) == 0

    setup.marketplace.ask(
        setup.e1155,
        NFTParams.token_id,
        NFTParams.price,
        ANYONE_CAN_BUY,
        {"from": A.asker},
    )
    setup.e1155.setApprovalForAll(setup.marketplace, True, {"from": A.asker})
    setup.marketplace.acceptAsk(
        setup.e1155, NFTParams.token_id, {"from": A.bidder, "value": NFTParams.price}
    )

    assert setup.e1155.balanceOf(A.asker, NFTParams.token_id) == 9
    assert setup.e1155.balanceOf(A.bidder, NFTParams.token_id) == 1
    assert setup.marketplace.escrow(A.asker) == NFTParams.price
