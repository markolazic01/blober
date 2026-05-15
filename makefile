.PHONY: build test build-all test-all benchmark

build:
	forge build --sizes

test:
	forge test -vvv

build-full:
	forge build --sizes
	FOUNDRY_PROFILE=benchmark forge build --sizes

test-full:
	forge test
	FOUNDRY_PROFILE=benchmark forge test -vvv

build-benchmark:
	FOUNDRY_PROFILE=benchmark forge build --sizes

test-benchmark:
	FOUNDRY_PROFILE=benchmark forge test -vvv
