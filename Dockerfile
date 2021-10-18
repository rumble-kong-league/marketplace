FROM python:3.9-slim-buster

RUN mkdir /marketplace && \
    apt-get update && \
    apt-get install -y curl linux-headers-amd64 gcc

RUN curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python -

COPY / /marketplace

WORKDIR /marketplace

RUN /root/.poetry/bin/poetry update
CMD ["/root/.poetry/bin/poetry run"]
