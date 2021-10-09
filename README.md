# GEB Reward Adjusters

These contracts automatically adjust the amount of system coins that a GEB system gives to addresses that call specific functions inside the protocol.

Currently there are two types of reward adjusters: the MinMax which sets a base and max reward and the Fixed adjuster that only sets a fixed reward for calling a function.

Each rewarder is in charge with calling a [treasury param adjuster](https://github.com/reflexer-labs/geb-treasury-core-param-adjuster/blob/master/src/SFTreasuryCoreParamAdjuster.sol) contract that's in charge with modifying core params inside a [StabilityFeeTreasury](https://github.com/reflexer-labs/geb/blob/master/src/single/StabilityFeeTreasury.sol).
