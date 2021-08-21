# Security Tests

The contracts in this folder are the fuzz scripts for the rewards adjusters.

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/<name of file>.sol --contract <Name of contract> --config src/test/fuzz/echidna.yaml
```

Configs are in this folder (echidna.yaml).

The contracts in this folder are modified versions of the originals in the _src_ folder. They have assertions added to test for invariants, visibility of functions modified. Running the Fuzz against modified versions without the assertions is still possible, general properties on the Fuzz contract can be executed against unmodified contracts.

Tests should be run one at a time because they interfere with each other.

For all contracts being fuzzed, we tested the following:

1. Writing assertions and/or turning "requires" into "asserts" within the smart contract itself. This will cause echidna to fail fuzzing, and upon failures echidna finds the lowest value that causes the assertion to fail. This is useful to test bounds of functions (i.e.: modifying safeMath functions to assertions will cause echidna to fail on overflows, giving insight on the bounds acceptable). This is useful to find out when these functions revert. Although reverting will not impact the contract's state, it could cause a denial of service (or the contract not updating state when necessary and getting stuck). We check the found bounds against the expected usage of the system.
2. For contracts that have state, we also force the contract into common states and fuzz common actions.

Echidna will generate random values and call all functions failing either for violated assertions, or for properties (functions starting with echidna_) that return false. Sequence of calls is limited by seqLen in the config file. Calls are also spaced over time (both block number and timestamp) in random ways. Once the fuzzer finds a new execution path, it will explore it by trying execution with values close to the ones that opened the new path.

# Results

### 1. Fuzzing the fixed rewards adjuster

In this test (contract Fuzz in FixedRewardsAdjusterFuzz.sol) we test for overflows (overflows will be flagged as failures). the contract also creates and fuzzes a rewards receiver and calls recompute rewards for the given receiver (this is to increase effectiveness of the script, the fuzzer eventually finds it's way to creating a funding receiver and then recomputing its rewards but it takes many times longer. The usual functions remain open so the fuzzer can and will execute with others).

Whenever it recomputes rewards it asserts the value of the fixed reward and the effects of it in all other contracts (treasury param adjuster, the reward giving contract).

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-reward-adjuster/src/test/fuzz/FixedRewardsAdjusterFuzz.sol:Fuzz
assertion in fundingReceivers: passed! 🎉
assertion in fuzz_eth_price: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in oracleRelayer: passed! 🎉
assertion in RAY: passed! 🎉
assertion in treasury: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in fuzz_redemption_price: passed! 🎉
assertion in WAD: passed! 🎉
assertion in recomputeRewards: passed! 🎉
assertion in gasPriceOracle: passed! 🎉
assertion in force_recompute_rewards: passed! 🎉
assertion in fuzz_funding_receiver: passed! 🎉
assertion in treasuryParamAdjuster: passed! 🎉
assertion in THOUSAND: passed! 🎉
assertion in removeFundingReceiver: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in ethPriceOracle: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in fuzz_gas_price: passed! 🎉
assertion in addFundingReceiver: passed! 🎉
assertion in HUNDRED: passed! 🎉

Seed: 6304501904400170187
```

#### Conclusion: No exceptions noted


### Fuzz MinMax adjuster

In this test (contract Fuzz in FixedRewardsAdjusterFuzz.sol) we test for overflows (overflows will be flagged as failures). the contract also creates and fuzzes a rewards receiver and calls recompute rewards for the given receiver (this is to increase effectiveness of the script, the fuzzer eventually finds it's way to creating a funding receiver and then recomputing its rewards but it takes many times longer. The usual functions remain open so the fuzzer can and will execute with others).

Whenever it recomputes rewards it asserts the value of the fixed reward and the effects of it in all other contracts (treasury param adjuster, the reward giving contract).

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-reward-adjuster/src/test/fuzz/MinMaxRewardsAdjusterFuzz.sol:Fuzz
assertion in fundingReceivers: passed! 🎉
assertion in fuzz_eth_price: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in fuzz_funding_receiver: passed! 🎉
assertion in oracleRelayer: passed! 🎉
assertion in RAY: passed! 🎉
assertion in treasury: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in fuzz_redemption_price: passed! 🎉
assertion in WAD: passed! 🎉
assertion in recomputeRewards: passed! 🎉
assertion in gasPriceOracle: passed! 🎉
assertion in force_recompute_rewards: passed! 🎉
assertion in treasuryParamAdjuster: passed! 🎉
assertion in THOUSAND: passed! 🎉
assertion in removeFundingReceiver: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in ethPriceOracle: passed! 🎉
assertion in addFundingReceiver: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in fuzz_gas_price: passed! 🎉
assertion in HUNDRED: passed! 🎉

Seed: -5022403734377708343
```

#### Conclusion: No exceptions found
