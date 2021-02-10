pragma solidity 0.6.7;

abstract contract StabilityFeeTreasuryLike {
    function getAllowance(address) virtual public view returns (uint256, uint256);
    function setPerBlockAllowance(address, uint256) virtual external;
}
abstract contract TreasuryFundableLike {
    function authorizedAccounts(address) virtual public view returns (uint256);
    function baseUpdateCallerReward() virtual public view returns (uint256);
    function maxUpdateCallerReward() virtual public view returns (uint256);
    function modifyParameters(bytes32, uint256) virtual external;
}
abstract contract TreasuryParamAdjusterLike {
    function adjustMaxReward(address receiver, bytes4 targetFunctionSignature, uint256 newMaxReward) virtual external;
}
abstract contract OracleLike {
    function read() virtual external view returns (uint256);
}
abstract contract OracleRelayerLike {
    function redemptionPrice() virtual public returns (uint256);
}

contract RewardsAdjuster {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    function addAuthorization(address account) virtual external isAuthorized {
        authorizedAccounts[account] = 1;
        emit AddAuthorization(account);
    }
    function removeAuthorization(address account) virtual external isAuthorized {
        authorizedAccounts[account] = 0;
        emit RemoveAuthorization(account);
    }
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "RewardsAdjuster/account-not-authorized");
        _;
    }

    // --- Structs ---
    struct FundingReceiver {
        uint256 lastUpdateTime;           // [unix timestamp]
        uint256 gasAmountForExecution;    // [gas amount]
        uint256 updateDelay;              // [seconds]
        uint256 baseRewardMultiplier;     // [hundred]
        uint256 maxRewardMultiplier;      // [hundred]
    }

    // --- Variables ---
    mapping(address => mapping(bytes4 => FundingReceiver)) public fundingReceivers;

    OracleLike                public gasPriceOracle;
    OracleLike                public ethPriceOracle;
    TreasuryParamAdjusterLike public treasuryParamAdjuster;
    OracleRelayerLike         public oracleRelayer;
    StabilityFeeTreasuryLike  public treasury;

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, address addr);
    event ModifyParameters(address targetContract, bytes4 targetFunction, bytes32 parameter, uint256 val);
    event AddFundingReceiver(
        address indexed receiver,
        bytes4  targetFunctionSignature,
        uint256 updateDelay,
        uint256 gasAmountForExecution,
        uint256 baseRewardMultiplier,
        uint256 maxRewardMultiplier
    );
    event RemoveFundingReceiver(address indexed receiver, bytes4 targetFunctionSignature);
    event RecomputedRewards(address receiver, uint256 newBaseReward, uint256 newMaxReward);

    constructor(
        address oracleRelayer_,
        address treasury_,
        address gasPriceOracle_,
        address ethPriceOracle_,
        address treasuryParamAdjuster_
    ) public {
        // Checks
        require(oracleRelayer_ != address(0), "RewardsAdjuster/null-oracle-relayer");
        require(treasury_ != address(0), "RewardsAdjuster/null-treasury");
        require(gasPriceOracle_ != address(0), "RewardsAdjuster/null-gas-oracle");
        require(ethPriceOracle_ != address(0), "RewardsAdjuster/null-eth-oracle");
        require(treasuryParamAdjuster_ != address(0), "RewardsAdjuster/null-treasury-adjuster");

        // Store
        oracleRelayer         = OracleRelayerLike(oracleRelayer_);
        treasury              = StabilityFeeTreasuryLike(treasury_);
        gasPriceOracle        = OracleLike(gasPriceOracle_);
        ethPriceOracle        = OracleLike(ethPriceOracle_);
        treasuryParamAdjuster = TreasuryParamAdjusterLike(treasuryParamAdjuster_);

        // Check that the oracle relayer has a redemption price stored
        oracleRelayer.redemptionPrice();

        // Emit events
        emit ModifyParameters("treasury", treasury_);
        emit ModifyParameters("oracleRelayer", oracleRelayer_);
        emit ModifyParameters("gasPriceOracle", gasPriceOracle_);
        emit ModifyParameters("ethPriceOracle", ethPriceOracle_);
        emit ModifyParameters("treasuryParamAdjuster", treasuryParamAdjuster_);
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Math ---
    uint256 public constant WAD            = 10**18;
    uint256 public constant RAY            = 10**27;
    uint256 public constant HUNDRED        = 100;
    uint256 public constant THOUSAND       = 1000;

    function addition(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "RewardsAdjuster/add-uint-uint-overflow");
    }
    function subtract(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "RewardsAdjuster/sub-uint-uint-underflow");
    }
    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "RewardsAdjuster/multiply-uint-uint-overflow");
    }
    function divide(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "RewardsAdjuster/div-y-null");
        z = x / y;
        require(z <= x, "RewardsAdjuster/div-invalid");
    }
    function wdivide(uint x, uint y) public pure returns (uint z) {
        require(y > 0, "RewardsAdjuster/div-y-null");
        z = multiply(x, WAD) / y;
    }

    // --- Administration ---
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "RewardsAdjuster/null-address");
        if (parameter == "oracleRelayer") {
            oracleRelayer = OracleRelayerLike(addr);
            oracleRelayer.redemptionPrice();
        }
        else if (parameter == "treasury") {
            treasury = StabilityFeeTreasuryLike(addr);
        }
        else if (parameter == "gasPriceOracle") {
            gasPriceOracle = OracleLike(addr);
        }
        else if (parameter == "ethPriceOracle") {
            ethPriceOracle = OracleLike(addr);
        }
        else if (parameter == "treasuryParamAdjuster") {
            treasuryParamAdjuster = TreasuryParamAdjusterLike(addr);
        }
        else revert("RewardsAdjuster/modify-unrecognized-params");
        emit ModifyParameters(parameter, addr);
    }
    function modifyParameters(address targetContract, bytes4 targetFunction, bytes32 parameter, uint256 val) external isAuthorized {
        require(val > 0, "RewardsAdjuster/null-value");
        FundingReceiver storage fundingReceiver = fundingReceivers[targetContract][targetFunction];
        require(fundingReceiver.lastUpdateTime > 0, "RewardsAdjuster/non-existent-receiver");

        if (parameter == "gasAmountForExecution") {
            fundingReceiver.gasAmountForExecution = val;
        }
        else if (parameter == "updateDelay") {
            fundingReceiver.updateDelay = val;
        }
        else if (parameter == "baseRewardMultiplier") {
            require(both(val > 0, val <= THOUSAND), "RewardsAdjuster/invalid-base-reward-multiplier");
            fundingReceiver.baseRewardMultiplier = val;
        }
        else if (parameter == "maxRewardMultiplier") {
            require(both(val >= HUNDRED, val <= THOUSAND), "RewardsAdjuster/invalid-max-reward-multiplier");
            fundingReceiver.maxRewardMultiplier = val;
        }
        else revert("RewardsAdjuster/modify-unrecognized-params");
        emit ModifyParameters(targetContract, targetFunction, parameter, val);
    }

    function addFundingReceiver(
        address receiver,
        bytes4  targetFunctionSignature,
        uint256 updateDelay,
        uint256 gasAmountForExecution,
        uint256 baseRewardMultiplier,
        uint256 maxRewardMultiplier
    ) external isAuthorized {
        // Checks
        require(receiver != address(0), "RewardsAdjuster/null-receiver");
        require(updateDelay > 0, "RewardsAdjuster/null-update-delay");
        require(both(baseRewardMultiplier > 0, baseRewardMultiplier <= THOUSAND), "RewardsAdjuster/invalid-base-reward-multiplier");
        require(both(maxRewardMultiplier >= HUNDRED, maxRewardMultiplier <= THOUSAND), "RewardsAdjuster/invalid-max-reward-multiplier");
        require(gasAmountForExecution > 0, "RewardsAdjuster/null-gas-amount");

        // Check that the receiver hasn't been already added
        FundingReceiver storage newReceiver = fundingReceivers[receiver][targetFunctionSignature];
        require(newReceiver.lastUpdateTime == 0, "RewardsAdjuster/receiver-already-added");

        // Add the receiver's data
        newReceiver.lastUpdateTime        = now;
        newReceiver.updateDelay           = updateDelay;
        newReceiver.gasAmountForExecution = gasAmountForExecution;
        newReceiver.baseRewardMultiplier  = baseRewardMultiplier;
        newReceiver.maxRewardMultiplier   = maxRewardMultiplier;

        emit AddFundingReceiver(
          receiver,
          targetFunctionSignature,
          updateDelay,
          gasAmountForExecution,
          baseRewardMultiplier,
          maxRewardMultiplier
        );
    }
    function removeFundingReceiver(address receiver, bytes4 targetFunctionSignature) external isAuthorized {
        // Check that the receiver is still stored and then delete it
        require(fundingReceivers[receiver][targetFunctionSignature].lastUpdateTime > 0, "RewardsAdjuster/non-existent-receiver");
        delete(fundingReceivers[receiver][targetFunctionSignature]);
        emit RemoveFundingReceiver(receiver, targetFunctionSignature);
    }

    // --- Core Logic ---
    function recomputeRewards(address receiver, bytes4 targetFunctionSignature) external {
        FundingReceiver storage targetReceiver = fundingReceivers[receiver][targetFunctionSignature];
        require(both(targetReceiver.lastUpdateTime > 0, addition(targetReceiver.lastUpdateTime, targetReceiver.updateDelay) <= now), "RewardsAdjuster/wait-more");

        // Update last time
        targetReceiver.lastUpdateTime = now;

        // Read the gas and the ETH prices
        uint256 gasPrice = gasPriceOracle.read();
        uint256 ethPrice = ethPriceOracle.read();

        // Calculate the base fiat value in RAY
        uint256 baseRewardFiatValue = multiply(multiply(gasPrice, targetReceiver.gasAmountForExecution), ethPrice);

        // Calculate the base reward expressed in system coins
        uint256 newBaseReward = divide(multiply(baseRewardFiatValue, RAY), oracleRelayer.redemptionPrice());
        newBaseReward         = divide(multiply(newBaseReward, targetReceiver.baseRewardMultiplier), THOUSAND);

        // Compute the new max reward and check both rewards
        uint256 newMaxReward = divide(multiply(newBaseReward, targetReceiver.maxRewardMultiplier), THOUSAND);
        require(both(newBaseReward > 0, newMaxReward > 0), "RewardsAdjuster/null-new-rewards");

        // Notify the treasury param adjuster about the new max reward
        newMaxReward = multiply(newMaxReward, RAY);
        treasuryParamAdjuster.adjustMaxReward(receiver, targetFunctionSignature, newMaxReward);

        // Approve the max reward in the treasury
        treasury.setPerBlockAllowance(receiver, multiply(newMaxReward, RAY));

        // Set the new rewards inside the receiver contract
        TreasuryFundableLike(receiver).modifyParameters("maxUpdateCallerReward", newMaxReward);
        TreasuryFundableLike(receiver).modifyParameters("baseUpdateCallerReward", newBaseReward);

        emit RecomputedRewards(receiver, newBaseReward, newMaxReward);
    }
}
