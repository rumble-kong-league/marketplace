# NFT Marketplace

![locker-room](static/locker-room.png)

Contracts herein define a minimal general trustless marketplace for any ERC-721 or ERC-1155 implementation. They support:

- batch trading
- royalties
- withdraw pattern to avoid re-entrancy issues
- events for optimal subgraph indexing

They are well-tested, a combination of stateful and unit tests was used.

You can use poetry for easy python virtual environment and requirements handling.

## Dev

To run tests

`brownie test -s`

This will give you unsupressed output for each example ran in stateful tests.

LFG 👑🦍
