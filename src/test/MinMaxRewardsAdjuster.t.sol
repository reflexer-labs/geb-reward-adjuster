pragma solidity 0.6.7;

import "ds-test/test.sol";
import "../MinMaxRewardsAdjuster.sol";

import { OracleRelayer } from "geb/OracleRelayer.sol";
import { StabilityFeeTreasury } from "geb/StabilityFeeTreasury.sol";
import {Coin} from "geb/Coin.sol";
import "geb/SAFEEngine.sol";
import {CoinJoin} from "geb/BasicTokenAdapters.sol";

import {SFTreasuryCoreParamAdjuster} from "geb-treasury-core-param-adjuster/SFTreasuryCoreParamAdjuster.sol";
import {IncreasingTreasuryReimbursement} from "geb-treasury-reimbursement/reimbursement/single/IncreasingTreasuryReimbursement.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract Usr {
    address adjuster;

    constructor(address adjuster_) public {
        adjuster = adjuster_;
    }

    function callAdjuster(bytes memory data) internal {
        (bool success, ) = adjuster.call(data);
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    function modifyParameters(bytes32, address) public { callAdjuster(msg.data); }
    function modifyParameters(address, bytes4, bytes32, uint) public { callAdjuster(msg.data); }
    function addFundingReceiver(address, bytes4, uint, uint, uint, uint) public { callAdjuster(msg.data); }
    function removeFundingReceiver(address, bytes4) public { callAdjuster(msg.data); }
    function recomputeRewards(address, bytes4) public { callAdjuster(msg.data); }
}

contract TreasuryFundable is IncreasingTreasuryReimbursement {
    event ModifyParameters(bytes32 parameter, uint256 val);

    constructor(
        address treasury
    ) public IncreasingTreasuryReimbursement (
        treasury,
        1,
        1,
        10**27
    ) {}

    function modifyParameters(bytes32 parameter, uint256 val) external {

        if (parameter == "baseUpdateCallerReward") {
          require(val <= maxUpdateCallerReward, "TreasuryFundable/invalid-base-caller-reward");
          baseUpdateCallerReward = val;
        }
        else if (parameter == "maxUpdateCallerReward") {
          require(val >= baseUpdateCallerReward, "TreasuryFundable/invalid-max-caller-reward");
          maxUpdateCallerReward = val;
        }
        else if (parameter == "perSecondCallerRewardIncrease") {
          require(val >= RAY, "TreasuryFundable/invalid-caller-reward-increase");
          perSecondCallerRewardIncrease = val;
        }
        else if (parameter == "maxRewardIncreaseDelay") {
          require(val > 0, "TreasuryFundable/invalid-max-increase-delay");
          maxRewardIncreaseDelay = val;
        }
        else revert("TreasuryFundable/modify-unrecognized-param");
        emit ModifyParameters(parameter, val);
    }
}

contract Feed {
    uint price;

    constructor (uint price_) public {
        price = price_;
    }

    function read() public view returns (uint) {
        return price;
    }
}

contract MinMaxRewardsAdjusterTest is DSTest {
    Hevm hevm;

    MinMaxRewardsAdjuster adjuster;
    StabilityFeeTreasury treasury;
    OracleRelayer oracleRelayer;
    Feed ethPriceOracle;
    Feed gasPriceOracle;
    SAFEEngine safeEngine;
    Coin systemCoin;
    CoinJoin systemCoinA;
    SFTreasuryCoreParamAdjuster treasuryParamAdjuster;
    TreasuryFundable treasuryFundable;
    Usr usr;

    uint256 public updateDelay = 1 days;
    uint256 public lastUpdateTime = 604411201;
    uint256 public treasuryCapacityMultiplier = 100;
    uint256 public minTreasuryCapacity = 1000 ether;
    uint256 public minimumFundsMultiplier = 100;
    uint256 public minMinimumFunds = 1 ether;
    uint256 public pullFundsMinThresholdMultiplier = 100;
    uint256 public minPullFundsThreshold = 2 ether;

    uint256 public constant WAD            = 10**18;
    uint256 public constant RAY            = 10**27;

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        safeEngine  = new SAFEEngine();
        systemCoin = new Coin("Coin", "COIN", 99);
        systemCoinA = new CoinJoin(address(safeEngine), address(systemCoin));
        treasury = new StabilityFeeTreasury(address(safeEngine), address(0x1), address(systemCoinA));
        oracleRelayer = new OracleRelayer(address(safeEngine));
        ethPriceOracle = new Feed(1000 ether);
        gasPriceOracle = new Feed(100 * 10**9); // 100 gwei
        treasuryFundable = new TreasuryFundable(address(treasury));

        treasuryParamAdjuster = new SFTreasuryCoreParamAdjuster(
            address(treasury),
            updateDelay,
            lastUpdateTime,
            treasuryCapacityMultiplier,
            minTreasuryCapacity,
            minimumFundsMultiplier,
            minMinimumFunds,
            pullFundsMinThresholdMultiplier,
            minPullFundsThreshold
        );

        treasury.addAuthorization(address(treasuryParamAdjuster));

        adjuster = new MinMaxRewardsAdjuster(
            address(oracleRelayer),
            address(treasury),
            address(gasPriceOracle),
            address(ethPriceOracle),
            address(treasuryParamAdjuster)
        );

        treasuryParamAdjuster.addRewardAdjuster(address(adjuster));
        treasury.addAuthorization(address(adjuster));

        usr = new Usr(address(adjuster));
    }


    function test_setup() public {
        assertEq(address(adjuster.oracleRelayer()), address(oracleRelayer));
        assertEq(address(adjuster.treasury()), address(treasury));
        assertEq(address(adjuster.gasPriceOracle()), address(gasPriceOracle));
        assertEq(address(adjuster.ethPriceOracle()), address(ethPriceOracle));
        assertEq(address(adjuster.treasuryParamAdjuster()), address(treasuryParamAdjuster));
        assertEq(adjuster.authorizedAccounts(address(this)), 1);
    }

    function testFail_setup_null_oracleRelayer() public {
        adjuster = new MinMaxRewardsAdjuster(
            address(0),
            address(treasury),
            address(gasPriceOracle),
            address(ethPriceOracle),
            address(treasuryParamAdjuster)
        );
    }

    function testFail_setup_null_treasury() public {
        adjuster = new MinMaxRewardsAdjuster(
            address(oracleRelayer),
            address(0),
            address(gasPriceOracle),
            address(ethPriceOracle),
            address(treasuryParamAdjuster)
        );
    }

    function testFail_setup_null_gasPriceOracle() public {
        adjuster = new MinMaxRewardsAdjuster(
            address(oracleRelayer),
            address(treasury),
            address(0),
            address(ethPriceOracle),
            address(treasuryParamAdjuster)
        );
    }

    function testFail_setup_null_ethPriceOracle() public {
        adjuster = new MinMaxRewardsAdjuster(
            address(oracleRelayer),
            address(treasury),
            address(gasPriceOracle),
            address(0),
            address(treasuryParamAdjuster)
        );
    }

    function testFail_setup_null_treasuryParamAdjuster() public {
        adjuster = new MinMaxRewardsAdjuster(
            address(oracleRelayer),
            address(treasury),
            address(gasPriceOracle),
            address(ethPriceOracle),
            address(0)
        );
    }

    function test_modify_parameters() public {
        OracleRelayer oracleRelayer2 = new OracleRelayer(address(safeEngine));
        adjuster.modifyParameters("oracleRelayer", address(oracleRelayer2));
        assertEq(address(adjuster.oracleRelayer()), address(oracleRelayer2));

        adjuster.modifyParameters("treasury", address(0x123));
        assertEq(address(adjuster.treasury()), address(0x123));

        adjuster.modifyParameters("gasPriceOracle", address(0x123));
        assertEq(address(adjuster.gasPriceOracle()), address(0x123));

        adjuster.modifyParameters("ethPriceOracle", address(0x123));
        assertEq(address(adjuster.ethPriceOracle()), address(0x123));

        adjuster.modifyParameters("treasuryParamAdjuster", address(0x123));
        assertEq(address(adjuster.treasuryParamAdjuster()), address(0x123));
    }

    function testFail_modify_parameters_null() public {
        adjuster.modifyParameters("treasury", address(0x0));
    }

    function testFail_modify_parameters_unauthorized() public {
        usr.modifyParameters("treasury", address(0x123));
    }

    function test_modify_parameters_fundingReceiver() public {
        // adding a funding receiver
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 301);

        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "gasAmountForExecution", 300);
        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "updateDelay", 2 days);
        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "baseRewardMultiplier", 200);
        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "maxRewardMultiplier", 201);

        (,
        uint gasAmountForExecution,
        uint updateDelay_,
        uint baseRewardMultiplier,
        uint maxRewardMultiplier
        ) = adjuster.fundingReceivers(address(treasuryFundable), bytes4("0x2"));

        assertEq(gasAmountForExecution, 300);
        assertEq(updateDelay_, 2 days);
        assertEq(baseRewardMultiplier, 200);
        assertEq(maxRewardMultiplier, 201);
    }

    function testFail_modify_parameters_fundingReceiver_invalid_param() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);

        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "invalid", 300);
    }

    function testFail_modify_parameters_fundingReceiver_unauthorized() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);

        usr.modifyParameters(address(treasuryFundable), bytes4("0x2"), "gasAmountForExecution", 300);
    }

    function testFail_modify_parameters_fundingReceiver_null_param() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);

        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "gasAmountForExecution", 0);
    }

    function testFail_modify_parameters_fundingReceiver_invalid_gasAmountForExecution() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);

        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "gasAmountForExecution", block.gaslimit);
    }

    function testFail_modify_parameters_fundingReceiver_invalid_fixedRewardMultiplier() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);

        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "fixedRewardMultiplier", 99);
    }

    function testFail_modify_parameters_fundingReceiver_invalid_fixedRewardMultiplier2() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);

        adjuster.modifyParameters(address(treasuryFundable), bytes4("0x2"), "fixedRewardMultiplier", 1001);
    }

    function test_add_funding_receiver() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 102);

        (
        uint lastUpdateTime_,
        uint gasAmountForExecution,
        uint updateDelay_,
        uint baseRewardMultiplier,
        uint maxRewardMultiplier
        ) = adjuster.fundingReceivers(address(treasuryFundable), bytes4("0x2"));

        assertEq(lastUpdateTime_, now);
        assertEq(gasAmountForExecution, 10**6);
        assertEq(updateDelay_, 1 days);
        assertEq(baseRewardMultiplier, 100);
        assertEq(maxRewardMultiplier, 102);
    }

    function testFail_add_null_funding_receiver() public {
        adjuster.addFundingReceiver(address(0), bytes4("0x2"), 1 days, 10**6, 100, 100);
    }

    function testFail_add_funding_receiver_null_updateDelay() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 0, 10**6, 100, 100);
    }

    function testFail_add_funding_receiver_invalid_baseRewardMultiplier() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 99, 100);
    }

    function testFail_add_funding_receiver_invalid_baseRewardMultiplier2() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 1001, 100);
    }

    function testFail_add_funding_receiver_invalid_maxRewardMultiplier() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 99);
    }

    function testFail_add_funding_receiver_invalid_maxRewardMultiplier2() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 1001);
    }

    function testFail_add_funding_receiver_null_gasAmountForExecution() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 0, 100, 101);
    }

    function testFail_add_funding_receiver_invalid_gasAmountForExecution() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, block.gaslimit, 100, 101);
    }

    function testFail_add_funding_receiver_already_exists() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);
    }

    function testFail_add_funding_receiver_unauthorized() public {
        usr.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);
    }

    function test_remove_funding_receiver() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);
        (uint lastUpdateTime_,,,,) = adjuster.fundingReceivers(address(treasuryFundable), bytes4("0x2"));
        assertEq(lastUpdateTime_, now);

        adjuster.removeFundingReceiver(address(treasuryFundable), bytes4("0x2"));
        (lastUpdateTime_,,,,) = adjuster.fundingReceivers(address(treasuryFundable), bytes4("0x2"));
        assertEq(lastUpdateTime_, 0);
    }

    function testFail_remove_funding_receiver_unexistent() public {
        adjuster.removeFundingReceiver(address(treasuryFundable), bytes4("0x2"));
    }

    function testFail_remove_funding_receiver_unauthorized() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);

        usr.removeFundingReceiver(address(treasuryFundable), bytes4("0x2"));
    }

    function test_recompute_rewards() public {
        adjuster.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 101);
        treasuryParamAdjuster.addFundedFunction(address(treasuryFundable), bytes4("0x2"), 1);

        hevm.warp(now + 1 days);
        adjuster.recomputeRewards(address(treasuryFundable), bytes4("0x2"));

        (
        uint lastUpdateTime_,
        uint gasAmountForExecution,
        uint updateDelay_,
        uint baseRewardMultiplier,
        uint maxRewardMultiplier
        ) = adjuster.fundingReceivers(address(treasuryFundable), bytes4("0x2"));

        assertEq(lastUpdateTime_, now);
        assertEq(gasAmountForExecution, 10**6);
        assertEq(updateDelay_, 1 days);
        assertEq(baseRewardMultiplier, 100);
        assertEq(maxRewardMultiplier, 101);

        uint baseRewardFiatValue = gasPriceOracle.read() * gasAmountForExecution * WAD / ethPriceOracle.read();
        uint newBaseReward = (baseRewardFiatValue * RAY / oracleRelayer.redemptionPrice()) * baseRewardMultiplier / 100;
        uint newMaxReward = newBaseReward * maxRewardMultiplier / 100;

        assertEq(treasuryFundable.baseUpdateCallerReward(), newBaseReward);
        assertEq(treasuryFundable.maxUpdateCallerReward(), newMaxReward);

        (, uint perBlockAllownace) = treasury.getAllowance(address(treasuryFundable));
        assertEq(perBlockAllownace, newMaxReward * RAY);

        (, uint latestMaxReward) = treasuryParamAdjuster.whitelistedFundedFunctions(address(treasuryFundable), bytes4("0x2"));
        assertEq(latestMaxReward, newMaxReward);
        assertEq(treasuryParamAdjuster.dynamicRawTreasuryCapacity(), newMaxReward);
    }

    function test_recompute_rewards_base_greater_than_prev_max() public {
        // precalculating new rewards
        (
            , uint gasAmountForExecution,,
            uint baseRewardMultiplier,
            uint maxRewardMultiplier
        ) = adjuster.fundingReceivers(address(treasuryFundable), bytes4("0x2"));

        uint baseRewardFiatValue = gasPriceOracle.read() * gasAmountForExecution * WAD / ethPriceOracle.read();
        uint newBaseReward = (baseRewardFiatValue * RAY / oracleRelayer.redemptionPrice()) * baseRewardMultiplier / 100;
        uint newMaxReward = newBaseReward * maxRewardMultiplier / 100;

        treasuryFundable.modifyParameters("maxUpdateCallerReward", newBaseReward - 1);

        test_recompute_rewards();
    }

    function test_recompute_rewards_max_lower_than_prev_base() public {
        // precalculating new rewards
        (
            , uint gasAmountForExecution,,
            uint baseRewardMultiplier,
            uint maxRewardMultiplier
        ) = adjuster.fundingReceivers(address(treasuryFundable), bytes4("0x2"));

        uint baseRewardFiatValue = gasPriceOracle.read() * gasAmountForExecution * WAD / ethPriceOracle.read();
        uint newBaseReward = (baseRewardFiatValue * RAY / oracleRelayer.redemptionPrice()) * baseRewardMultiplier / 100;
        uint newMaxReward = newBaseReward * maxRewardMultiplier / 100;

        treasuryFundable.modifyParameters("baseUpdateCallerReward", newMaxReward + 1);

        test_recompute_rewards();
    }

    function sort(uint[2] memory input) public returns (uint[2] memory) {
        if (input[1] >= input[0]) return input;
        return [input[1], input[0]];
    }

    function test_recompute_rewards(uint[2] memory previousRewards) public {
        previousRewards = sort(previousRewards);
        if (treasuryFundable.baseUpdateCallerReward() < previousRewards[1]) {
            treasuryFundable.modifyParameters("maxUpdateCallerReward", previousRewards[1]);
            treasuryFundable.modifyParameters("baseUpdateCallerReward", previousRewards[0]);
        } else {
            treasuryFundable.modifyParameters("baseUpdateCallerReward", previousRewards[0]);
            treasuryFundable.modifyParameters("maxUpdateCallerReward", previousRewards[1]);
        }

        test_recompute_rewards();
    }
}
