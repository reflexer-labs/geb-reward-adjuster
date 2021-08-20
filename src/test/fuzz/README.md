# Security Tests

The contracts in this folder are the fuzz scripts for the ESM Threshold Setter.

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

### 1. Fuzzing for overflows (FuzzBounds)

In this test we want failures, as they will show us what are the bounds in which the contract operates safely.

Failures flag where overflows happen, and should be compared to expected inputs (to avoid overflows frm causing DoS).

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-debt-auction-param-setter/src/test/fuzz/DebtAuctionInitialParameterSetterFuzz.sol:Fuzz
echidna_debt_auction_bid_size_bound: passed! 🎉
echidna_initial_debt_auction_minted_tokens: passed! 🎉
echidna_initial_debt_auction_minted_tokens_bound: passed! 🎉
echidna_debt_auction_bid_size: passed! 🎉
assertion in fuzzParams: passed! 🎉
assertion in rmultiply: failed!💥
  Call sequence:
    rmultiply(8941294071242991741013141623006020698352,12970519921988971311690354564591009167)

assertion in ray: failed!💥
  Call sequence:
    ray(115795553445168649141101025579135698635404286616916628467799335108554)

assertion in bidTargetValue: passed! 🎉
assertion in multiply: failed!💥
  Call sequence:
    multiply(2725066548825930874958881611933156817,43109916273908539182156118718506260751084)

assertion in protocolTokenPremium: passed! 🎉
assertion in baseUpdateCallerReward: passed! 🎉
assertion in maxRewardIncreaseDelay: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in treasuryAllowance: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in wmultiply: failed!💥
  Call sequence:
    wmultiply(40639036560460496253109311379785551116901904830235584217005880217874725994,2864)

assertion in subtract: failed!💥
  Call sequence:
    subtract(0,1)

assertion in perSecondCallerRewardIncrease: passed! 🎉
assertion in rad: failed!💥
  Call sequence:
    rad(115794899141511153324851619876786844637068797117709)

assertion in manualSetDebtAuctionParameters: passed! 🎉
assertion in minProtocolTokenAmountOffered: passed! 🎉
assertion in getPremiumAdjustedProtocolTokenAmount: passed! 🎉
assertion in addition: failed!💥
  Call sequence:
    addition(74148970973594851740571204185379308733342590580922301826623562031989813614067,42050981052931150353965577213698609541419515978951639067457277862800188809577)

assertion in RAY: passed! 🎉
assertion in updateDelay: passed! 🎉
assertion in treasury: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in maxUpdateCallerReward: passed! 🎉
assertion in WAD: passed! 🎉
assertion in getRawProtocolTokenAmount: passed! 🎉
assertion in removeAuthorization: passed! 🎉
assertion in accountingEngine: passed! 🎉
assertion in protocolTokenOrcl: passed! 🎉
assertion in rdivide: failed!💥
  Call sequence:
    rdivide(115825465736981544347031552090208817915756752051042,780745183397972890879065050819452740316697669610652)

assertion in getNewDebtBid: passed! 🎉
assertion in setDebtAuctionInitialParameters: passed! 🎉
assertion in systemCoinOrcl: passed! 🎉
assertion in lastUpdateTime: passed! 🎉
assertion in range: passed! 🎉
assertion in rpower: failed!💥
  Call sequence:
    rpower(340300460364730518656359006319414565551,329460461862177295882379727161694,0)

assertion in minimum: passed! 🎉
assertion in getCallerReward: passed! 🎉
assertion in wdivide: failed!💥
  Call sequence:
    wdivide(115814166400482211444885527025002270214358626434757228712349,79871747325669261343077702811224544011127738076672493068677458)

assertion in modifyParameters: passed! 🎉

Seed: 2825694286002874683
```

Most of these failures are well known (math functions), we will focus on the ones specific to this contract:

```
assertion in getPremiumAdjustedProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(2,7696469028944939096644330046923983.291495366604588268,115926436795955985160419997568026068982.163811880113870634,120642387219613518400626400807383327335171361243)
    getPremiumAdjustedProtocolTokenAmount()
```

Prot Price of 2, bid target value of 115926436795955985160419997568026068982.163811880113870634 and protocolTokenPremium of 999
(coin price does not affect it).

Here the fuzzer reduced the prot price to two, but what actually causes the overflow are the consecutive multiplications up front (bidTargetValue * WAD * protocolTokenPremium). This bound could be increased by reordering the arythmetic operations (the way they are in ```setDebtAuctionInitialParameters()```), with the added benefit of alighning both results (though diferrences are minimal, refer to the next test for more details).

We adjusted the formula and reran the script with the result below:

```
getPremiumAdjustedProtocolTokenAmount: passed! 🎉
assertion in addition: failed!💥
  Call sequence:
    addition(74148970973594851740571204185379308733342590580922301826623562031989813614067,42050981052931150353965577213698609541419515978951639067457277862800188809577)
```

Pro price: 74148970973594851740571204185379308733,342,590,580,922,301,826,623.562031989813614067
bid target value: 42050981052931150353965577213698609541,419,515,978,951,639,067,457.277862800188809577

Bounds increased consideraly, and now the formula matches the one in ```setDebtAuctionInitialParameters()```.

```
assertion in getRawProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(12363724300,488908949313535191735025544936183155531.510918229770825230,1157998202302582545322303197744827203045317.72204312158718461,1504229331527011360703020412954109405186050922765518291569)
    getRawProtocolTokenAmount()
```

Prot price of 12363724300, bid target value of 1157998202302582545322303197744827203045317.72204312158718461. Here the fuzzer also made it's best to reduce prot price, ended up with a large bitTarget, if we balance the two (up to 1mm prot price):

prot price 1,236,372.430000000000000000
bid target value 11579982023025825453223031977.4482720304531772204312158718461

```
assertion in getNewDebtBid: failed!💥
  Call sequence:
    fuzzParams(17,657,843,745,536,337.527512516605525074, 1,589,585.014227748301395367 ,115,804,424,984,310.826176615835225343,0)
    getNewDebtBid()
````

A Bid target price of 115,804,424,984,310.826176615835225343 alone makes the function revert due to an overflow.

```
assertion in setDebtAuctionInitialParameters: failed!💥
  Call sequence:
    fuzzParams(36,143,935,985.15173946989974365, 20,657,823,283493783720108499, 115,803,057,612,405.542733808860688740,0)
    setDebtAuctionInitialParameters(0x0)
```
Will overflow only for Prot price in the trillion range, coin price over 20mm, and bidTargetVlue in the Trillion Range. (tokenPremium set to 1).

#### Conclusion: Bounds are plentyful and should not affect the system in normal conditions.


### Fuzz Properties (Fuzz)

In this case we setup the setter, and check properties.

Here we are not looking for bounds, but instead checking the properties that either should remain constant:

- initial debt auction minted tokens bounds and value
- bid size bounds and value

These properties are verified in between all calls.

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-debt-auction-param-setter/src/test/fuzz/DebtAuctionInitialParameterSetterFuzz.sol:Fuzz
echidna_debt_auction_bid_size_bound: passed! 🎉
echidna_initial_debt_auction_minted_tokens: passed! 🎉
echidna_initial_debt_auction_minted_tokens_bound: passed! 🎉
echidna_debt_auction_bid_size: passed! 🎉

Seed: -8306747842532670008
```

#### Conclusion: No exceptions found
