VERSION ?= $(shell cat pyproject.toml| grep version| awk -F'"' {'print $$2'})


docker:
	docker build -t rumble-kong-league/marketplace:v$(VERSION) .

shell:
	docker build -t rumble-kong-league/marketplace:v${VERSION}-shell -f poetry.Dockerfile .
	docker run -it --rm -v $(PWD):/marketplace rumble-kong-league/marketplace:v${VERSION}-shell

clean-shell:
	docker rmi rumble-kong-league/marketplace:v${VERSION}-shell
