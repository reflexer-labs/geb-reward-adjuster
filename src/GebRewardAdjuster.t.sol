pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./GebRewardAdjuster.sol";

contract GebRewardAdjusterTest is DSTest {
    GebRewardAdjuster adjuster;

    function setUp() public {
        adjuster = new GebRewardAdjuster();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
