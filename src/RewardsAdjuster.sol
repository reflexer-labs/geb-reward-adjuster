pragma solidity 0.6.7;

abstract contract StabilityFeeTreasuryLike {
    function getAllowance(address) virtual public view returns (uint256, uint256);
    function setPerBlockAllowance(address, uint256) virtual external;
}
abstract contract TreasuryFundableLike {
    function authorizedAccounts(address) virtual public view returns (uint256);
    function baseUpdateCallerReward() virtual public view returns (uint256);
    function modifyParameters(bytes32, uint256) virtual external;
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
        uint256 lastUpdateTime;             // [unix timestamp]
        uint256 updateDelay;                // [seconds]
        uint256 baseRewardFiatTargetValue;  // [ray]
        uint256 maxRewardMultiplier;        // [hundred]
    }

    // --- Variables ---
    mapping(address => FundingReceiver) public fundingReceivers;

    OracleRelayerLike        public oracleRelayer;
    StabilityFeeTreasuryLike public treasury;

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
    event ModifyParameters(bytes32 parameter, address addr);
    event AddFundingReceiver(
        address indexed receiver,
        uint256 updateDelay,
        uint256 baseRewardFiatTargetValue,
        uint256 maxRewardMultiplier
    );
    event RemoveFundingReceiver(address indexed receiver);
    event RecomputedRewards(address receiver, uint256 newBaseReward, uint256 newMaxReward);

    constructor(
        address oracleRelayer_,
        address treasury_
    ) public {
        // Checks
        require(oracleRelayer_ != address(0), "RewardsAdjuster/null-oracle-relayer");
        require(treasury_ != address(0), "RewardsAdjuster/null-treasury");

        // Store
        oracleRelayer = OracleRelayerLike(oracleRelayer_);
        treasury      = StabilityFeeTreasuryLike(treasury_);

        // Check that the oracle relayer has a redemption price stored
        oracleRelayer.redemptionPrice();

        // Emit events
        emit ModifyParameters("treasury", treasury_);
        emit ModifyParameters("oracleRelayer", oracleRelayer_);
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Math ---
    uint256 public constant WAD      = 10**18;
    uint256 public constant RAY      = 10**27;
    uint256 public constant HUNDRED  = 100;
    uint256 public constant THOUSAND = 1000;

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
        else revert("RewardsAdjuster/modify-unrecognized-params");
        emit ModifyParameters(parameter, addr);
    }

    function addFundingReceiver(
        address receiver,
        uint256 updateDelay,
        uint256 baseRewardFiatTargetValue,
        uint256 maxRewardMultiplier
    ) external isAuthorized {
        // Checks
        require(receiver != address(0), "RewardsAdjuster/null-receiver");
        require(updateDelay > 0, "RewardsAdjuster/null-update-delay");
        require(baseRewardFiatTargetValue > 0, "RewardsAdjuster/null-base-reward-target-value");
        require(both(maxRewardMultiplier >= HUNDRED, maxRewardMultiplier <= THOUSAND), "RewardsAdjuster/invalid-max-reward-multiplier");

        // Check that the receiver hasn't been already added
        FundingReceiver storage newReceiver = fundingReceivers[receiver];
        require(newReceiver.lastUpdateTime == 0, "RewardsAdjuster/receiver-already-added");

        // Add the receiver's data
        newReceiver.lastUpdateTime            = now;
        newReceiver.updateDelay               = updateDelay;
        newReceiver.baseRewardFiatTargetValue = baseRewardFiatTargetValue;
        newReceiver.maxRewardMultiplier       = maxRewardMultiplier;

        emit AddFundingReceiver(
          receiver,
          updateDelay,
          baseRewardFiatTargetValue,
          maxRewardMultiplier
        );
    }
    function removeFundingReceiver(address receiver) external isAuthorized {
        // Check that the receiver is still stored and then delete it
        require(fundingReceivers[receiver].lastUpdateTime > 0, "RewardsAdjuster/non-existent-receiver");
        delete(fundingReceivers[receiver]);
        emit RemoveFundingReceiver(receiver);
    }

    // --- Core Logic ---
    function recomputeRewards(address receiver) external {
        FundingReceiver storage targetReceiver = fundingReceivers[receiver];
        require(both(targetReceiver.lastUpdateTime > 0, addition(targetReceiver.lastUpdateTime, targetReceiver.updateDelay) <= now), "RewardsAdjuster/wait-more");

        // Update last time
        targetReceiver.lastUpdateTime = now;

        // Compute the new base & max rewards
        uint256 newBaseReward = wdivide(targetReceiver.baseRewardFiatTargetValue, oracleRelayer.redemptionPrice());
        uint256 newMaxReward  = divide(multiply(newBaseReward, targetReceiver.maxRewardMultiplier), THOUSAND);
        require(both(newBaseReward > 0, newMaxReward > 0), "RewardsAdjuster/null-new-rewards");

        // Approve the max reward in the treasury
        treasury.setPerBlockAllowance(receiver, multiply(newMaxReward, RAY));

        // Set the new rewards inside the receiver contract
        TreasuryFundableLike(receiver).modifyParameters("maxUpdateCallerReward", newMaxReward);
        TreasuryFundableLike(receiver).modifyParameters("baseUpdateCallerReward", newBaseReward);

        emit RecomputedRewards(receiver, newBaseReward, newMaxReward);
    }
}
