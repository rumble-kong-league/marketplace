#!/bin/bash

poetry update
poetry run brownie pm install OpenZeppelin/openzeppelin-contracts@4.3.0

cd /marketplace/contracts
poetry run brownie compile --all

cd /marketplace

poetry shell
