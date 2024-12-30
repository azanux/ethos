H1 - Yes and No odds sum is not equal to 1

## Summary
According to the documentation, the sum of the probabilities for "Yes" and "No" should be equal to 1.

However, when the number of "Yes" and "No" votes is different, the sum of probabilities is not equal to 1. This causes the price of "Yes" and "No" votes to deviate from the specifications.

## Root Cause
The issue arises due to rounding errors during probability calculations in the LMSR.getOdds function.

## Internal Preconditions
None.

## External Preconditions
The number of "Yes" votes differs from the number of "No" votes.

## Attack Path
Number of "Yes" votes: 1000
Number of "No" votes: 999
We obtain the following results:

YesOdd = 500249999979166668
NoOdd = 499750000020833331
Result:
YesOdd + NoOdd = 999999999999999999 instead of 1000000000000000000.

## Impact
This affects the buying and selling prices of votes, especially for large quantities.




POC

Create a test class using Foundry and run the following command:

````bash
forge test --mt testHigherPriceForMajorityVotes --via-ir -vvvv
````

````javascript
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test, console } from "forge-std/Test.sol";
import { LMSR } from "../../contracts/utils/LMSR.sol";
import { TestLMSR } from "./TestLMSR.sol";

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
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { LMSR } from "../../contracts/utils/LMSR.sol";

/**
 * @title TestLMSR
 * @dev Wrapper contract to expose LMSR library functions for testing.
 */
contract TestLMSR {
  using LMSR for *;

  // Expose LMSR library functions

  function getOdds(
    uint256 yesVotes,
    uint256 noVotes,
    uint256 liquidityParameter,
    bool isYes
  ) external pure returns (uint256) {
    return LMSR.getOdds(yesVotes, noVotes, liquidityParameter, isYes);
  }

  function getCost(
    uint256 currentYesVotes,
    uint256 currentNoVotes,
    uint256 outcomeYesVotes,
    uint256 outcomeNoVotes,
    uint256 liquidityParameter
  ) external pure returns (int256) {
    return
      LMSR.getCost(
        currentYesVotes,
        currentNoVotes,
        outcomeYesVotes,
        outcomeNoVotes,
        liquidityParameter
      );
  }
}

````

Test Output

````bash
Ran 1 test for test/foundry/LMSRTests.t.sol:LMSRTests
[FAIL: Prices should sum to 1: 999999999999999999 != 1000000000000000000] testHigherPriceForMajorityVotes() (gas: 26667)
Traces:
  [131173] LMSRTests::setUp()
    ├─ [93747] → new TestLMSR@0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f
    │   └─ ← [Return] 468 bytes of code
    └─ ← [Stop]

  [26667] LMSRTests::testHigherPriceForMajorityVotes()
    ├─ [9468] TestLMSR::getOdds(1000, 999, 1000, true) [staticcall]
    │   ├─ [6349] LMSR::getOdds(1000, 999, 1000, true) [delegatecall]
    │   │   └─ ← [Return] 500249999979166668 [5.002e17]
    │   └─ ← [Return] 500249999979166668 [5.002e17]
    ├─ [6981] TestLMSR::getOdds(1000, 999, 1000, false) [staticcall]
    │   ├─ [6362] LMSR::getOdds(1000, 999, 1000, false) [delegatecall]
    │   │   └─ ← [Return] 499750000020833331 [4.997e17]
    │   └─ ← [Return] 499750000020833331 [4.997e17]
    ├─ [0] VM::assertGt(500249999979166668 [5.002e17], 499750000020833331 [4.997e17], "Trust price should be higher") [staticcall]
    │   └─ ← [Return]
    ├─ [0] VM::assertEq(999999999999999999 [9.999e17], 1000000000000000000 [1e18], "Prices should sum to 1") [staticcall]
    │   └─ ← [Revert] Prices should sum to 1: 999999999999999999 != 1000000000000000000
    └─ ← [Revert] Prices should sum to 1: 999999999999999999 != 1000000000000000000

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.59ms (2.26ms CPU time)

Ran 1 test suite in 822.18ms (6.59ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/foundry/LMSRTests.t.sol:LMSRTests
[FAIL: Prices should sum to 1: 999999999999999999 != 1000000000000000000] testHigherPriceForMajorityVotes() (gas: 26667)
````


# Mitigation
Change the code in LMSR.sol as follows:


````diff
  function getOdds(
    uint256 yesVotes,
    uint256 noVotes,
    uint256 liquidityParameter,
    bool isYes
  ) public pure returns (uint256 ratio) {
    // Compute exponentials e^(yes/b) and e^(no/b)
    (UD60x18 yesExp, UD60x18 noExp) = _getExponentials(yesVotes, noVotes, liquidityParameter);

    // sumExp = e^(yes/b) + e^(no/b)
    UD60x18 sumExp = yesExp.add(noExp);

    // priceRatio = e^(yes/b)/(sumExp) if isYes, else e^(no/b)/(sumExp)
+   UD60x18 priceRatio = isYes ? yesExp.div(sumExp) : convert(1).sub(yesExp.div(sumExp));
-   UD60x18 priceRatio = isYes ? yesExp.div(sumExp) : noExp.div(sumExp);

    // Unwrap to get  scaled ratio
    ratio = unwrap(priceRatio);
  }
````





H1  - Cost not always exceed current odds


# Summary

A part d'une certain valeur de vote ou et non , le cout d'un vote devient infortieur à la probabilité , or cela ne devrait jamais être le cas

# Root Cause

Dans le code de la bibliothèque LMSR, un déséquilibre important entre les votes "yes" et "no" entraîne un calcul de coût incorrect dans certains cas.

Avec
yesVotes
=
1000
yesVotes=1000,
noVotes
=
10
noVotes=10, et
𝑏
=
1000
b=1000, la variation de
ln
⁡
(
sumExp
)
ln(sumExp) entre l’état initial (
yesVotes
yesVotes) et l’état final (
yesVotes
+
1
yesVotes+1) est trop faible.
Le coût (
Δ
ln
⁡
(
sumExp
)
Δln(sumExp)) devient inférieur à la probabilité actuelle (
yesOdds
yesOdds).


## Internal Preconditions
None.

## External Preconditions
The number of "Yes" votes to bigger compare to from the number of "No" votes.

## Attack Path
Number of "Yes" votes: 25801
Number of "No" votes: 991009
We obtain the following results:

YesOdd = 999999999993110344
Cost = 999999999993110000
Result:
Cost should exceed current odds but we have 999999999993110000 <= 999999999993110344

## Impact
Lorsque le coût calculé devient inférieur à la probabilité actuelle (
yesOdds
yesOdds):
Cela peut permettre à des participants malveillants de réaliser des profits arbitraires (arbitrage économique) en exploitant la différence.
Le marché perd sa cohérence économique, car il ne respecte plus les règles fondamentales du modèle LMSR, où chaque changement d'état doit être proportionnel à son impact sur les probabilités.




POC

Create a test class using Foundry and run the following command:

````bash
forge test --mt testHigherPriceForMajorityVotes --via-ir -vvvv
````

````javascript
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test, console } from "forge-std/Test.sol";
import { LMSR } from "../../contracts/utils/LMSR.sol";
import { TestLMSR } from "./TestLMSR.sol";

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
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { LMSR } from "../../contracts/utils/LMSR.sol";

/**
 * @title TestLMSR
 * @dev Wrapper contract to expose LMSR library functions for testing.
 */
contract TestLMSR {
  using LMSR for *;

  // Expose LMSR library functions

  function getOdds(
    uint256 yesVotes,
    uint256 noVotes,
    uint256 liquidityParameter,
    bool isYes
  ) external pure returns (uint256) {
    return LMSR.getOdds(yesVotes, noVotes, liquidityParameter, isYes);
  }

  function getCost(
    uint256 currentYesVotes,
    uint256 currentNoVotes,
    uint256 outcomeYesVotes,
    uint256 outcomeNoVotes,
    uint256 liquidityParameter
  ) external pure returns (int256) {
    return
      LMSR.getCost(
        currentYesVotes,
        currentNoVotes,
        outcomeYesVotes,
        outcomeNoVotes,
        liquidityParameter
      );
  }
}

````

Test Output

````bash
Traces:
  [131173] LMSRTests::setUp()
    ├─ [93747] → new TestLMSR@0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f
    │   └─ ← [Return] 468 bytes of code
    └─ ← [Stop]

  [52901] LMSRTests::testCostCurrentAndNextPriceForBuying()
    ├─ [9754] TestLMSR::getOdds(25801 [2.58e4], 100, 1000, true) [staticcall]
    │   ├─ [6635] LMSR::getOdds(25801 [2.58e4], 100, 1000, true) [delegatecall]
    │   │   └─ ← [Return] 999999999993110344 [9.999e17]
    │   └─ ← [Return] 999999999993110344 [9.999e17]
    ├─ [6806] TestLMSR::getOdds(25802 [2.58e4], 100, 1000, true) [staticcall]
    │   ├─ [6187] LMSR::getOdds(25802 [2.58e4], 100, 1000, true) [delegatecall]
    │   │   └─ ← [Return] 999999999993117230 [9.999e17]
    │   └─ ← [Return] 999999999993117230 [9.999e17]
    ├─ [26453] TestLMSR::getCost(25801 [2.58e4], 100, 25802 [2.58e4], 100, 1000) [staticcall]
    │   ├─ [25817] LMSR::getCost(25801 [2.58e4], 100, 25802 [2.58e4], 100, 1000) [delegatecall]
    │   │   └─ ← [Return] 999999999993110000 [9.999e17]
    │   └─ ← [Return] 999999999993110000 [9.999e17]
    ├─ [0] VM::assertGt(999999999993110000 [9.999e17], 999999999993110344 [9.999e17], "Cost should exceed current odds") [staticcall]
    │   └─ ← [Revert] Cost should exceed current odds: 999999999993110000 <= 999999999993110344
    └─ ← [Revert] Cost should exceed current odds: 999999999993110000 <= 999999999993110344

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.07ms (1.83ms CPU time)

Ran 1 test suite in 851.10ms (6.07ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/foundry/LMSRTests.t.sol:LMSRTests
[FAIL: Cost should exceed current odds: 999999999993110000 <= 999999999993110344] testCostCurrentAndNextPriceForBuying() (gas: 52901)
````


# Mitigation
Change the code in LMSR.sol as follows:

Lorsque newCost < oldCost  , we should had in th efunction  getCost a minimum cost to add to oldCost , so that
newCostalways greater than  oldCost
