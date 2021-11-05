import pytest
from brownie.network.account import Account  # type: ignore
from brownie.test import strategy  # type: ignore
from brownie import accounts, Marketplace, E721, E1155, ZERO_ADDRESS, reverts  # type: ignore

# from hypothesis.stateful import precondition
from typing import DefaultDict, Dict, List, Tuple, Optional, TypeVar, Set, Union
from collections import defaultdict
from random import randint

from libs.utils import *
from libs.adaptors import NFT, Ask, Bid

T = TypeVar("T")
K = TypeVar("K")
V = TypeVar("V")

TO_ANYONE = ZERO_ADDRESS


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


TokenID = WithdrawableBalance = int


class StateMachine:

    # price needs to at least be 1
    st_price = strategy("uint256", min_value="1", max_value="1 ether")

    def __init__(cls, A, marketplace, e7, e1):
        cls.accounts = A
        cls.marketplace = marketplace

        cls.e7 = e7
        cls.e1 = e1

    def setup(self):
        # state sits here. This gets ran once

        self.bids: DefaultDict[Account, Set[Bid]] = defaultdict(set)
        self.asks: DefaultDict[Account, Set[Ask]] = defaultdict(set)

        self.holdership: DefaultDict[Account, Set[NFT]] = defaultdict(set)
        self.escrow: DefaultDict[Account, WithdrawableBalance] = defaultdict(int)

    def initialize(self):
        # initialize gets ran before each example

        # mint tradeable NFTs for askers
        for asker in self.accounts.askers:
            e = self.e7.faucet({"from": asker})
            ee = self.e1.faucet({"from": asker})

            token_id_e7 = self.pluck_token_id(e.events)
            token_id_e1 = self.pluck_token_id(ee.events)

            _asker = Account(asker)
            self.holdership[_asker].add(NFT(Account(self.e7.address), token_id_e7))
            self.holdership[_asker].add(NFT(Account(self.e1.address), token_id_e1))

    def invariant(self):
        # invariants run after each rule
        contract_bids = self.contract_bids()
        contract_asks = self.contract_asks()

        state_bids = self.flatten_dict(self.bids)
        state_asks = self.flatten_dict(self.asks)

        assert state_bids == contract_bids
        assert state_asks == contract_asks

        pr_purple("invariant checked")

    def rule_ask(self, price="st_price"):
        asker, nft = self.find_asker()

        ask = Ask(True, nft, asker, price, Account(TO_ANYONE))
        self.marketplace.ask(
            [ask.nft.address],
            [ask.nft.token_id],
            [ask.price],
            [ask.to],
            {"from": ask.seller},
        )
        self.add_ask(ask)

        pr_yellow(f"{ask}")

    # todo: when precondition works with brownie, remove the if condition
    # @precondition(lambda _: True == True)
    def rule_cancel_ask(self, st_price):
        if self.get_ask() is None:
            self.rule_ask(st_price)

        ask = self.get_ask()
        self.marketplace.cancelAsk(
            [ask.nft.address], [ask.nft.token_id], {"from": ask.seller}
        )
        self.remove_ask(ask)

        pr_yellow(
            f"cancelled ask. token_id={ask.nft.token_id},addr={ask.nft.address.address.lower()}"
        )

    # @precondition(lambda _: True == True)
    def rule_accept_ask(self):
        pr_yellow("accepted ask")

    def rule_bid(self, price="st_price"):
        bidder, nft = self.find_bidder()

        bid = Bid(True, nft, bidder, price)
        existing_bid = self.find_existing_bid(nft)
        bid_args = [
            [bid.nft.address],
            [bid.nft.token_id],
            [bid.price],
            {"from": bid.buyer, "value": bid.price},
        ]

        if existing_bid is None:
            self.marketplace.bid(*bid_args)
            self.add_bid(bid)
            pr_light_purple(f"{bid}")
        else:
            if existing_bid.price > bid.price:
                with reverts(self.marketplace.REVERT_BID_TOO_LOW()):
                    self.marketplace.bid(*bid_args)

    # @precondition(lambda _: True == True)
    def rule_cancel_bid(self, st_price):
        if self.get_bid() is None:
            self.rule_bid(st_price)

        bid = self.get_bid()
        self.marketplace.cancelBid(
            [bid.nft.address], [bid.nft.token_id], {"from": bid.buyer}
        )
        self.remove_bid(bid)

        pr_light_purple(
            f"cancelled bid. token_id={bid.nft.token_id},addr={bid.nft.address.address.lower()}"
        )

    # @precondition(lambda _: True == True)
    def rule_accept_bid(self):
        pr_light_purple("accepted bid")

    # @precondition(lambda _: True == True)
    def rule_transfer_has_ask(self):
        pr_cyan("transferred")

    # @precondition(lambda _: True == True)
    def rule_transfer_has_bid_to(self):
        pr_cyan("transferred")

    # ---

    # returns an asker and an NFT that they can place an ask on
    def find_asker(self) -> Tuple[Account, NFT]:
        """
        Loops through holdership, to give the first available account that can place an ask
        """
        # this will always be valid as long as we are correctly updating the holdership
        # that means:
        # - update if someone accepts ask
        # - update if someone accepts bid
        # - update on transfers
        for holder, nfts in self.holdership.items():
            if len(nfts) > 0:
                return (holder, next(iter(nfts)))

        return Account(ZERO_ADDRESS), NFT(Account(ZERO_ADDRESS), 0)

    # returns bidder and an NFT on which to bid
    def find_bidder(self) -> Tuple[Account, NFT]:
        """
        Finds the account from which we can bid, and also find an NFT on which to bid
        """
        # to find a bidder and an NFT to bid on, we mint an arbitrary new NFT from an
        # account other than the bidder
        bidder = self.accounts.bidders[randint(0, 1)]
        minter = self.not_this_account(bidder)

        nft_contract = self.e7 if randint(0, 1) == 0 else self.e1
        e = nft_contract.faucet({"from": minter})
        token_id = self.pluck_token_id(e.events)
        self.holdership[Account(minter)].add(
            NFT(Account(nft_contract.address), token_id)
        )

        return (bidder, NFT(Account(nft_contract.address), token_id))

    # given an NFT, gives you a bid on it (or None)
    def find_existing_bid(self, nft: NFT) -> Optional[Bid]:
        """
        Finds a bid, given an NFT.
        """
        bid = [bid for bids in self.bids.values() for bid in bids if nft == bid.nft]
        return None if len(bid) == 0 else bid[0]

    # returns an account that is not the arg account
    def not_this_account(self, not_this: Account) -> Account:
        for acc in self.accounts.bidders + self.accounts.askers:
            if acc.address != not_this.address:
                return acc

    def pluck_token_id(self, e: Dict) -> int:
        if "TransferSingle" in e:
            return int(e["TransferSingle"]["id"])
        elif "Transfer":
            return int(e["Transfer"]["tokenId"])
        else:
            return -1

    def _update_order(self, order: Union[Ask, Bid]) -> None:
        existing_order = None
        is_ask_request = isinstance(order, Ask)
        agents_orders = set()

        if is_ask_request:
            agents_orders = self.asks[order.seller]
        else:
            agents_orders = self.bids[order.buyer]

        for _order in agents_orders:
            if (
                _order.nft.token_id == order.nft.token_id
                and _order.nft.address == order.nft.address
            ):
                existing_order = _order

        if is_ask_request:
            if existing_order is not None:
                self.asks[order.seller].remove(existing_order)
            self.asks[order.seller].add(order)
        else:
            if existing_order is not None:
                self.bids[order.buyer].remove(existing_order)
            self.bids[order.buyer].add(order)

    # adds ask to the test's state
    def add_ask(self, ask: Ask) -> None:
        self._update_order(ask)

    # adds bid to the test's state
    def add_bid(self, bid: Bid) -> None:
        self._update_order(bid)

    def _remove_order(self, order: Union[Ask, Bid]) -> None:
        # breakpoint()

        agents_orders = set()
        is_ask_request = isinstance(order, Ask)

        agents_orders = (
            self.asks[order.seller] if is_ask_request else self.bids[order.buyer]
        )

        updated_orders = set(_order for _order in agents_orders if _order != order)

        if is_ask_request:
            self.asks[order.seller] = updated_orders
        else:
            self.bids[order.buyer] = updated_orders

    # removes ask from the test's state
    def remove_ask(self, ask: Ask) -> None:
        self._remove_order(ask)

    # removes bid from the test's state
    def remove_bid(self, bid: Bid) -> None:
        self._remove_order(bid)

    def _contract_orders(self, *, is_ask_request: bool) -> Set[Union[Ask, Bid]]:
        orders: Set[Union[Ask, Bid]] = set()

        contract_func = (
            self.marketplace.asks if is_ask_request == True else self.marketplace.bids
        )

        for nft in [self.e7, self.e1]:
            # plus one, because token index starts at 1
            total_supply = nft.totalSupply() + 1

            for token_id in range(total_supply):
                _order = contract_func(nft.address, token_id)
                order: Union[Ask, Bid]
                if _order[0]:
                    nft = NFT(Account(nft.address), token_id)
                    if is_ask_request:
                        order = Ask(
                            True,
                            nft,
                            Account(_order[1]),
                            int(_order[2]),
                            Account(_order[3]),
                        )
                    else:
                        order = Bid(True, nft, Account(_order[1]), int(_order[2]))

                    orders.add(order)

        return orders

    def contract_asks(self) -> Set[Union[Ask, Bid]]:
        return self._contract_orders(is_ask_request=True)

    def contract_bids(self) -> Set[Union[Ask, Bid]]:
        return self._contract_orders(is_ask_request=False)

    def flatten_dict(self, d: Dict[K, Set[V]]) -> Set[V]:
        """
        Double set comprehension allows us to flatten a dict whose values are lists of
        values.

        Same as:
        x = set()
        for v in d.values():
            for x in v:
                set.add(x)
        """
        return {x for v in d.values() for x in v}

    def _get_first_order(self, *, is_ask_request: bool) -> Optional[Union[Ask, Bid]]:
        accs_orders = self.asks if is_ask_request == True else self.bids

        for orders in accs_orders.values():  # type: ignore
            if len(orders) > 0:
                return next(iter(orders))

        return None

    # returns first bid that it finds (or None)
    def get_bid(self) -> Optional[Bid]:
        return self._get_first_order(is_ask_request=False)  # type: ignore

    # returns first ask that it finds (or None)
    def get_ask(self) -> Optional[Ask]:
        return self._get_first_order(is_ask_request=True)  # type: ignore


def test_stateful(state_machine, A):
    marketplace = Marketplace.deploy({"from": A.admin})

    e7 = E721.deploy({"from": A.admin})
    e1 = E1155.deploy({"from": A.admin})

    state_machine(StateMachine, A, marketplace, e7, e1)
