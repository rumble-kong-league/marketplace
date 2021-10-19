from dataclasses import dataclass
import json
import pytest
from brownie.network.account import Account
from brownie.test import strategy
from brownie import accounts, Marketplace, E721, E1155
from hypothesis.stateful import precondition
from typing import DefaultDict, List, Dict, Tuple
from collections import defaultdict


def pr_red(skk):
    print("\033[91m {}\033[00m".format(skk))


def pr_green(skk):
    print("\033[92m {}\033[00m".format(skk))


def pr_yellow(skk):
    print("\033[93m {}\033[00m".format(skk))


def pr_light_purple(skk):
    print("\033[94m {}\033[00m".format(skk))


def pr_purple(skk):
    print("\033[95m {}\033[00m".format(skk))


def pr_cyan(skk):
    print("\033[96m {}\033[00m".format(skk))


def pr_light_gray(skk):
    print("\033[97m {}\033[00m".format(skk))


def pr_black(skk):
    print("\033[98m {}\033[00m".format(skk))


class Accounts:
    def __init__(self, accounts):
        self.admin = accounts[0]

        self.bidders = [accounts[1], accounts[2]]
        self.askers = [accounts[3], accounts[4]]


@pytest.fixture(autouse=True)
def shared_setup(fn_isolation):
    pass


@pytest.fixture(scope="module")
def A():
    a = Accounts(accounts)
    return a


@dataclass(frozen=True)
class Ask:
    exists: bool
    seller: Account
    price: int
    to: str

    def __repr__(self) -> str:
        s = json.dumps(
            {
                "exists": self.exists,
                "seller": self.seller.address.lower(),
                "price": self.price,
                "to": self.to,
            },
            indent=2,
        )
        return f"Ask(\n{s}\n)"

    @classmethod
    def from_raw(cls, exists: bool, seller: str, price: int, to: str):
        return cls(exists, Account(seller), price, to)


@dataclass(frozen=True)
class Bid:
    exists: bool
    buyer: Account
    price: int

    def __repr__(self) -> str:
        s = json.dumps(
            {
                "exists": self.exists,
                "buyer": self.buyer.address.lower(),
                "price": self.price,
            },
            indent=2,
        )
        return f"Bid(\n{s}\n)"

    @classmethod
    def from_contract(cls, exists: bool, buyer: str, price: int):
        return cls(exists, Account(buyer), price)


TokenID = int


class StateMachine:
    def __init__(cls, A, marketplace, e7, e1):
        cls.accounts = A
        cls.marketplace = marketplace

        cls.e7 = e7
        cls.e1 = e1

    def setup(self):
        # state sits here. This gets ran once

        self.bids = dict()
        self.asks = dict()

        self.holdership: DefaultDict[
            Account, List[Tuple[Account, TokenID]]
        ] = defaultdict(list)
        self.escrow = dict()

    def initialize(self):
        # initialize gets ran before each example

        token_e7_id = 1
        token_e1_id = 1

        # mint tradeable NFTs for askers
        for asker in self.accounts.askers:
            self.e7.faucet({"from": asker})
            self.e1.faucet({"from": asker})
            self.holdership[Account(asker)].append(
                (Account(self.e7.address), token_e7_id)
            )
            self.holdership[Account(asker)].append(
                (Account(self.e1.address), token_e7_id)
            )
            token_e7_id += 1
            token_e1_id += 1

    def invariant(self):
        # invariants gets ran afteer each example
        pr_purple("invariant")

    def rule_ask(self):
        pr_yellow("asking")

    def rule_cancel_ask(self):
        pr_yellow("cancelled ask")

    @precondition(lambda self: len(self.asks) != 0)
    def rule_accept_ask(self):
        pr_yellow("accepted ask")

    def rule_bid(self):
        pr_light_purple("bidding")

    def rule_cancel_bid(self):
        pr_light_purple("cancelled bid")

    @precondition(lambda self: len(self.bids) != 0)
    def rule_accept_bid(self):
        pr_light_purple("accepted bid")

    # todo: precondition that it has ask
    def rule_transfer_has_ask(self):
        pr_cyan("transferred")

    # todo: precondition that it has a bid
    def rule_transfer_has_bid_to(self):
        pr_cyan("transferred")


def test_stateful(state_machine, A):
    marketplace = Marketplace.deploy({"from": A.admin})

    e7 = E721.deploy({"from": A.admin})
    e1 = E1155.deploy({"from": A.admin})

    state_machine(StateMachine, A, marketplace, e7, e1)
