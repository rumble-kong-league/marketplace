from dataclasses import dataclass
from brownie.network.account import Account
import json


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
