// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LMSR} from "../../contracts/utils/LMSR.sol";

/**
 * @title TestLMSR
 * @dev Wrapper contract to expose LMSR library functions for testing.
 */
contract TestLMSR {
    using LMSR for *;

    // Expose LMSR library functions

    function getOdds(uint256 yesVotes, uint256 noVotes, uint256 liquidityParameter, bool isYes)
        external
        pure
        returns (uint256)
    {
        return LMSR.getOdds(yesVotes, noVotes, liquidityParameter, isYes);
    }

    function getCost(
        uint256 currentYesVotes,
        uint256 currentNoVotes,
        uint256 outcomeYesVotes,
        uint256 outcomeNoVotes,
        uint256 liquidityParameter
    ) external pure returns (int256) {
        return LMSR.getCost(currentYesVotes, currentNoVotes, outcomeYesVotes, outcomeNoVotes, liquidityParameter);
    }
}
