// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {LMSR} from "../../contracts/utils/LMSR.sol";
import {TestLMSR} from "./TestLMSR.sol";

/**
 * @title LMSRTests
 * @dev Test contract for the LMSR library using Foundry's testing framework.
 */
contract LMSRTests is Test {
    TestLMSR private lmsr;

    // Constants for testing
    uint256 private constant LIQUIDITY_PARAMETER = 1000; // Liquidity parameter for stable price calculations
    uint256 private constant QUOTIENT = 1e18; // Scaling factor for fixed-point arithmetic

    // Setup function to initialize the LMSR library
    function setUp() public {
        // Deploy LMSR library
        lmsr = new TestLMSR();
    }

    /**
     * @notice Test that initial prices are calculated correctly when votes are equal.
     * @dev Verifies that the trust and distrust prices are identical and 50% of the total.
     */
    function testInitialPricesWithEqualVotes() public {
        uint256 votes = 1000; // Number of votes for both "yes" and "no"

        // Compute prices using LMSR library
        uint256 trustPrice = lmsr.getOdds(votes, votes, LIQUIDITY_PARAMETER, true);
        uint256 distrustPrice = lmsr.getOdds(votes, votes, LIQUIDITY_PARAMETER, false);

        // Check that the prices are equal and half the maximum price
        assertEq(trustPrice, distrustPrice, "Prices should be equal for equal votes");
        assertEq(trustPrice, QUOTIENT / 2, "Price should be half of the maximum");
        assertEq(trustPrice + distrustPrice, QUOTIENT, "Prices should sum to 1");
    }

    function test_FuzzInitialPricesWithEqualVotes(uint256 val) public {
        if (val > 13000) {
            return;
        }
        uint256 votes = val; // Number of votes for both "yes" and "no"

        // Compute prices using LMSR library
        uint256 trustPrice = lmsr.getOdds(votes, votes, LIQUIDITY_PARAMETER, true);
        uint256 distrustPrice = lmsr.getOdds(votes, votes, LIQUIDITY_PARAMETER, false);

        // Check that the prices are equal and half the maximum price
        assertEq(trustPrice, distrustPrice, "Prices should be equal for equal votes");
        assertEq(trustPrice, QUOTIENT / 2, "Price should be half of the maximum");
        assertEq(trustPrice + distrustPrice, QUOTIENT, "Prices should sum to 1");
    }

    /**
     * @notice Test that the price for the majority side is higher.
     * @dev Ensures that the odds calculation reflects the higher price for "yes" votes.
     */
    function testHigherPriceForMajorityVotes() public {
        uint256 yesVotes = 1000; // "Yes" votes exceed "No" votes
        uint256 noVotes = 999; // "No" votes

        // Compute prices using LMSR library
        uint256 trustPrice = lmsr.getOdds(yesVotes, noVotes, LIQUIDITY_PARAMETER, true);
        uint256 distrustPrice = lmsr.getOdds(yesVotes, noVotes, LIQUIDITY_PARAMETER, false);

        // Check that the "yes" side price is higher
        assertGt(trustPrice, distrustPrice, "Trust price should be higher");
        assertEq(trustPrice + distrustPrice, QUOTIENT, "Prices should sum to 1");
    }

    /**
     * @notice Test that the price for the majority side is higher.
     * @dev Ensures that the odds calculation reflects the higher price for "yes" votes.
     */
    function testFuzzHigherPriceForMajorityVotes(uint256 yes, uint256 no) public {
        if (yes <= no || yes > 13000) {
            return;
        }
        uint256 yesVotes = yes; // "Yes" votes exceed "No" votes
        uint256 noVotes = no; // "No" votes

        // Compute prices using LMSR library
        uint256 trustPrice = lmsr.getOdds(yesVotes, noVotes, LIQUIDITY_PARAMETER, true);
        uint256 distrustPrice = lmsr.getOdds(yesVotes, noVotes, LIQUIDITY_PARAMETER, false);

        // Check that the "yes" side price is higher
        assertGt(trustPrice, distrustPrice, "Trust price should be higher");
        //assertEq(trustPrice + distrustPrice, QUOTIENT, "Prices should sum to 1");
    }

    /**
     * @notice Test that prices stay within valid bounds.
     * @dev Verifies that prices are between 0 and the maximum scaling factor.
     */
    function testPriceBounds() public {
        uint256 largeVotes = 10000; // Large number of "yes" votes
        uint256 smallVotes = 1; // Small number of "no" votes

        // Compute prices using LMSR library
        uint256 highPrice = lmsr.getOdds(largeVotes, smallVotes, LIQUIDITY_PARAMETER, true);
        uint256 lowPrice = lmsr.getOdds(largeVotes, smallVotes, LIQUIDITY_PARAMETER, false);

        // Ensure prices are within bounds
        assertLe(highPrice, QUOTIENT, "Price cannot exceed the maximum");
        assertGt(lowPrice, 0, "Price must be greater than zero");
    }

    /**
     * @notice Test that prices increase incrementally with votes.
     * @dev Ensures that adding more votes results in higher prices.
     */
    function testIncrementalPriceIncrease() public {
        uint256 liquidity = 10000; // High liquidity parameter for testing
        uint256 previousPrice;

        // Iterate over vote counts and check price progression
        for (uint256 i = 1; i < 5000; i += 500) {
            uint256 newPrice = lmsr.getOdds(i, 0, liquidity, true);
            if (i > 1) {
                assertGt(newPrice, previousPrice, "Price should increase as votes increase");
            }
            previousPrice = newPrice;
        }
    }

    /**
     * @notice Test that the cost of zero vote change is zero.
     * @dev Verifies that no change in state results in no cost.
     */
    function testCostOfZeroVotes() public {
        uint256 votes = 0; // No votes

        // Compute cost of no vote change
        int256 cost = lmsr.getCost(votes, votes, votes, votes, LIQUIDITY_PARAMETER);

        // Ensure cost is zero
        assertEq(cost, 0, "Cost of zero votes should be zero");
    }

    /**
     * @notice Test that buying votes has a positive cost.
     * @dev Ensures that adding votes incurs a non-zero cost.
     */
    function testPositiveCostForBuyingVotes() public {
        uint256 currentVotes = 1000; // Initial vote count
        uint256 votesToBuy = 10; // Votes to add

        // Compute cost for adding votes
        int256 cost =
            lmsr.getCost(currentVotes, currentVotes, currentVotes + votesToBuy, currentVotes, LIQUIDITY_PARAMETER);

        // Ensure cost is positive
        assertGt(cost, 0, "Cost should be greater than zero");
    }

    /**
     * @notice Test that buying votes has a positive cost.
     * @dev Ensures that adding votes incurs a non-zero cost.
     */
    function testNegativeCostForSelliningVotes() public {
        uint256 currentVotes = 1000; // Initial vote count
        uint256 votesToSell = 10; // Votes to add

        // Compute cost for adding votes
        int256 cost = lmsr.getCost(
            currentVotes, currentVotes, currentVotes - votesToSell, currentVotes - votesToSell, LIQUIDITY_PARAMETER
        );

        // Ensure cost is positive
        assertLt(cost, 0, "Cost should be greater than zero");
    }

    /**
     * @notice Test that influencing the majority side is more expensive.
     * @dev Verifies that adding votes to the majority side incurs higher costs.
     */
    function testHigherCostForMajorityVotes() public {
        uint256 majorityVotes = 2000; // Votes on majority side
        uint256 minorityVotes = 1500; // Votes on minority side
        uint256 addAmount = 10; // Votes to add

        // Compute costs for both sides
        int256 costToMajority =
            lmsr.getCost(majorityVotes, minorityVotes, majorityVotes + addAmount, minorityVotes, LIQUIDITY_PARAMETER);

        int256 costToMinority =
            lmsr.getCost(majorityVotes, minorityVotes, majorityVotes, minorityVotes + addAmount, LIQUIDITY_PARAMETER);

        // Ensure the majority side is more expensive
        assertGt(costToMajority, costToMinority, "Majority votes should cost more");
    }

    /**
     * @notice Test that adding and removing votes conserves funds.
     * @dev Ensures that the net cost of adding and removing votes is zero.
     */
    function testConservationOfFunds() public {
        uint256 initialVotes = 1000; // Starting vote count
        uint256 votesToAdd = 100; // Votes to add

        // Compute costs for adding and removing votes
        int256 costToAdd =
            lmsr.getCost(initialVotes, initialVotes, initialVotes + votesToAdd, initialVotes, LIQUIDITY_PARAMETER);
        int256 costToRemove =
            lmsr.getCost(initialVotes + votesToAdd, initialVotes, initialVotes, initialVotes, LIQUIDITY_PARAMETER);

        // Ensure net cost is zero
        assertEq(costToAdd + costToRemove, 0, "Funds should be conserved");
    }

    /**
     * @notice Test that the `getOdds` function handles zero votes gracefully.
     */
    function testHandleZeroVotesGracefully() public {
        uint256 yesVotes = 0;
        uint256 noVotes = 1000;

        // Calculate odds for both sides
        uint256 yesOdds = lmsr.getOdds(yesVotes, noVotes, LIQUIDITY_PARAMETER, true);
        uint256 noOdds = lmsr.getOdds(yesVotes, noVotes, LIQUIDITY_PARAMETER, false);

        // Assert that no errors occur and values are within range
        assertLe(yesOdds, QUOTIENT, "Yes odds should not exceed maximum");
        assertGt(noOdds, 0, "No odds should be greater than zero");
    }

    /**
     * @notice Test that the `getOdds` function handles very large vote numbers.
     */
    function testHandleLargeVoteNumbers() public {
        uint256 maxSafeVotes = 133000 - 1;

        // Calculate odds for a large number of votes
        uint256 yesOdds = lmsr.getOdds(maxSafeVotes, 1, LIQUIDITY_PARAMETER, true);
        uint256 noOdds = lmsr.getOdds(maxSafeVotes, 1, LIQUIDITY_PARAMETER, false);

        // Assert that values are within range
        assertLe(yesOdds, QUOTIENT, "Yes odds should not exceed maximum");
        assertGt(noOdds, 0, "No odds should be greater than zero");
    }

    /**
     * @notice Test the impact of the liquidity parameter on price sensitivity.
     */
    function testLiquidityParameterImpact() public {
        uint256 yesVotes = 2000;
        uint256 noVotes = 1000;

        // Calculate odds with different liquidity parameters
        uint256 lessLiquidOdds = lmsr.getOdds(yesVotes, noVotes, LIQUIDITY_PARAMETER, true);
        uint256 moreLiquidOdds = lmsr.getOdds(yesVotes, noVotes, LIQUIDITY_PARAMETER * 2, true);

        // Assert that higher liquidity reduces price sensitivity
        assertLt(moreLiquidOdds, lessLiquidOdds, "Higher liquidity should reduce sensitivity");
    }

    /**
     * @notice Test the impact of the liquidity parameter on price sensitivity.
     */
    function testLiquidityParameterImpact(uint256 param) public {
        uint256 yesVotes = 2000;
        uint256 noVotes = 1000;

        // Calculate odds with different liquidity parameters
        uint256 lessLiquidOdds = lmsr.getOdds(yesVotes, noVotes, param, true);
        uint256 moreLiquidOdds = lmsr.getOdds(yesVotes, noVotes, param * 2, true);

        // Assert that higher liquidity reduces price sensitivity
        assertLt(moreLiquidOdds, lessLiquidOdds, "Higher liquidity should reduce sensitivity");
    }

    /**
     * @notice Test the cost calculation between current and next price for buying votes.
     */
    function testCostBetweenCurrentAndNextPriceForBuying() public {
        for (uint256 yes = 1; yes < 132000; yes += 100) {
            for (uint256 no = 0; no < 1000; no += 100) {
                uint256 yesOdds = lmsr.getOdds(yes, no, LIQUIDITY_PARAMETER, true);
                uint256 nextYesOdds = lmsr.getOdds(yes + 1, no, LIQUIDITY_PARAMETER, true);
                int256 yesCost = lmsr.getCost(yes, no, yes + 1, no, LIQUIDITY_PARAMETER);
                assertGt(yesCost, int256(yesOdds), "Cost should exceed current odds");
                assertLt(yesCost, int256(nextYesOdds), "Cost should be below next odds");
            }
        }
    }

    /**
     * @notice Test the cost calculation between current and next price for buying votes.
     */
    function testCostCurrentAndNextPriceForBuying() public {
        uint256 yes = 25801;
        uint256 no = 100;

        uint256 yesOdds = lmsr.getOdds(yes, no, LIQUIDITY_PARAMETER, true);
        uint256 nextYesOdds = lmsr.getOdds(yes + 1, no, LIQUIDITY_PARAMETER, true);
        int256 yesCost = lmsr.getCost(yes, no, yes + 1, no, LIQUIDITY_PARAMETER);
        assertGt(yesCost, int256(yesOdds), "Cost should exceed current odds");
        assertLt(yesCost, int256(nextYesOdds), "Cost should be below next odds");
    }

    /**
     * @notice Test the cost calculation between current and next price for selling votes.
     */
    function testCostBetweenCurrentAndNextPriceForSelling() public {
        for (uint256 yes = 1; yes < 1000; yes += 100) {
            for (uint256 no = 1; no < 1000; no += 100) {
                uint256 yesOdds = lmsr.getOdds(yes, no, LIQUIDITY_PARAMETER, true);
                uint256 nextYesOdds = lmsr.getOdds(yes - 1, no, LIQUIDITY_PARAMETER, true);
                int256 yesCost = lmsr.getCost(yes, no, yes - 1, no, LIQUIDITY_PARAMETER);
                assertLt(yesCost, -int256(yesOdds), "Cost should be less than negative current odds");
                assertGt(yesCost, -int256(nextYesOdds), "Cost should be greater than negative next odds");
            }
        }
    }
}
