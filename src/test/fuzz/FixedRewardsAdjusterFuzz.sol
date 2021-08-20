pragma solidity 0.6.7;

import { DSTest } from "../../../lib/geb-treasury-core-param-adjuster/lib/geb-treasuries/lib/geb/lib/ds-token/lib/ds-test/src/test.sol";
// import { OracleRelayer } from "../../../lib/geb/src/OracleRelayer.sol";
// import { StabilityFeeTreasury } from "../../../lib/geb/src//StabilityFeeTreasury.sol";
// import {Coin} from "../../../lib/geb/src//Coin.sol";
// import "../../../lib/geb/src//SAFEEngine.sol";
// import {CoinJoin} from "../../../lib/geb/src//BasicTokenAdapters.sol";
// import {SFTreasuryCoreParamAdjuster} from "../../../lib/geb-treasury-core-param-adjuster/src/SFTreasuryCoreParamAdjuster.sol";
// import {MandatoryFixedTreasuryReimbursement} from "../../../lib/geb-treasury-reimbursement/src/MandatoryFixedTreasuryReimbursement.sol";
import "./FixedRewardsAdjusterMock.sol";

// contract AccountingEngine {
//     uint256 public initialDebtAuctionMintedTokens;
//     uint256 public debtAuctionBidSize;

//     function modifyParameters(bytes32 parameter, uint data) external {
//         if (parameter == "debtAuctionBidSize") debtAuctionBidSize = data;
//         else if (parameter == "initialDebtAuctionMintedTokens") initialDebtAuctionMintedTokens = data;
//     }
// }

// contract Feed {
//     uint256 public priceFeedValue;
//     bool public hasValidValue;
//     constructor(uint256 initPrice, bool initHas) public {
//         priceFeedValue = uint(initPrice);
//         hasValidValue = initHas;
//     }
//     function set_val(uint newPrice) external {
//         priceFeedValue = newPrice;
//     }
//     function set_has(bool newHas) external {
//         hasValidValue = newHas;
//     }
//     function getResultWithValidity() external returns (uint256, bool) {
//         return (priceFeedValue, hasValidValue);
//     }
// }

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

contract OracleRelayerMock {
    uint redempPrice = 3 ether;
    function redemptionPrice() public returns (uint) {
        return redempPrice;
    }
}

// @notice Fuzz the whole thing, failures will show bounds (run with checkAsserts: on)
contract Setup is FixedRewardsAdjusterMock, DSTest {

    TokenMock systemCoin;

    constructor() FixedRewardsAdjusterMock(
            address(new OracleRelayerMock()), // oracleRelayer
            address(2),                       // treasury
            address(3),                       // gasPriceOracle
            address(4),                       // ethPriceOracle
            address(5)                        // treasuryParamAdjuster
    ) public {

        SAFEEngine safeEngine  = new SAFEEngine();
        safeEngine  = new SAFEEngine();
        systemCoin = new Coin("Coin", "COIN", 99);
        systemCoinA = new CoinJoin(address(safeEngine), address(systemCoin));
        treasury = new StabilityFeeTreasury(address(safeEngine), address(0x1), address(systemCoinA));
        oracleRelayer = new OracleRelayer(address(safeEngine));
        ethPriceOracle = new Feed(1000 ether);
        gasPriceOracle = new Feed(100 * 10**9); // 100 gwei
        treasuryFundable = new TreasuryFundable(address(treasury), 1 ether);

        // systemCoin = TokenMock(address(treasury.systemCoin()));

        // MockTreasury(address(treasury)).setTotalAllowance(address(this), uint(-1));
        // MockTreasury(address(treasury)).setPerBlockAllowance(address(this), 10E45);
    }

    function setUp() public {}

    function test_fuzz() public {
        assert(true);
    }

    // function fuzzParams(uint protPrice, uint coinPrice, uint _bidTargetValue, uint _protocolTokenPremium) public {
    //     Feed(address(protocolTokenOrcl)).set_val(protPrice);
    //     Feed(address(systemCoinOrcl)).set_val(coinPrice);
    //     bidTargetValue = (_bidTargetValue == 0) ? 1 : _bidTargetValue;
    //     protocolTokenPremium = range(_protocolTokenPremium, 1, 999);
    // }
}

// // @notice Fuzz the contracts testing properties
// contract Fuzz is DebtAuctionInitialParameterSetterMock {

//     TokenMock systemCoin;
//     uint256 _coinsToMint = 1E40;

//     constructor() DebtAuctionInitialParameterSetterMock(
//             address(new Feed(1000 ether, true)),
//             address(new Feed(2.015 ether, true)),
//             address(new AccountingEngine()),
//             address(new MockTreasury(address(new TokenMock()))),
//             3600, // periodSize
//             5E18, // baseUpdateCallerReward
//             10E18, // maxUpdateCallerReward
//             1000192559420674483977255848, // perSecondCallerRewardIncrease, 100%/h
//             0.5 ether, // minProtocolTokenAmountOffered
//             700, // protocolTokenPremium, 30%
//             100000 ether // bidTargetValue, 100k
//     ) public {

//         systemCoin = TokenMock(address(treasury.systemCoin()));

//         MockTreasury(address(treasury)).setTotalAllowance(address(this), uint(-1));
//         MockTreasury(address(treasury)).setPerBlockAllowance(address(this), 10E45);
//         maxRewardIncreaseDelay = 6 hours;
//     }

//     function fuzzParams(uint protPrice, uint coinPrice, uint _bidTargetValue, uint _protocolTokenPremium) public {
//         Feed(address(protocolTokenOrcl)).set_val(range(protPrice, 1, 10e27));
//         Feed(address(systemCoinOrcl)).set_val(range(coinPrice, 1, 10e27));
//         bidTargetValue = range(_bidTargetValue, 1, 10000000 ether); // 10mm
//         protocolTokenPremium = range(_bidTargetValue, 0, 999); // full acceptable range
//         setDebtAuctionInitialParameters(address(0xdeadbeef));
//     }

//     function range(uint a, uint min, uint max) public pure returns (uint) {
//         if (a <= min) return min;
//         if (a >= max) return max;
//         return a;
//     }

//     // properties
//     function echidna_debt_auction_bid_size() public returns (bool) {
//         return (AccountingEngine(address(accountingEngine)).debtAuctionBidSize() == getNewDebtBid() || lastUpdateTime == 0);
//     }

//     function echidna_debt_auction_bid_size_bound() public returns (bool) {
//         return (AccountingEngine(address(accountingEngine)).debtAuctionBidSize() >= RAY || lastUpdateTime == 0);
//     }

//     function echidna_initial_debt_auction_minted_tokens() public returns (bool) {
//         return (AccountingEngine(address(accountingEngine)).initialDebtAuctionMintedTokens() == getPremiumAdjustedProtocolTokenAmount() || lastUpdateTime == 0);
//     }

//     function echidna_initial_debt_auction_minted_tokens_bound() public returns (bool) {
//         return (AccountingEngine(address(accountingEngine)).initialDebtAuctionMintedTokens() >= minProtocolTokenAmountOffered || lastUpdateTime == 0);
//     }
// }

contract Fuzz is Setup {

}
