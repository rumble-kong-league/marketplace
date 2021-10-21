FROM python:3.9-slim-buster as requirements

RUN mkdir /marketplace && \
    apt-get update && \
    apt-get install -y linux-headers-amd64 gcc && \
    rm -rf /var/lib/apt/lists/*

RUN pip install poetry

COPY / /marketplace
WORKDIR /marketplace

RUN poetry export -f requirements.txt --without-hashes -o /tmp/requirements.txt

CMD ["/root/.poetry/bin/poetry shell"]

FROM python:3.9-slim-buster

RUN mkdir /marketplace \
    && apt-get update \
    && apt-get install -y curl linux-headers-amd64 gcc \
    && rm -rf /var/lib/apt/lists/*

COPY / /marketplace
WORKDIR /marketplace

COPY --from=requirements /tmp/requirements.txt .

RUN pip install -r requirements.txt \
    && brownie pm install OpenZeppelin/openzeppelin-contracts@4.3.0

RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - \
    && apt-get update \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g ganache-cli

WORKDIR /marketplace/contracts

RUN brownie compile --all

CMD ["/usr/local/bin/brownie","test"]
