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
    token_id, price = 1, "1 ether"

    assert setup.e721.ownerOf(token_id) == A.asker
    assert setup.marketplace.escrow(A.asker) == 0

    setup.marketplace.bid(setup.e721, token_id, {"from": A.bidder, "value": price})
    setup.e721.setApprovalForAll(setup.marketplace, True, {"from": A.asker})
    setup.marketplace.acceptBid(setup.e721, token_id, {"from": A.asker})

    assert setup.e721.ownerOf(token_id) == A.bidder
    assert setup.marketplace.escrow(A.asker) == price


def test_accept_bid_1155(setup, A):
    setup.e1155.faucet({"from": A.asker})
    token_id, price = 1, "1 ether"

    assert setup.e1155.balanceOf(A.asker, token_id) == 10
    assert setup.marketplace.escrow(A.asker) == 0

    setup.marketplace.bid(setup.e1155, token_id, {"from": A.bidder, "value": price})
    setup.e1155.setApprovalForAll(setup.marketplace, True, {"from": A.asker})
    setup.marketplace.acceptBid(setup.e1155, token_id, {"from": A.asker})

    assert setup.e1155.balanceOf(A.asker, token_id) == 9
    assert setup.e1155.balanceOf(A.bidder, token_id) == 1
    assert setup.marketplace.escrow(A.asker) == price
