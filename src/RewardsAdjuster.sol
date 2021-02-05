pragma solidity 0.6.7;

abstract contract StabilityFeeTreasuryLike {
    function getAllowance(address) virtual public view returns (uint256, uint256);
    function setPerBlockAllowance(address, uint256) external;
}
abstract contract TreasuryFundableLike {
    
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

    // --- Variables ---
    mapping(address => )

    // --- Events ---
    event AddAuthorization(address account);
    event RemoveAuthorization(address account);
}
