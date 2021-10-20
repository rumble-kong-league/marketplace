from dataclasses import dataclass
import json
import pytest
from brownie.network.account import Account
from brownie.test import strategy
from brownie import accounts, Marketplace, E721, E1155, ZERO_ADDRESS, reverts

# todo: look at brownie and hypothesis. See how this can be added
# from hypothesis.stateful import precondition
from typing import DefaultDict, Dict, List, Tuple, Optional, TypeVar
from collections import defaultdict
from random import randint

T = TypeVar("T")
K = TypeVar("K")
V = TypeVar("V")

TO_ANYONE = ZERO_ADDRESS


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
class NFT:
    address: Account
    token_id: int

    def __repr__(self) -> str:
        s = json.dumps(
            {"address": self.address.address.lower(), "tokenID": self.token_id}
        )
        return f"NFT({s})"


# TODO: to should be an Account as well
@dataclass(frozen=True)
class Ask:
    exists: bool
    nft: NFT
    seller: Account
    price: int
    to: str

    def __repr__(self) -> str:
        s = json.dumps(
            {
                "exists": self.exists,
                "nft": str(self.nft),
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
    nft: NFT
    buyer: Account
    price: int

    def __repr__(self) -> str:
        s = json.dumps(
            {
                "exists": self.exists,
                "nft": str(self.nft),
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
WithdrawableBalance = int


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

        # todo: pull the token ids straight out of the event like in self.find_bidder
        token_e7_id = 1
        token_e1_id = 1

        # mint tradeable NFTs for askers
        for asker in self.accounts.askers:
            self.e7.faucet({"from": asker})
            self.e1.faucet({"from": asker})
            self.holdership[Account(asker)].append(
                NFT(Account(self.e7.address), token_e7_id)
            )
            self.holdership[Account(asker)].append(
                NFT(Account(self.e1.address), token_e7_id)
            )
            token_e7_id += 1
            token_e1_id += 1

    def invariant(self):
        # invariants gets ran after each rule

        contract_bids = self.contract_bids()
        contract_asks = self.contract_asks()
        state_bids = self.flatten_dict(self.bids)
        state_asks = self.flatten_dict(self.asks)

        assert len(contract_bids) == len(state_bids)
        assert len(contract_asks) == len(state_asks)

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

    # @precondition(lambda self: True == True)
    def rule_cancel_ask(self, st_price):
        if not self.there_is_at_least_one_ask():
            self.rule_ask(st_price)

        ask = self.get_ask()

        self.marketplace.cancelAsk(
            ask.nft.address, ask.nft.token_id, {"from": ask.seller}
        )
        self.remove_ask(ask)

        pr_yellow(
            f"cancelled ask. token_id={ask.nft.token_id},addr={ask.nft.address.address.lower()}"
        )

    # @precondition(lambda self: self.there_is_at_least_one_ask() == True)
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
                # will not pass every time. If there is an existing bid with higer price, reverts with: "Marketplace::bid too low"
                with reverts(self.marketplace.REVERT_BID_TOO_LOW()):
                    self.marketplace.bid(*bid_args)

    # @precondition(lambda self: self.there_is_at_least_one_bid() == True)
    def rule_cancel_bid(self, st_price):
        if not self.there_is_at_least_one_bid():
            self.rule_bid(st_price)

        bid = self.get_bid()
        self.marketplace.cancelBid(
            bid.nft.address, bid.nft.token_id, {"from": bid.buyer}
        )
        self.remove_bid(bid)

        pr_light_purple(
            f"cancelled bid. token_id={bid.nft.token_id},addr={bid.nft.address.address.lower()}"
        )

    # @precondition(lambda self: self.there_is_at_least_one_bid() == True)
    def rule_accept_bid(self):
        pr_light_purple("accepted bid")

    # @precondition(lambda self: self.there_is_at_least_one_ask() == True)
    def rule_transfer_has_ask(self):
        pr_cyan("transferred")

    # @precondition(lambda self: self.there_is_at_least_one_bid() == True)
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

    def update_bids(self, bid: Bid) -> None:
        # only create a new bid, if there isn't one
        # if there is a bid for this nft and token_id - overwrite
        self.bids[bid.buyer].append(bid)

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

    def contract_asks(self) -> List[Ask]:
        asks: List[Ask] = []
        total_supply = self.e7.totalSupply() + 1

        for token_id in range(total_supply):
            _ask = self.marketplace.asks(self.e7.address, token_id)
            # if ask exists
            if _ask[0] == True:
                ask = Ask(
                    True,
                    NFT(self.e7.address, token_id),
                    Account(_ask[1]),
                    int(_ask[2]),
                    _ask[3],
                )
                asks.append(ask)

        total_supply = self.e1.totalSupply() + 1

        for token_id in range(total_supply):
            _ask = self.marketplace.asks(self.e1.address, token_id)
            # if ask exists
            if _ask[0] == True:
                ask = Ask(
                    True,
                    NFT(self.e1.address, token_id),
                    Account(_ask[1]),
                    int(_ask[2]),
                    _ask[3],
                )
                asks.append(ask)

        return asks

    # todo: very similar to contract_asks. DRY!
    def contract_bids(self) -> List[Bid]:
        bids: List[Bid] = []
        total_supply = self.e7.totalSupply() + 1

        for token_id in range(total_supply):
            _bid = self.marketplace.bids(self.e7.address, token_id)
            # if bid exists
            if _bid[0] == True:
                bid = Bid(
                    True,
                    NFT(self.e7.address, token_id),
                    Account(_bid[1]),
                    int(_bid[2]),
                )
                bids.append(bid)

        total_supply = self.e1.totalSupply() + 1

        for token_id in range(total_supply):
            _bid = self.marketplace.bids(self.e1.address, token_id)
            # if ask exists
            if _bid[0] == True:
                bid = Bid(
                    True, NFT(self.e1.address, token_id), Account(_bid[1]), int(_bid[2])
                )
                bids.append(bid)

        return bids

    def assert_equal_to_one(item: T, others: List[T]) -> None:
        for _item in others:
            if item == _item:
                return
        assert False

    def flatten_dict(self, d: Dict[K, V]) -> List[V]:
        vs: List[V] = []
        for k in d.keys():
            vs = vs + d[k]
        return vs

    def there_is_at_least_one_ask(self) -> bool:
        ask = self.get_ask()
        if ask is None:
            return False
        else:
            return True

    def there_is_at_least_one_bid(self) -> bool:
        bid = self.get_bid()
        if bid is None:
            return False
        else:
            return True

    def get_bid(self) -> Optional[Bid]:
        """
        Gives back first bid that it finds
        """
        for _, bids in self.bids.items():
            if len(bids) > 0:
                return bids[0]
        return None

    def get_ask(self) -> Optional[Ask]:
        """
        Gives back first ask that it finds
        """
        for _, asks in self.asks.items():
            if len(asks) > 0:
                return asks[0]


def test_stateful(state_machine, A):
    marketplace = Marketplace.deploy({"from": A.admin})

    e7 = E721.deploy({"from": A.admin})
    e1 = E1155.deploy({"from": A.admin})

    state_machine(StateMachine, A, marketplace, e7, e1)
