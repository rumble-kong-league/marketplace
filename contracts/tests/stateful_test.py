from dataclasses import dataclass
import json
import pytest
from brownie.network.account import Account
from brownie.test import strategy
from brownie import accounts, Marketplace, E721, E1155


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


class StateMachine:
    def __init__(cls, A, marketplace, e7, e1):
        cls.accounts = A
        cls.marketplace = marketplace

        cls.e7 = e7
        cls.e1 = e1

    def setup(self):
        # state sits here. This gets ran once
        ...

    def initialize(self):
        # initialize gets ran before each example
        ...

    def invariant(self):
        # invariants gets ran afteer each example
        ...

    def rule_ask(self):
        ...

    def rule_cancel_ask(self):
        ...

    def rule_accept_ask(self):
        ...

    def rule_bid(self):
        ...

    def rule_cancel_bid(self):
        ...

    def rule_accept_bid(self):
        ...

    def rule_transfer(self):
        ...


def test_stateful(state_machine, A):
    marketplace = Marketplace.deploy({"from": A.admin})

    e7 = E721.deploy({"from": A.admin})
    e1 = E1155.deploy({"from": A.admin})

    state_machine(StateMachine, A, marketplace, e7, e1)
