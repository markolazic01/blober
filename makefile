.PHONY: build test build-full test-full build-benchmark test-benchmark symbolic

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

# Halmos symbolic proofs (test/symbolic): needs `pip install halmos==0.3.3`
symbolic:
	halmos --match-contract SymbolicTest --loop 4 --solver-timeout-assertion 0
