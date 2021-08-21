pragma solidity 0.6.7;

import { DSTest } from "../../../lib/geb-treasury-core-param-adjuster/lib/geb-treasuries/lib/geb/lib/ds-token/lib/ds-test/src/test.sol";
import {SFTreasuryCoreParamAdjuster} from "../../../lib/geb-treasury-core-param-adjuster/src/SFTreasuryCoreParamAdjuster.sol";
import "./MinMaxRewardsAdjusterMock.sol";

contract TreasuryFundableMock {
    uint public maxUpdateCallerReward;
    uint public baseUpdateCallerReward;

    function modifyParameters(bytes32 param, uint val) public {
        if (param == "maxUpdateCallerReward") maxUpdateCallerReward = val;
        else if (param == "baseUpdateCallerReward") baseUpdateCallerReward = val;
        else revert("unrecognized param");
    }
}

abstract contract Hevm {
    function warp(uint256) virtual public;
}

contract StabilityFeeTreasuryMock {
    mapping (address => uint) internal totalAllowance;
    mapping (address => uint) internal perBlockAllowance;

    function getAllowance(address who) public view returns (uint256, uint256) {
        return (
            totalAllowance[who],
            perBlockAllowance[who]
        );
    }
    function setPerBlockAllowance(address who, uint256 allowance) external {
        perBlockAllowance[who] = allowance;
    }
}
contract OracleRelayerMock {
    uint redemptionPrice_ = 1;
    function redemptionPrice() public returns (uint256) {
        return redemptionPrice_;
    }

    function write(uint val) public {
        redemptionPrice_ = val;
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

    function write(uint val) public {
        price = val;
    }
}

contract TreasuryParamAdjusterMock {
    uint public lastUpdateTime;
    function adjustMaxReward(address, bytes4, uint256) external {
        lastUpdateTime = now;
    }
}

contract TokenMock {
    uint constant maxUint = uint(0) - 1;
    mapping (address => uint256) public received;
    mapping (address => uint256) public sent;

    function totalSupply() public view returns (uint) {
        return maxUint;
    }
    function balanceOf(address src) public view returns (uint) {
        return maxUint;
    }
    function allowance(address src, address guy) public view returns (uint) {
        return maxUint;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        received[dst] += wad;
        sent[src]     += wad;
        return true;
    }

    function approve(address guy, uint wad) virtual public returns (bool) {
        return true;
    }
}

// @notice Fuzz the whole thing, failures will show bounds (run with checkAsserts: on)
contract Fuzz is MinMaxRewardsAdjusterMock {

    TreasuryFundableMock treasuryFundable;

    constructor() MinMaxRewardsAdjusterMock(
            address(new OracleRelayerMock()),
            address(new StabilityFeeTreasuryMock()),
            address(3),                             // gasPriceOracle
            address(4),                             // ethPriceOracle
            address(new TreasuryParamAdjusterMock())
    ) public {

        ethPriceOracle = OracleLike(address(new Feed(1000 ether)));
        gasPriceOracle = OracleLike(address(new Feed(100 * 10**9))); // 100 gwei
        treasuryFundable = new TreasuryFundableMock();

        authorizedAccounts[address(this)] = 1;
    }

    function max(uint a, uint b) private returns (uint) {
        return (a > b) ? a : b;
    }

    function fuzz_gas_price(uint val) public {
        val = max(val, 10**8); // minimum .1 gwei
        Feed(address(gasPriceOracle)).write(val);
        assert(gasPriceOracle.read() == val);
    }

    function fuzz_eth_price(uint val) public {
        val = max(val, 1 ether); // minimum 1 usd
        Feed(address(ethPriceOracle)).write(val);
        assert(ethPriceOracle.read() == val);
    }

    function fuzz_redemption_price(uint val) public {
        val = max(val, .01 ether); // minimum .01 usd
        Feed(address(oracleRelayer)).write(val);
        assert(oracleRelayer.redemptionPrice() == val);
    }

    function fuzz_funding_receiver(uint gasAmountForExecution, uint baseRewardMultiplier, uint maxRewardMultiplier) public {
        gasAmountForExecution = max(gasAmountForExecution, 10000); // minimum 10k
        baseRewardMultiplier = max(baseRewardMultiplier % 1000, 100); // all allowed values (100 ~ 1000)
        maxRewardMultiplier = max(max(maxRewardMultiplier % 1000, 100), baseRewardMultiplier); // all allowed values (100 ~ 1000)
        // adding one funding receiver to force execution of recompute_rewards
        FundingReceiver storage newReceiver = fundingReceivers[address(treasuryFundable)][bytes4("0x2")];
        require(newReceiver.lastUpdateTime == 0, "FixedRewardsAdjuster/receiver-already-added");

        // Add the receiver's data
        newReceiver.lastUpdateTime        = now - 10 days;
        newReceiver.updateDelay           = 1;
        newReceiver.gasAmountForExecution = gasAmountForExecution;
        newReceiver.baseRewardMultiplier = baseRewardMultiplier;
        newReceiver.maxRewardMultiplier = maxRewardMultiplier;
    }

    function force_recompute_rewards() public {
        this.recomputeRewards(address(treasuryFundable), bytes4("0x2"));

        uint baseRewardFiatValue = gasPriceOracle.read() * fundingReceivers[address(treasuryFundable)][bytes4("0x2")].gasAmountForExecution * WAD / ethPriceOracle.read();
        uint newBaseReward = (baseRewardFiatValue * RAY / oracleRelayer.redemptionPrice()) * fundingReceivers[address(treasuryFundable)][bytes4("0x2")].baseRewardMultiplier / 100;
        uint newMaxReward = newBaseReward * fundingReceivers[address(treasuryFundable)][bytes4("0x2")].maxRewardMultiplier / 100;

        assert(treasuryFundable.baseUpdateCallerReward() == newBaseReward);
        assert(treasuryFundable.maxUpdateCallerReward() == newMaxReward);

        (, uint perBlockAllownace) = treasury.getAllowance(address(treasuryFundable));
        assert(perBlockAllownace == newMaxReward * RAY);
    }
}

contract FuzzTest is Fuzz, DSTest {
    Hevm hevm;
    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);
    }

    function test_fuzz_setup_minmax() public {
        this.addFundingReceiver(address(treasuryFundable), bytes4("0x2"), 1 days, 10**6, 100, 100);
        hevm.warp(now + 1 days);
        this.recomputeRewards(address(treasuryFundable), bytes4("0x2"));

        (
        uint lastUpdateTime_,
        uint gasAmountForExecution,
        uint updateDelay_,
        uint baseRewardMultiplier,
        uint maxRewardMultiplier
        ) = this.fundingReceivers(address(treasuryFundable), bytes4("0x2"));

        assertEq(lastUpdateTime_, now);
        assertEq(gasAmountForExecution, 10**6);
        assertEq(updateDelay_, 1 days);
        assertEq(baseRewardMultiplier, 100);
        assertEq(maxRewardMultiplier, 100);

        uint baseRewardFiatValue = gasPriceOracle.read() * gasAmountForExecution * WAD / ethPriceOracle.read();
        uint newBaseReward = (baseRewardFiatValue * RAY / oracleRelayer.redemptionPrice()) * baseRewardMultiplier / 100;
        uint newMaxReward = newBaseReward * maxRewardMultiplier / 100;

        assertEq(treasuryFundable.baseUpdateCallerReward(), newBaseReward);
        assertEq(treasuryFundable.maxUpdateCallerReward(), newMaxReward);

        (, uint perBlockAllownace) = treasury.getAllowance(address(treasuryFundable));
        assertEq(perBlockAllownace, newMaxReward * RAY);
    }
}
