import pytest
from brownie.network.account import Account # type: ignore
from brownie.test import strategy # type: ignore
from brownie import accounts, Marketplace, E721, E1155, ZERO_ADDRESS, reverts # type: ignore

from hypothesis.stateful import precondition
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

        self.bids: DefaultDict[Account, List[Bid]] = defaultdict(list)
        self.asks: DefaultDict[Account, List[Ask]] = defaultdict(list)

        self.holdership: DefaultDict[Account, List[NFT]] = defaultdict(list)
        self.escrow: DefaultDict[Account, WithdrawableBalance] = defaultdict(int)

    def initialize(self):
        # initialize gets ran before each example

        # mint tradeable NFTs for askers
        for asker in self.accounts.askers:
            e = self.e7.faucet({"from": asker})
            ee = self.e1.faucet({"from": asker})
            token_id_e7 = self.pluck_token_id(e.events)
            token_id_e1 = self.pluck_token_id(ee.events)
            self.holdership[Account(asker)].append(
                NFT(Account(self.e7.address), token_id_e7)
            )
            self.holdership[Account(asker)].append(
                NFT(Account(self.e1.address), token_id_e1)
            )

    def invariant(self):
        # invariants gets ran after each rule

        contract_bids = self.contract_bids()
        contract_asks = self.contract_asks()
        state_bids = self.flatten_dict(self.bids)
        state_asks = self.flatten_dict(self.asks)

        assert len(contract_bids) == len(state_bids)
        assert len(contract_asks) == len(state_asks)

        # todo: set equality
        map(
            lambda bid: self.assert_equal_to_one(bid, state_bids),
            contract_bids,
        )
        map(
            lambda ask: self.assert_equal_to_one(ask, state_asks),
            contract_asks,
        )

        pr_purple("invariant")

    def rule_ask(self, price="st_price"):

        asker, nft = self.find_asker()

        ask = Ask(True, nft, asker, price, TO_ANYONE)
        self.marketplace.ask(
            ask.nft.address,
            ask.nft.token_id,
            ask.price,
            TO_ANYONE,
            {"from": ask.seller},
        )
        self.update_asks(ask)

        pr_yellow(f"{ask}")

    # @precondition(lambda _: True == True)
    def rule_cancel_ask(self, st_price):
        if self.get_ask() is None:
            self.rule_ask(st_price)

        ask = self.get_ask()

        self.marketplace.cancelAsk(
            ask.nft.address, ask.nft.token_id, {"from": ask.seller}
        )
        self.remove_ask(ask)

        pr_yellow(
            f"cancelled ask. token_id={ask.nft.token_id},addr={ask.nft.address.address.lower()}"
        )

    @precondition(lambda _: True == True)
    def rule_accept_ask(self):
        pr_yellow("accepted ask")

    def rule_bid(self, price="st_price"):
        bidder, nft = self.find_bidder()

        bid = Bid(True, nft, bidder, price)
        existing_bid = self.find_existing_bid(nft)
        bid_args = [
            bid.nft.address,
            bid.nft.token_id,
            {"from": bid.buyer, "value": bid.price},
        ]

        if existing_bid is None:
            self.marketplace.bid(*bid_args)
            self.update_bids(bid)
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
            bid.nft.address, bid.nft.token_id, {"from": bid.buyer}
        )
        self.remove_bid(bid)

        pr_light_purple(
            f"cancelled bid. token_id={bid.nft.token_id},addr={bid.nft.address.address.lower()}"
        )

    @precondition(lambda _: True == True)
    def rule_accept_bid(self):
        pr_light_purple("accepted bid")

    @precondition(lambda _: True == True)
    def rule_transfer_has_ask(self):
        pr_cyan("transferred")

    @precondition(lambda _: True == True)
    def rule_transfer_has_bid_to(self):
        pr_cyan("transferred")

    # ---

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
                return (holder, nfts[0])

        return Account(ZERO_ADDRESS), NFT(ZERO_ADDRESS, 0)

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

        return (bidder, NFT(Account(nft_contract.address), token_id))

    def find_existing_bid(self, nft: NFT) -> Optional[Bid]:
        """
        Finds a bid, given an NFT.
        """
        for _, bids in self.bids.items():
            for bid in bids:
                if nft == bid.nft:
                    return bid

        return None

    def not_this_account(self, not_this: Account) -> Account:
        for acc in self.accounts.bidders + self.accounts.askers:
            if acc.address.lower() != not_this.address.lower():
                return acc

    def pluck_token_id(self, e: Dict) -> int:
        if "TransferSingle" in e:
            return int(e["TransferSingle"]["id"])
        elif "Transfer":
            return int(e["Transfer"]["tokenId"])
        else:
            return -1

    def update_asks(self, ask: Ask) -> None:
        # only create a new ask if there isn't one
        # if there is one for this nft and token_id - overwrite

        ix = -1
        for _ix, _ask in enumerate(self.asks[ask.seller]):
            if (
                _ask.nft.address == ask.nft.address
                and _ask.nft.token_id == ask.nft.token_id
            ):
                ix = _ix
                break

        if ix == -1:
            self.asks[ask.seller].append(ask)
        else:
            self.asks[ask.seller][ix] = ask

    def update_bids(self, bid: Bid) -> None:
        # only create a new bid, if there isn't one
        # if there is a bid for this nft and token_id - overwrite
        self.bids[bid.buyer].append(bid)

    def remove_ask(self, ask: Ask) -> None:

        ix = -1

        for _ix, _ask in enumerate(self.asks[ask.seller]):
            if (
                _ask.nft.address == ask.nft.address
                and _ask.nft.token_id == ask.nft.token_id
            ):
                ix = _ix
                break

        self.asks[ask.seller] = [
            _ask for _ix, _ask in enumerate(self.asks[ask.seller]) if _ix != ix
        ]

    def remove_bid(self, bid: Bid) -> None:

        ix = -1

        for _ix, _bid in enumerate(self.bids[bid.buyer]):
            if (
                _bid.nft.address == bid.nft.address
                and _bid.nft.token_id == bid.nft.token_id
            ):
                ix = _ix
                break

        self.bids[bid.buyer] = [
            _bid for _ix, _bid in enumerate(self.bids[bid.buyer]) if _ix != ix
        ]

    def _contract_orders(
        self, *, ask_request: bool, bid_request: bool
    ) -> Set[Union[Ask, Bid]]:
        if ask_request == False and bid_request == False:
            raise Exception("invalid")
        if ask_request == True and bid_request == True:
            raise Exception("invalid")

        orders: Set[Union[Ask, Bid]] = set()

        contract_func = (
            self.marketplace.asks if ask_request == True else self.marketplace.bids
        )

        for nft in [self.e7, self.e1]:
            # plus one, because token index starts at 1
            total_supply = nft.totalSupply() + 1

            for token_id in range(total_supply):
                _order = contract_func(nft.address, token_id)
                order: Union[Ask, Bid]
                if _order[0] == True:
                    nft = NFT(nft.address, token_id)

                    if ask_request == True:
                        # todo: _order[3] should be an Account
                        order = Ask(
                            True, nft, Account(_order[1]), int(_order[2]), _order[3]
                        )
                    elif bid_request == True:
                        order = Bid(True, nft, Account(_order[1]), int(_order[2]))
                    else:
                        raise Exception("unknown")

                    orders.add(order)

        return orders

    def contract_asks(self) -> Set[Union[Ask, Bid]]:
        return self._contract_orders(ask_request=True, bid_request=False)

    def contract_bids(self) -> Set[Union[Ask, Bid]]:
        return self._contract_orders(ask_request=False, bid_request=True)

    def assert_equal_to_one(self, item: T, others: List[T]) -> None:
        for _item in others:
            if item == _item:
                return
        assert False

    def flatten_dict(self, d: Dict[K, List[V]]) -> List[V]:
        vs: List[V] = []
        for k in d.keys():
            vs = vs + d[k]
        return vs

    def _get_first_order(self, *, ask_request: bool, bid_request: bool) -> Optional[Union[Ask, Bid]]:
      if ask_request == True and bid_request == True:
        raise Exception("invalid")
      if ask_request == False and bid_request == False:
        raise Exception("invalid")

      order: Optional[Union[Ask, Bid]] = None
      accs_orders = self.asks if ask_request == True else self.bids

      for _, orders in accs_orders.items(): # type: ignore
        if len(orders) > 0:
          order = orders[0]
          return order

      return order

    def get_bid(self) -> Optional[Bid]:
        return self._get_first_order(ask_request=False, bid_request=True) # type: ignore

    def get_ask(self) -> Optional[Ask]:
        return self._get_first_order(ask_request=True, bid_request=False) # type: ignore


def test_stateful(state_machine, A):
    marketplace = Marketplace.deploy({"from": A.admin})

    e7 = E721.deploy({"from": A.admin})
    e1 = E1155.deploy({"from": A.admin})

    state_machine(StateMachine, A, marketplace, e7, e1)
