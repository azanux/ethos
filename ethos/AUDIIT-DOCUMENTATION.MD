// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { UD60x18, unwrap, convert, exp } from "@prb/math/src/UD60x18.sol";

/**
 * @title LMSR
 * @dev This library implements the Logarithmic Market Scoring Rule (LMSR) mechanism to calculate
 *      odds and costs in a prediction market setting using a fixed-point arithmetic format
 *      (UD60x18) for stable and precise computations.
 *
 * The LMSR model sets the cost of a given state based on the current quantities ("votes") of two
 * opposing positions—like "yes" vs. "no." The relative prices adjust automatically as votes
 * change, ensuring that no participant can gain a risk-free profit through arbitrage.
 *
 * Core formulas:
 *
 *     odds = e^(yes/b) / [ e^(yes/b) + e^(no/b) ]
 *
 *     cost = b * ln(e^(yes/b) + e^(no/b))
 *
 * - b is the liquidity parameter (higher b = more stable prices, but higher capital requirements)
 * - yes and no are the count of "yes" and "no" votes respectively
 *
 * All returned values are UD60x18 fixed-point numbers, i.e., scaled by 1e18. These are dimensionless
 * ratios. To convert them into a currency unit (like wei), you must multiply by a base price or
 * scaling factor outside this library.
 *
 * MATHEMATICAL BOUNDS AND SAFETY:
 * - The exp() function reverts if its input > ~133.084.
 * - Therefore, (votes / b) must not exceed ~133.
 * - In practice: votes ≤ 133 * b
 *
 * Example: If b = 1000, then max safe votes ≈ 133,000 per side.
 *
 * LIQUIDITY PARAMETER (b) GUIDELINES:
 * - Recommended range: ~100-1,000,000
 * - Smaller b: More volatility, lower capital requirements, risk of overflow with fewer votes.
 * - Larger b: More stability, higher capital requirements, safer from overflow.
 */

library LMSR {
  error VotesExceedSafeLimit(uint256 votes, uint256 liquidityParameter, uint256 maxSafe);

  /**
   * @notice Computes the current odds (yes or no) given the market state.
   *
   * The formula:
   *     odds = e^(yes/b) / [ e^(yes/b) + e^(no/b) ]
   *
   * @param yesVotes Total number of "yes" votes currently in the market.
   * @param noVotes Total number of "no" votes currently in the market.
   * @param liquidityParameter The market's liquidity parameter (b).
   * @param isYes If true, returns the odds for the "yes" side; if false, for the "no" side.
   * @return ratio The current odds in a percentage from 0 to 1 (scaled up by 1e18).
   */
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
    UD60x18 priceRatio = isYes ? yesExp.div(sumExp) : noExp.div(sumExp);

    // Unwrap to get  scaled ratio
    ratio = unwrap(priceRatio);
  }

  /**
   * @notice Computes the incremental cost of changing the market state from
   *         (currentYesVotes, currentNoVotes) to (outcomeYesVotes, outcomeNoVotes).
   *
   * This is computed as:
   *     costDiff = cost(outcomeYesVotes, outcomeNoVotes) - cost(currentYesVotes, currentNoVotes)
   *
   * where:
   *     cost = b * ln(e^(yes/b) + e^(no/b))
   *
   * @param currentYesVotes The current number of "yes" votes.
   * @param currentNoVotes The current number of "no" votes.
   * @param outcomeYesVotes The target number of "yes" votes after the trade.
   * @param outcomeNoVotes The target number of "no" votes after the trade.
   * @param liquidityParameter The market's liquidity parameter (b).
   * @return costDiff The incremental cost difference, as an integral of the odds percentage (scaled up by 1e18).
   */
  function getCost(
    uint256 currentYesVotes,
    uint256 currentNoVotes,
    uint256 outcomeYesVotes,
    uint256 outcomeNoVotes,
    uint256 liquidityParameter
  ) public pure returns (int256 costDiff) {
    uint256 oldCost = _cost(currentYesVotes, currentNoVotes, liquidityParameter);
    uint256 newCost = _cost(outcomeYesVotes, outcomeNoVotes, liquidityParameter);
    costDiff = int256(newCost) - int256(oldCost);
  }

  /**
   * @dev Internal function implementing the LMSR cost formula:
   *
   *     cost = b * ln(e^(yes/b) + e^(no/b))
   *
   * Returns the cost in UD60x18 format (scaled by 1e18).
   *
   * @param yesVotes The number of "yes" votes.
   * @param noVotes The number of "no" votes.
   * @param liquidityParameter The market's liquidity parameter (b).
   * @return costResult The cost value in UD60x18 format (scaled by 1e18).
   */
  function _cost(
    uint256 yesVotes,
    uint256 noVotes,
    uint256 liquidityParameter
  ) public pure returns (uint256 costResult) {
    // Compute e^(yes/b) and e^(no/b)
    (UD60x18 yesExp, UD60x18 noExp) = _getExponentials(yesVotes, noVotes, liquidityParameter);

    // sumExp = e^(yes/b) + e^(no/b)
    UD60x18 sumExp = yesExp.add(noExp);

    // lnVal = ln(e^(yes/b) + e^(no/b))
    UD60x18 lnVal = sumExp.ln();

    // Unwrap lnVal and multiply by b (also in UD60x18) to get cost
    uint256 lnValUnwrapped = unwrap(lnVal);
    costResult = lnValUnwrapped * liquidityParameter;
  }

  /**
   * @dev Computes e^(yes/b) and e^(no/b) using UD60x18 arithmetic. Reverts if
   *      votes exceed the safe limit, which could cause overflow in exp().
   *
   * @param yesVotes The number of "yes" votes.
   * @param noVotes The number of "no" votes.
   * @param liquidityParameter The market's liquidity parameter (b).
   * @return yesExp e^(yes/b) in UD60x18 format.
   * @return noExp e^(no/b) in UD60x18 format.
   *
   * Reverts with VotesExceedSafeLimit if either vote count > 133 * b.
   */
  function _getExponentials(
    uint256 yesVotes,
    uint256 noVotes,
    uint256 liquidityParameter
  ) public pure returns (UD60x18 yesExp, UD60x18 noExp) {
    // maxSafeRatio chosen as 133 since exp input ~133.084 causes overflow
    uint256 maxSafeRatio = 133;

    if (
      yesVotes > maxSafeRatio * liquidityParameter || noVotes > maxSafeRatio * liquidityParameter
    ) {
      revert VotesExceedSafeLimit(
        yesVotes > noVotes ? yesVotes : noVotes,
        liquidityParameter,
        maxSafeRatio * liquidityParameter
      );
    }

    // Convert to UD60x18
    UD60x18 yesUD = convert(yesVotes);
    UD60x18 noUD = convert(noVotes);
    UD60x18 b = convert(liquidityParameter);

    // Compute ratios
    UD60x18 yesRatio = yesUD.div(b);
    UD60x18 noRatio = noUD.div(b);

    // Compute exponentials
    yesExp = exp(yesRatio);
    noExp = exp(noRatio);
  }
}




// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControl } from "./utils/AccessControl.sol";
import { ETHOS_PROFILE } from "./utils/Constants.sol";
import { IEthosProfile } from "./interfaces/IEthosProfile.sol";
import { InsufficientLiquidity, InactiveMarket, InsufficientFunds, FeeTransferFailed, InsufficientVotesOwned, InsufficientVotesToSell, InvalidProfileId, MarketAlreadyExists, MarketCreationErrorCode, MarketCreationUnauthorized, MarketDoesNotExist, SellSlippageLimitExceeded, InvalidMarketConfigOption, UnauthorizedGraduation, UnauthorizedWithdrawal, MarketNotGraduated, ZeroAddressNotAllowed } from "./errors/ReputationMarketErrors.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { LMSR } from "./utils/LMSR.sol";
import { ITargetStatus } from "./interfaces/ITargetStatus.sol";

/**
 * @title ReputationMarket
 * @dev This contract establishes Reputation Markets, allowing buying and selling of "trust" and "distrust" votes for specific
 * Ethos profiles, reflecting the perceived reputation of the profile's owner. Using a Logarithmic Market Scoring Rule (LMSR),
 * vote prices fluctuate dynamically based on demand: an increase in trust votes raises their price while lowering distrust prices,
 * and vice versa. This setup allows participants to potentially profit by buying votes at lower prices and selling them at higher
 * prices when sentiment changes.
 *
 * The vote pricing model functions like a prediction market with perpetual duration, inversely adjusting trust and distrust
 * prices. As the trust price rises, the distrust price decreases proportionally, with both prices always summing to the market's basePrice.
 * This mechanism reflects the balance of sentiment, allowing users to gauge a profile's perceived trustworthiness as a percentage.
 * Unlike traditional prediction markets, this model has no end date or decision criteria, operating continuously until market graduation.
 *
 * Graduation: the intent is that upon graduation, each holder of trust and distrust votes receives equivalent ERC-20 tokens
 * representing their position. These tokens will be freely tradable, without the reciprocal pricing mechanism of this contract.
 * A price floor will be established by Ethos, offering to buy back the new ERC-20 tokens at their final vote price upon graduation,
 * ensuring participants don't incur losses due to the transition. Only Ethos, through a designated contract, will be authorized to
 * graduate markets and withdraw funds to initiate this conversion process. This conversion contract is not yet implemented.
 *
 * Market configurations offer different initial setups to control the volatility and stability of reputation markets.
 * With the default configuration, a low number of initial votes can cause significant price fluctuations, leading to a highly
 * volatile market. To provide flexibility, we offer additional configurations (e.g., deluxe, premium) with varying initial
 * liquidity parameters. These configurations allow market creators to choose the market's volatility level: lower liquidity
 * parameters result in faster price changes, while higher liquidity enables smoother, gradual price adjustments. Ethos admins can
 * add or remove configurations without modifying the core contract, enabling ongoing experimentation with different market structures.
 */
contract ReputationMarket is AccessControl, UUPSUpgradeable, ReentrancyGuard, ITargetStatus {
  /**
   * @dev Constructor that disables initializers when the implementation contract is deployed.
   * This prevents the implementation contract from being initialized, which is important for
   * security since the implementation contract should never be used directly, only through
   * delegatecall from the proxy.
   */
  constructor() {
    _disableInitializers();
  }

  using Math for uint256;
  // --- Structs ---
  struct Market {
    uint256[2] votes;
    uint256 basePrice;
    uint256 liquidityParameter;
  }

  struct MarketInfo {
    uint256 profileId;
    uint256 trustVotes;
    uint256 distrustVotes;
    uint256 basePrice;
    uint256 liquidityParameter;
  }

  /**
   * @notice Configuration parameters for initializing new reputation markets
   * @dev Used to define different tiers of market initialization options
   * @param liquidity The LMSR liquidity parameter that controls price sensitivity
   * @param basePrice The base price that trust and distrust vote prices will sum to (in wei)
   * @param creationCost The amount of ETH required to create a market with this configuration
   */
  struct MarketConfig {
    uint256 liquidity;
    uint256 basePrice;
    uint256 creationCost;
  }

  /**
   * @notice Tracks the last known state of a market for calculating and emitting price/vote deltas
   * @dev Used by _emitMarketUpdate to track changes between market updates
   * @param voteTrust The last recorded number of trust votes
   * @param voteDistrust The last recorded number of distrust votes
   * @param positivePrice The last recorded trust vote price
   * @param negativePrice The last recorded distrust vote price
   * @param lastUpdateBlock The block number of the last market update
   */
  struct MarketUpdateInfo {
    uint256 voteTrust;
    uint256 voteDistrust;
    uint256 positivePrice;
    uint256 negativePrice;
    uint256 lastUpdateBlock;
  }
  // --- Constants ---
  uint256 public constant DEFAULT_PRICE = 0.01 ether;
  uint256 public constant MINIMUM_BASE_PRICE = 0.0001 ether;
  uint256 private constant TRUST = 1;
  uint256 private constant DISTRUST = 0;
  uint256 private constant BASIS_POINTS_BASE = 10000;
  uint256 private constant MAX_PROTOCOL_FEE_BASIS_POINTS = 500; // 5%
  uint256 private constant MAX_DONATION_BASIS_POINTS = 500; // 5%

  // --- State Variables ---
  /**
   * @dev Entry and exit fees (in basis points) allow flexible revenue generation for the protocol.
   * Both fees are adjustable up to a capped maximum to ensure stable, predictable market costs for users.
   */
  uint256 public entryProtocolFeeBasisPoints;
  uint256 public exitProtocolFeeBasisPoints;
  address public protocolFeeAddress;
  /**
   * @dev Donations, also referred to as rewards, create incentives for profile owners who open reputation markets for themselves.
   * These rewards compensate owners for the reputational risk and effort involved in promoting adoption of the market.
   */
  uint256 public donationBasisPoints;

  // authorized market creation options; index 0 is the default config
  MarketConfig[] public marketConfigs;

  // profileId => isPositive => votes
  mapping(uint256 => Market) private markets;
  // profileId => funds currently invested in each market
  mapping(uint256 => uint256) public marketFunds;
  // profileId => graduated (markets that have graduated)
  mapping(uint256 => bool) public graduatedMarkets;
  // profileId => MarketUpdateInfo
  mapping(uint256 => MarketUpdateInfo) public lastMarketUpdates;
  // msg.sender => profileId => isPositive => votes
  mapping(address => mapping(uint256 => Market)) private votesOwned;
  // profileId => participant address
  // append only; don't bother removing. Use isParticipant to check if they've sold all their votes.
  mapping(uint256 => address[]) public participants;
  // profileId => participant => isParticipant
  mapping(uint256 => mapping(address => bool)) public isParticipant;
  // recipient address => donation amount
  mapping(address => uint256) public donationEscrow;
  // profileId => recipient address
  mapping(uint256 => address) public donationRecipient;

  // Mapping to store the allow list of profileIds that can create their market.
  // profileId => isAllowed bool;
  mapping(uint256 => bool) private creationAllowedProfileIds;

  // This is used to control whether anyone can create a market or only the contract admin or addresses in the allow list.
  bool private enforceCreationAllowList;

  // Add storage gap as the last storage variable
  // This allows us to add new storage variables in future upgrades
  // by reducing the size of this gap
  uint256[50] private __gap;

  event MarketCreated(uint256 indexed profileId, address indexed creator, MarketConfig config);
  event MarketConfigAdded(uint256 indexed configIndex, MarketConfig config);
  event MarketConfigRemoved(uint256 indexed configIndex, MarketConfig config);
  event VotesBought(
    uint256 indexed profileId,
    address indexed buyer,
    bool indexed isPositive,
    uint256 amount,
    uint256 funds,
    uint256 boughtAt
  );
  event VotesSold(
    uint256 indexed profileId,
    address indexed seller,
    bool indexed isPositive,
    uint256 amount,
    uint256 funds,
    uint256 soldAt
  );
  event MarketUpdated(
    uint256 indexed profileId,
    uint256 indexed voteTrust,
    uint256 indexed voteDistrust,
    uint256 trustPrice,
    uint256 distrustPrice,
    int256 deltaVoteTrust,
    int256 deltaVoteDistrust,
    int256 deltaTrustPrice,
    int256 deltaDistrustPrice,
    uint256 blockNumber,
    uint256 updatedAt
  );
  event DonationWithdrawn(address indexed recipient, uint256 amount);
  event DonationRecipientUpdated(
    uint256 indexed profileId,
    address indexed oldRecipient,
    address indexed newRecipient
  );
  event MarketGraduated(uint256 indexed profileId);
  event MarketFundsWithdrawn(uint256 indexed profileId, address indexed withdrawer, uint256 amount);

  /**
   * @notice Ensures the market is not graduated (still active for trading)
   * @dev Modifier used to restrict trading functions to only active markets
   * @param profileId The ID of the market to check
   */
  modifier activeMarket(uint256 profileId) {
    if (graduatedMarkets[profileId]) revert InactiveMarket(profileId);

    _;
  }

  /**
   * @dev initializer in place of constructor.
   * @param owner Owner address.
   * @param admin Admin address.
   * @param expectedSigner ExpectedSigner address.
   * @param signatureVerifier SignatureVerifier address.
   * @param contractAddressManagerAddr ContractAddressManagerAddr address.
   */
  function initialize(
    address owner,
    address admin,
    address expectedSigner,
    address signatureVerifier,
    address contractAddressManagerAddr
  ) external initializer {
    __accessControl_init(
      owner,
      admin,
      expectedSigner,
      signatureVerifier,
      contractAddressManagerAddr
    );
    __UUPSUpgradeable_init();
    enforceCreationAllowList = true;
    // Default market configurations:

    // Default tier
    // - Minimum viable liquidity for small/new markets
    // - 0.002 ETH initial liquidity
    // - 1 vote each for trust/distrust (volatile price at low volume)
    marketConfigs.push(
      // max votes 133,000; ~.01 ETH per vote, max market size: 1,330 ETH
      MarketConfig({ liquidity: 1000, basePrice: DEFAULT_PRICE, creationCost: 0.2 ether })
    );

    // Deluxe tier
    // - Moderate liquidity for established profiles
    // - 0.05 ETH initial liquidity
    // - 1,000 votes each for trust/distrust (moderate price stability)
    marketConfigs.push(
      // max votes 1,330,000; ~.01 ETH per vote, max market size: 13,300 ETH
      MarketConfig({ liquidity: 10000, basePrice: DEFAULT_PRICE, creationCost: 0.5 ether })
    );

    // Premium tier
    // - High liquidity for stable price discovery
    // - 0.1 ETH initial liquidity
    // - 10,000 votes each for trust/distrust (highly stable price)
    marketConfigs.push(
      // max votes 13,300,000; ~.01 ETH per vote, max market size: 133,000 ETH
      MarketConfig({ liquidity: 100000, basePrice: DEFAULT_PRICE, creationCost: 1.0 ether })
    );
  }

  /**
   * @notice Required override for UUPS proxy upgrade authorization
   * @param newImplementation The address of the new implementation contract to upgrade to
   */
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyOwner onlyNonZeroAddress(newImplementation) {
    // Intentionally left blank to ensure onlyOwner and zeroCheck modifiers run
  }

  // --- Market Creation ---

  /**
   * @notice Creates a new reputation market for a profile using the default market configuration
   * @dev This is a convenience function that calls createMarketWithConfig with index 0
   */
  function createMarket() public payable whenNotPaused {
    createMarketWithConfig(0);
  }

  /**
   * @notice Creates a new reputation market for a profile using a specific market configuration
   * @dev Only callable by users for their own profiles when allowed; see createMarketWithConfigAdmin for creating markets on behalf of others
   * @param marketConfigIndex The index of the market configuration to use
   */
  function createMarketWithConfig(uint256 marketConfigIndex) public payable whenNotPaused {
    uint256 senderProfileId = _getProfileIdForAddress(msg.sender);

    // Verify sender can create market
    if (enforceCreationAllowList && !creationAllowedProfileIds[senderProfileId])
      revert MarketCreationUnauthorized(
        MarketCreationErrorCode.PROFILE_NOT_AUTHORIZED,
        msg.sender,
        senderProfileId
      );

    _createMarket(senderProfileId, msg.sender, marketConfigIndex);
  }

  /**
   * @notice Creates a new reputation market for a profile using a specific market configuration
   * @dev Only callable by admins, can create markets for any address/profile
   * @param marketOwner Create this market on behalf of this owner; will look up their profile and send donations
   * @param marketConfigIndex The index of the market configuration to use
   */
  function createMarketWithConfigAdmin(
    address marketOwner,
    uint256 marketConfigIndex
  ) public payable whenNotPaused onlyAdmin {
    uint256 profileId = _getProfileIdForAddress(marketOwner);
    _createMarket(profileId, marketOwner, marketConfigIndex);
  }

  /**
   * @dev Internal function to handle market creation logic
   * @param profileId The ID of the profile to create a market for
   * @param recipient The address of the market owner (will receive donations)
   * @param marketConfigIndex The index of the market configuration to use
   */
  function _createMarket(
    uint256 profileId,
    address recipient,
    uint256 marketConfigIndex
  ) private nonReentrant {
    // ensure a market doesn't already exist for this profile
    if (markets[profileId].votes[TRUST] != 0 || markets[profileId].votes[DISTRUST] != 0)
      revert MarketAlreadyExists(profileId);

    // ensure the specified config option is valid
    if (marketConfigIndex >= marketConfigs.length)
      revert InvalidMarketConfigOption("Invalid config index");

    uint256 creationCost = marketConfigs[marketConfigIndex].creationCost;

    // Handle creation cost, refunds and market funds for non-admin users
    if (!hasRole(ADMIN_ROLE, msg.sender)) {
      if (msg.value < creationCost) revert InsufficientLiquidity(creationCost);
      marketFunds[profileId] = creationCost;
      if (msg.value > creationCost) {
        _sendEth(msg.value - creationCost);
      }
    } else {
      // when an admin creates a market, there is no minimum creation cost; use whatever they sent
      marketFunds[profileId] = msg.value;
    }

    // Create the new market using the specified config
    markets[profileId].votes[TRUST] = 1;
    markets[profileId].votes[DISTRUST] = 1;
    markets[profileId].basePrice = marketConfigs[marketConfigIndex].basePrice;
    markets[profileId].liquidityParameter = marketConfigs[marketConfigIndex].liquidity;

    donationRecipient[profileId] = recipient;

    emit MarketCreated(profileId, msg.sender, marketConfigs[marketConfigIndex]);
    _emitMarketUpdate(profileId);
  }

  // --- Market Configuration ---

  /**
   * @notice Adds a new market configuration option
   * @param liquidity The LMSR liquidity parameter for the new config
   * @param basePrice The base price for the new config (in wei)
   * @param creationCost The ETH cost to create a market with this config
   * @return The index of the newly added config
   */
  function addMarketConfig(
    uint256 liquidity,
    uint256 basePrice,
    uint256 creationCost
  ) public onlyAdmin whenNotPaused returns (uint256) {
    if (liquidity < 100) revert InvalidMarketConfigOption("Min liquidity not met");

    if (basePrice < MINIMUM_BASE_PRICE) revert InvalidMarketConfigOption("Insufficient base price");

    marketConfigs.push(
      MarketConfig({ liquidity: liquidity, basePrice: basePrice, creationCost: creationCost })
    );

    uint256 configIndex = marketConfigs.length - 1;
    emit MarketConfigAdded(configIndex, marketConfigs[configIndex]);
    return configIndex;
  }

  /**
   * @dev Removes a market configuration option while maintaining at least one config
   * @param configIndex The index of the config to remove
   */
  function removeMarketConfig(uint256 configIndex) public onlyAdmin whenNotPaused {
    // Cannot remove if only one config remains
    if (marketConfigs.length <= 1) revert InvalidMarketConfigOption("Must keep one config");

    // Check if the index is valid
    if (configIndex >= marketConfigs.length) revert InvalidMarketConfigOption("index not found");

    emit MarketConfigRemoved(configIndex, marketConfigs[configIndex]);

    // If this is not the last element, swap with the last element
    uint256 lastIndex = marketConfigs.length - 1;
    if (configIndex != lastIndex) {
      marketConfigs[configIndex] = marketConfigs[lastIndex];
    }

    // Remove the last element
    marketConfigs.pop();
  }

  /**
   * @dev Controls whether the allow list is enforced for market creation
   * @param value true to enforce allow list (only allowed profiles can create markets),
   *              false to allow anyone to create a market for their own profile
   */
  function setAllowListEnforcement(bool value) public onlyAdmin whenNotPaused {
    enforceCreationAllowList = value;
  }

  /**
   * @notice Sets whether a specific profile is allowed to create a market
   * @param profileId The profile ID to modify permissions for
   * @param value True to allow market creation, false to disallow
   */
  function setUserAllowedToCreateMarket(
    uint256 profileId,
    bool value
  ) public onlyAdmin whenNotPaused {
    creationAllowedProfileIds[profileId] = value;
  }

  // --- Core Trading Functions ---

  /**
   * @notice Buy trust or distrust votes for a market
   * @dev Protocol fees and donations are taken from the payment amount.
   *      Excess ETH is refunded to the buyer.
   * @param profileId The ID of the market to buy votes in
   * @param isPositive True to buy trust votes, false to buy distrust votes
   * @param maxVotesToBuy Maximum number of votes to buy with the provided ETH
   * @param minVotesToBuy Minimum acceptable number of votes (protects against slippage)
   * @notice payable - Send ETH to cover vote cost plus fees
   */
  function buyVotes(
    uint256 profileId,
    bool isPositive,
    uint256 maxVotesToBuy,
    uint256 minVotesToBuy
  ) public payable whenNotPaused activeMarket(profileId) nonReentrant {
    _checkMarketExists(profileId);
    // preliminary check to ensure this is enough money to buy the minimum requested votes.
    (, , , uint256 total) = _calculateBuy(markets[profileId], isPositive, minVotesToBuy);
    if (total > msg.value) revert InsufficientFunds();

    (
      uint256 purchaseCostBeforeFees,
      uint256 protocolFee,
      uint256 donation,
      uint256 totalCostIncludingFees
    ) = _calculateBuy(markets[profileId], isPositive, maxVotesToBuy);
    uint256 currentVotesToBuy = maxVotesToBuy;
    // if the cost is greater than the maximum votes to buy,
    // decrement vote count and recalculate until we identify the max number of votes they can afford
    while (totalCostIncludingFees > msg.value) {
      currentVotesToBuy--;
      (purchaseCostBeforeFees, protocolFee, donation, totalCostIncludingFees) = _calculateBuy(
        markets[profileId],
        isPositive,
        currentVotesToBuy
      );
    }

    // Update market state
    markets[profileId].votes[isPositive ? TRUST : DISTRUST] += currentVotesToBuy;
    votesOwned[msg.sender][profileId].votes[isPositive ? TRUST : DISTRUST] += currentVotesToBuy;

    // Add buyer to participants if not already a participant
    if (!isParticipant[profileId][msg.sender]) {
      participants[profileId].push(msg.sender);
      isParticipant[profileId][msg.sender] = true;
    }

    // tally market funds
    marketFunds[profileId] += purchaseCostBeforeFees;

    // Distribute the fees
    applyFees(protocolFee, donation, profileId);

    // Calculate and refund remaining funds
    uint256 refund = msg.value - totalCostIncludingFees;
    if (refund > 0) _sendEth(refund);
    emit VotesBought(
      profileId,
      msg.sender,
      isPositive,
      currentVotesToBuy,
      totalCostIncludingFees,
      block.timestamp
    );
    _emitMarketUpdate(profileId);
  }

  /**
   * @dev Previews the cost and fees for buying votes (without executing the trade)
   * @param market The market state to calculate costs for
   * @param isPositive True for trust votes, false for distrust votes
   * @param votesToBuy Number of votes to calculate cost for
   * @return purchaseCostBeforeFees The base cost of votes before fees
   * @return protocolFee Protocol fee amount
   * @return donation Donation amount for market creator
   * @return totalCostIncludingFees Total cost including all fees
   */
  function _calculateBuy(
    Market memory market,
    bool isPositive,
    uint256 votesToBuy
  )
    private
    view
    returns (
      uint256 purchaseCostBeforeFees,
      uint256 protocolFee,
      uint256 donation,
      uint256 totalCostIncludingFees
    )
  {
    // Determine the cost to purchase this many votes
    purchaseCostBeforeFees = _calcCost(market, isPositive, true, votesToBuy);

    // Preview how much fees would cost on top of the purchase cost
    (totalCostIncludingFees, protocolFee, donation) = previewEntryFees(purchaseCostBeforeFees);
  }

  /**
   * @notice Sell trust or distrust votes from a market
   * @dev Protocol fees are taken from the sale proceeds.
   *      Proceeds are sent to the seller after fees.
   * @param profileId The ID of the market to sell votes in
   * @param isPositive True to sell trust votes, false to sell distrust votes
   * @param votesToSell Number of votes to sell
   * @param minimumVotePrice Minimum acceptable price per vote (protects against slippage)
   */
  function sellVotes(
    uint256 profileId,
    bool isPositive,
    uint256 votesToSell,
    uint256 minimumVotePrice
  ) public whenNotPaused activeMarket(profileId) nonReentrant {
    _checkMarketExists(profileId);
    (uint256 proceedsBeforeFees, uint256 protocolFee, uint256 proceedsAfterFees) = _calculateSell(
      markets[profileId],
      profileId,
      isPositive,
      votesToSell
    );

    uint256 pricePerVote = votesToSell > 0 ? proceedsBeforeFees / votesToSell : 0;
    if (pricePerVote < minimumVotePrice) {
      revert SellSlippageLimitExceeded(minimumVotePrice, pricePerVote);
    }

    markets[profileId].votes[isPositive ? TRUST : DISTRUST] -= votesToSell;
    votesOwned[msg.sender][profileId].votes[isPositive ? TRUST : DISTRUST] -= votesToSell;
    // tally market funds
    marketFunds[profileId] -= proceedsBeforeFees;

    // apply protocol fees
    applyFees(protocolFee, 0, profileId);

    // send the proceeds to the seller
    _sendEth(proceedsAfterFees);

    emit VotesSold(
      profileId,
      msg.sender,
      isPositive,
      votesToSell,
      proceedsAfterFees,
      block.timestamp
    );
    _emitMarketUpdate(profileId);
  }

  /**
   * @dev Previews the proceeds and fees for selling votes (without executing the trade)
   * @param market The market state to calculate proceeds for
   * @param profileId The ID of the market
   * @param isPositive True for trust votes, false for distrust votes
   * @param votesToSell Number of votes to calculate proceeds for
   * @return proceedsBeforeFees The base proceeds before fees
   * @return protocolFee Protocol fee amount
   * @return proceedsAfterFees Net proceeds after fees
   */
  function _calculateSell(
    Market memory market,
    uint256 profileId,
    bool isPositive,
    uint256 votesToSell
  )
    private
    view
    returns (uint256 proceedsBeforeFees, uint256 protocolFee, uint256 proceedsAfterFees)
  {
    uint256 votesAvailable = votesOwned[msg.sender][profileId].votes[isPositive ? TRUST : DISTRUST];
    if (votesToSell > votesAvailable) revert InsufficientVotesOwned(profileId, msg.sender);

    if (market.votes[isPositive ? TRUST : DISTRUST] < votesToSell)
      revert InsufficientVotesToSell(profileId);

    // determine the proceeds from the sale
    proceedsBeforeFees = _calcCost(market, isPositive, false, votesToSell);

    // preview how many fees would be removed from the proceeds
    (proceedsAfterFees, protocolFee) = previewExitFees(proceedsBeforeFees);
  }

  // ---Rewards & Donations---
  /**
   * @notice Updates the donation recipient for a market
   * @dev Only callable by current recipient. New recipient must have same profileId.
   *      Transfers any existing donation balance to the new recipient.
   * @param profileId The profile ID of the market to update
   * @param newRecipient The new address to receive donations
   */
  function updateDonationRecipient(
    uint256 profileId,
    address newRecipient
  ) public whenNotPaused nonReentrant {
    if (newRecipient == address(0)) revert ZeroAddress();

    // if the new donation recipient has a balance, do not allow overwriting
    if (donationEscrow[newRecipient] != 0)
      revert InvalidMarketConfigOption("Donation recipient has balance");

    // Ensure the sender is the current donation recipient
    if (msg.sender != donationRecipient[profileId]) revert InvalidProfileId();

    // Ensure the new recipient has the same Ethos profileId
    uint256 recipientProfileId = _ethosProfileContract().verifiedProfileIdForAddress(newRecipient);
    if (recipientProfileId != profileId) revert InvalidProfileId();

    // Update the donation recipient reference
    donationRecipient[profileId] = newRecipient;
    // Swap the current donation balance to the new recipient
    donationEscrow[newRecipient] += donationEscrow[msg.sender];
    donationEscrow[msg.sender] = 0;
    emit DonationRecipientUpdated(profileId, msg.sender, newRecipient);
  }

  /**
   * @notice Allows a market owner to withdraw their accumulated donations
   * @dev Transfers all donations from escrow to the caller
   * @return The amount of ETH withdrawn
   */
  function withdrawDonations() public whenNotPaused nonReentrant returns (uint256) {
    uint256 amount = donationEscrow[msg.sender];
    if (amount == 0) revert InsufficientFunds();

    // Reset escrow balance before transfer to prevent reentrancy
    donationEscrow[msg.sender] = 0;

    // Transfer the funds
    (bool success, ) = msg.sender.call{ value: amount }("");
    if (!success) revert FeeTransferFailed("Donation withdrawal failed");

    emit DonationWithdrawn(msg.sender, amount);
    return amount;
  }

  // --- Fee Management ---

  /**
   * @notice Sets the donation percentage in basis points
   * @param basisPoints The new donation percentage in basis points, maximum 500 (5%)
   */
  function setDonationBasisPoints(uint256 basisPoints) public onlyAdmin whenNotPaused {
    if (basisPoints > MAX_DONATION_BASIS_POINTS)
      revert InvalidMarketConfigOption("Donation exceeds maximum");

    donationBasisPoints = basisPoints;
  }

  /**
   * @dev Sets the protocol fee in basis points
   * @param basisPoints The new fee in basis points, maximum 500 (5%)
   */
  function setEntryProtocolFeeBasisPoints(uint256 basisPoints) public onlyAdmin whenNotPaused {
    // must specify a protocol fee address before enabling entry fees
    if (protocolFeeAddress == address(0)) revert ZeroAddress();
    if (basisPoints > MAX_PROTOCOL_FEE_BASIS_POINTS)
      revert InvalidMarketConfigOption("Fee exceeds maximum");

    entryProtocolFeeBasisPoints = basisPoints;
  }

  /**
   * @notice Sets the exit protocol fee in basis points
   * @param basisPoints The new fee in basis points, maximum 500 (5%)
   */
  function setExitProtocolFeeBasisPoints(uint256 basisPoints) public onlyAdmin whenNotPaused {
    // must specify a protocol fee address before enabling exit fees
    if (protocolFeeAddress == address(0)) revert ZeroAddress();
    if (basisPoints > MAX_PROTOCOL_FEE_BASIS_POINTS)
      revert InvalidMarketConfigOption("Fee exceeds maximum");

    exitProtocolFeeBasisPoints = basisPoints;
  }

  /**
   * @notice Sets the address that receives protocol fees
   * @param newProtocolFeeAddress The address to receive protocol fees
   */
  function setProtocolFeeAddress(address newProtocolFeeAddress) public onlyAdmin whenNotPaused {
    if (newProtocolFeeAddress == address(0)) revert ZeroAddress();

    protocolFeeAddress = newProtocolFeeAddress;
  }

  // --- Market Graduation & Withdrawal ---

  /**
   * @notice Graduates a market, marking it as inactive for trading
   * @dev Only callable by the authorized Ethos graduation contract
   * @param profileId The ID of the market to graduate
   */
  function graduateMarket(
    uint256 profileId
  ) public whenNotPaused activeMarket(profileId) nonReentrant {
    address authorizedAddress = contractAddressManager.getContractAddressForName(
      "GRADUATION_WITHDRAWAL"
    );
    if (msg.sender != authorizedAddress) revert UnauthorizedGraduation();

    _checkMarketExists(profileId);
    graduatedMarkets[profileId] = true;
    emit MarketGraduated(profileId);
  }

  /**
   * @notice Withdraws all funds from a graduated market
   * @dev Only callable by the authorized Ethos graduation contract
   * @param profileId The ID of the graduated market to withdraw from
   */
  function withdrawGraduatedMarketFunds(uint256 profileId) public whenNotPaused nonReentrant {
    address authorizedAddress = contractAddressManager.getContractAddressForName(
      "GRADUATION_WITHDRAWAL"
    );
    if (msg.sender != authorizedAddress) revert UnauthorizedWithdrawal();

    _checkMarketExists(profileId);
    if (!graduatedMarkets[profileId]) revert MarketNotGraduated();

    if (marketFunds[profileId] == 0) revert InsufficientFunds();

    _sendEth(marketFunds[profileId]);
    emit MarketFundsWithdrawn(profileId, msg.sender, marketFunds[profileId]);
    marketFunds[profileId] = 0;
  }

  // --- View Functions ---

  /**
   * @notice Gets the current vote counts, prices, and parameters for a market
   * @param profileId The profile ID of the market to query
   * @return MarketInfo struct with trust/distrust votes, base price, and liquidity parameter
   */
  function getMarket(uint256 profileId) public view returns (MarketInfo memory) {
    return
      MarketInfo({
        profileId: profileId,
        trustVotes: markets[profileId].votes[TRUST],
        distrustVotes: markets[profileId].votes[DISTRUST],
        basePrice: markets[profileId].basePrice,
        liquidityParameter: markets[profileId].liquidityParameter
      });
  }

  /**
   * @notice Gets the number of available market configurations
   * @return The number of configurations in marketConfigs array
   */
  function getMarketConfigCount() public view returns (uint256) {
    return marketConfigs.length;
  }

  /**
   * @notice Gets the total number of addresses that have ever held votes in a market
   * @param profileId The profile ID of the market
   * @return The number of historical participants (includes addresses that sold all votes)
   */
  function getParticipantCount(uint256 profileId) public view returns (uint256) {
    _checkMarketExists(profileId);
    return participants[profileId].length;
  }

  /**
   * @notice Gets the number of trust and distrust votes owned by a user in a market
   * @param user The address of the user to query
   * @param profileId The profile ID of the market
   * @return MarketInfo struct with the user's vote counts and market parameters
   */
  function getUserVotes(address user, uint256 profileId) public view returns (MarketInfo memory) {
    return
      MarketInfo({
        profileId: profileId,
        trustVotes: votesOwned[user][profileId].votes[TRUST],
        distrustVotes: votesOwned[user][profileId].votes[DISTRUST],
        basePrice: markets[profileId].basePrice,
        liquidityParameter: markets[profileId].liquidityParameter
      });
  }

  /**
   * @notice Calculates the current odds for a market position and converts them to a price using the market's base price
   * @param profileId The profile ID of the market
   * @param isPositive Whether to get trust (true) or distrust (false) odds
   * @return The odds converted to a price in wei (odds * basePrice)
   */
  function getVotePrice(uint256 profileId, bool isPositive) public view returns (uint256) {
    _checkMarketExists(profileId);
    return _calcVotePrice(markets[profileId], isPositive);
  }

  /**
   * @dev Checks if the user is allowed to create a market.
   * @param profileId The profileId of the user to check.
   * @return True if the profile is allowed to create a market, false otherwise.
   */
  function isAllowedToCreateMarket(uint256 profileId) public view returns (bool) {
    return creationAllowedProfileIds[profileId];
  }

  /**
   * @notice Simulates buying votes to preview costs and fees without executing the trade
   * @param profileId The profile ID of the market
   * @param isPositive True for trust votes, false for distrust votes
   * @param votesToBuy Number of votes to simulate buying
   * @return purchaseCostBeforeFees The base cost of votes before fees
   * @return protocolFee Protocol fee amount
   * @return donation Donation amount for market creator
   * @return totalCostIncludingFees Total cost including all fees
   */
  function simulateBuy(
    uint256 profileId,
    bool isPositive,
    uint256 votesToBuy
  )
    public
    view
    activeMarket(profileId)
    returns (
      uint256 purchaseCostBeforeFees,
      uint256 protocolFee,
      uint256 donation,
      uint256 totalCostIncludingFees,
      uint256 newVotePrice
    )
  {
    _checkMarketExists(profileId);
    Market memory simulatedMarket = markets[profileId];

    (purchaseCostBeforeFees, protocolFee, donation, totalCostIncludingFees) = _calculateBuy(
      simulatedMarket,
      isPositive,
      votesToBuy
    );
    simulatedMarket.votes[isPositive ? TRUST : DISTRUST] += votesToBuy;
    newVotePrice = _calcVotePrice(simulatedMarket, isPositive);
  }

  /**
   * @notice Simulates selling votes to preview proceeds and fees without executing the trade
   * @param profileId The profile ID of the market
   * @param isPositive True for trust votes, false for distrust votes
   * @param votesToSell Number of votes to simulate selling
   * @return proceedsBeforeFees The base proceeds before fees
   * @return protocolFee Protocol fee amount
   * @return proceedsAfterFees Net proceeds after fees
   */
  function simulateSell(
    uint256 profileId,
    bool isPositive,
    uint256 votesToSell
  )
    public
    view
    activeMarket(profileId)
    returns (
      uint256 proceedsBeforeFees,
      uint256 protocolFee,
      uint256 proceedsAfterFees,
      uint256 newVotePrice
    )
  {
    _checkMarketExists(profileId);
    Market memory simulatedMarket = markets[profileId];

    (proceedsBeforeFees, protocolFee, proceedsAfterFees) = _calculateSell(
      simulatedMarket,
      profileId,
      isPositive,
      votesToSell
    );
    simulatedMarket.votes[isPositive ? TRUST : DISTRUST] -= votesToSell;
    newVotePrice = _calcVotePrice(simulatedMarket, isPositive);
  }

  // --- Internal Helper Functions ---

  /**
   * @notice Emits an event with the current market state and changes since last update
   * @dev Tracks changes in vote counts and prices between market updates
   * @param profileId The profile ID of the market to update
   */
  function _emitMarketUpdate(uint256 profileId) private {
    _checkMarketExists(profileId);
    uint256 currentPositivePrice = getVotePrice(profileId, true);
    uint256 currentNegativePrice = getVotePrice(profileId, false);

    MarketUpdateInfo storage lastUpdate = lastMarketUpdates[profileId];

    int256 deltaVoteTrust;
    int256 deltaVoteDistrust;
    int256 deltaPositivePrice;
    int256 deltaNegativePrice;

    if (lastUpdate.lastUpdateBlock != 0) {
      deltaVoteTrust = int256(markets[profileId].votes[TRUST]) - int256(lastUpdate.voteTrust);
      deltaVoteDistrust =
        int256(markets[profileId].votes[DISTRUST]) -
        int256(lastUpdate.voteDistrust);
      deltaPositivePrice = int256(currentPositivePrice) - int256(lastUpdate.positivePrice);
      deltaNegativePrice = int256(currentNegativePrice) - int256(lastUpdate.negativePrice);
    } else {
      deltaVoteTrust = int256(markets[profileId].votes[TRUST]);
      deltaVoteDistrust = int256(markets[profileId].votes[DISTRUST]);
      deltaPositivePrice = int256(currentPositivePrice);
      deltaNegativePrice = int256(currentNegativePrice);
    }

    emit MarketUpdated(
      profileId,
      markets[profileId].votes[TRUST],
      markets[profileId].votes[DISTRUST],
      currentPositivePrice,
      currentNegativePrice,
      deltaVoteTrust,
      deltaVoteDistrust,
      deltaPositivePrice,
      deltaNegativePrice,
      block.number,
      block.timestamp
    );

    // Update the lastMarketUpdates mapping
    lastMarketUpdates[profileId] = MarketUpdateInfo({
      voteTrust: markets[profileId].votes[TRUST],
      voteDistrust: markets[profileId].votes[DISTRUST],
      positivePrice: currentPositivePrice,
      negativePrice: currentNegativePrice,
      lastUpdateBlock: block.number
    });
  }

  /**
   * @notice Sends ETH to msg.sender
   * @param amount Amount of ETH to send in wei
   */
  function _sendEth(uint256 amount) private {
    (bool success, ) = payable(msg.sender).call{ value: amount }("");
    if (!success) revert FeeTransferFailed("ETH transfer failed");
  }

  /**
   * @dev Gets the verified profile ID for an address, reverts if none exists
   * @param userAddress The address to look up
   * @return profileId The verified profile ID for the address
   */
  function _getProfileIdForAddress(address userAddress) private view returns (uint256) {
    if (userAddress == address(0)) revert ZeroAddressNotAllowed();

    uint256 profileId = _ethosProfileContract().verifiedProfileIdForAddress(userAddress);
    if (profileId == 0) revert InvalidProfileId();

    return profileId;
  }

  /**
   * @notice Calculates the buy or sell price for votes based on market state
   * @dev Uses bonding curve formula: price = (votes * basePrice) / totalVotes
   * Markets are double sided, so the price of trust and distrust votes always sum to the base price
   * @param market The market state to calculate price for
   * @param isPositive Whether to calculate trust (true) or distrust (false) vote price
   * @return The calculated vote price
   */
  function _calcVotePrice(Market memory market, bool isPositive) private pure returns (uint256) {
    // odds are in a ratio of N / 1e18
    uint256 odds = LMSR.getOdds(
      market.votes[TRUST],
      market.votes[DISTRUST],
      market.liquidityParameter,
      isPositive
    );
    // multiply odds by base price to get price; divide by 1e18 to get price in wei
    // round up for trust, down for distrust so that prices always equal basePrice
    return
      odds.mulDiv(market.basePrice, 1e18, isPositive ? Math.Rounding.Floor : Math.Rounding.Ceil);
  }

  /**
   * @notice Calculates the cost of a trade using LMSR cost function
   * @dev The cost of a trade is the difference between:
   *      - Cost after the trade (with updated vote counts)
   *      - Cost before the trade (with current vote counts)
   * @param market The market state to calculate cost for
   * @param isPositive Whether to calculate for trust (true) or distrust (false) votes
   * @param isBuy True for buying votes, false for selling votes
   * @param amount Number of votes to buy or sell
   * @return cost The difference in LMSR costs scaled by basePrice
   */
  function _calcCost(
    Market memory market,
    bool isPositive,
    bool isBuy,
    uint256 amount
  ) private pure returns (uint256 cost) {
    // cost ratio is a unitless ratio of N / 1e18
    uint256[] memory voteDelta = new uint256[](2);
    // convert boolean input into market state change
    if (isBuy) {
      if (isPositive) {
        voteDelta[0] = market.votes[TRUST] + amount;
        voteDelta[1] = market.votes[DISTRUST];
      } else {
        voteDelta[0] = market.votes[TRUST];
        voteDelta[1] = market.votes[DISTRUST] + amount;
      }
    } else {
      if (isPositive) {
        voteDelta[0] = market.votes[TRUST] - amount;
        voteDelta[1] = market.votes[DISTRUST];
      } else {
        voteDelta[0] = market.votes[TRUST];
        voteDelta[1] = market.votes[DISTRUST] - amount;
      }
    }

    int256 costRatio = LMSR.getCost(
      market.votes[TRUST],
      market.votes[DISTRUST],
      voteDelta[0],
      voteDelta[1],
      market.liquidityParameter
    );

    uint256 positiveCostRatio = costRatio > 0 ? uint256(costRatio) : uint256(costRatio * -1);
    // multiply cost ratio by base price to get cost; divide by 1e18 to apply ratio
    cost = positiveCostRatio.mulDiv(
      market.basePrice,
      1e18,
      isPositive ? Math.Rounding.Floor : Math.Rounding.Ceil
    );
  }

  /**
   * @notice Reverts if no market exists for the given profile ID
   * @param profileId The profile ID to check
   */
  function _checkMarketExists(uint256 profileId) private view {
    if (markets[profileId].votes[TRUST] == 0 && markets[profileId].votes[DISTRUST] == 0)
      revert MarketDoesNotExist(profileId);
  }

  /* @notice Gets interface for interacting with Ethos Profile system
   * @return IEthosProfile interface for profile operations
   */
  function _ethosProfileContract() private view returns (IEthosProfile) {
    return IEthosProfile(contractAddressManager.getContractAddressForName(ETHOS_PROFILE));
  }

  /**
   * @notice Processes protocol fees and donations for a market transaction
   * @dev Protocol fees are sent immediately to the protocol fee address
   *      Donations are stored in escrow until withdrawn by the market owner
   * @param protocolFee Amount of protocol fee to collect
   * @param donation Amount to add to donation escrow
   * @param marketOwnerProfileId Profile ID of market owner who will receive the donation
   * @return fees Total amount of fees processed (protocol fee + donation)
   */
  function applyFees(
    uint256 protocolFee,
    uint256 donation,
    uint256 marketOwnerProfileId
  ) private returns (uint256 fees) {
    donationEscrow[donationRecipient[marketOwnerProfileId]] += donation;
    if (protocolFee > 0) {
      (bool success, ) = protocolFeeAddress.call{ value: protocolFee }("");
      if (!success) revert FeeTransferFailed("Protocol fee deposit failed");
    }
    fees = protocolFee + donation;
  }

  /**
   * @notice Calculates the protocol fee and donation amounts for a market entry (buy) transaction
   * @param fundsBeforeFees The base amount to calculate fees from
   * @return totalCostIncludingFees The total cost including protocol fee and donation
   * @return protocolFee The protocol fee amount
   * @return donation The donation amount for market creator
   */
  function previewEntryFees(
    uint256 fundsBeforeFees
  ) private view returns (uint256 totalCostIncludingFees, uint256 protocolFee, uint256 donation) {
    protocolFee = (fundsBeforeFees * entryProtocolFeeBasisPoints) / BASIS_POINTS_BASE;
    donation = (fundsBeforeFees * donationBasisPoints) / BASIS_POINTS_BASE;
    totalCostIncludingFees = fundsBeforeFees + protocolFee + donation;
  }

  /**
   * @notice Calculates the protocol fee for a market exit (sell) transaction
   * @param proceedsBeforeFees The base proceeds to calculate fees from
   * @return totalProceedsAfterFees The net proceeds after subtracting protocol fee
   * @return protocolFee The protocol fee amount
   */
  function previewExitFees(
    uint256 proceedsBeforeFees
  ) private view returns (uint256 totalProceedsAfterFees, uint256 protocolFee) {
    protocolFee = (proceedsBeforeFees * exitProtocolFeeBasisPoints) / BASIS_POINTS_BASE;
    totalProceedsAfterFees = proceedsBeforeFees - protocolFee;
  }

  /**
   * @dev Checks whether market exists and is allowed to be used for replies and upvotes
   * @param targetId Market profile id
   * @return exists Whether market exists
   * @return allowed Whether market is allowed to be used
   */
  function targetExistsAndAllowedForId(
    uint256 targetId
  ) external view returns (bool exists, bool allowed) {
    // A market exists if it has any votes (either trust or distrust)
    exists = markets[targetId].votes[TRUST] != 0 || markets[targetId].votes[DISTRUST] != 0;

    // A market is open for replies and votes if it exists and hasn't been graduated
    allowed = exists && !graduatedMarkets[targetId];
  }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
enum MarketCreationErrorCode {
  PROFILE_NOT_AUTHORIZED,
  PROFILE_MISMATCH
}

error InvalidProfileId();
error MarketAlreadyExists(uint256 profileId);
error MarketDoesNotExist(uint256 profileId);
error MarketCreationUnauthorized(
  MarketCreationErrorCode code,
  address addressStr,
  uint256 profileId
);
error InsufficientFunds();
error InsufficientLiquidity(uint256 creationCost);
error InsufficientVotesOwned(uint256 profileId, address addressStr);
error InsufficientVotesToSell(uint256 profileId);
error InvalidMarketConfigOption(string message);
error FeeTransferFailed(string message);
error InactiveMarket(uint256 profileId);
error UnauthorizedGraduation();
error UnauthorizedWithdrawal();
error MarketNotGraduated();
error NoFundsToWithdraw();
error ZeroAddressNotAllowed();
error SellSlippageLimitExceeded(uint256 minimumPricePerVote, uint256 actualPricePerVote);



1. Detailed Function Explanation
Contract: LMSR
Function: getOdds

Purpose: Computes the current odds for "yes" or "no" based on market state using the LMSR formula.
Returns: Scaled probability ratio for either "yes" or "no" (as a fixed-point number scaled by
1
0
18
10
18
 ).
Modifiers: None.
Visibility: public pure.
Detailed Information:
It calculates
𝑒
yes
/
𝑏
e
yes/b
  and
𝑒
no
/
𝑏
e
no/b
 .
Divides the exponential result by the total to compute the odds.
Notes: Correct implementation; adheres to the description in comments.
Potential Vulnerabilities: Reverts if the input exceeds safe limits; handled explicitly in _getExponentials.
Function: getCost

Purpose: Calculates the cost difference for a trade (incremental cost).
Returns: Incremental cost as an integer (difference between old and new costs).
Modifiers: None.
Visibility: public pure.
Detailed Information:
Uses _cost to compute the LMSR cost formula for both states.
Subtracts old cost from new cost.
Potential Vulnerabilities: Handles large values safely due to the fixed-point math library.
Function: _cost

Purpose: Implements the LMSR cost formula
𝑏
⋅
ln
⁡
(
𝑒
yes
/
𝑏
+
𝑒
no
/
𝑏
)
b⋅ln(e
yes/b
 +e
no/b
 ).
Returns: Cost value (scaled by
1
0
18
10
18
 ).
Modifiers: None.
Visibility: public pure.
Detailed Information:
Computes exponentials for both states, sums them, and calculates the logarithm.
Multiplies the result by the liquidity parameter
𝑏
b.
Potential Vulnerabilities: None identified.
Function: _getExponentials

Purpose: Computes
𝑒
yes
/
𝑏
e
yes/b
  and
𝑒
no
/
𝑏
e
no/b
 .
Returns: Exponential values for both "yes" and "no" votes.
Modifiers: None.
Visibility: public pure.
Detailed Information:
Validates vote counts against the safe limit (
133
×
𝑏
133×b).
Uses the exp function from the fixed-point library.
Potential Vulnerabilities: Properly validates input; no vulnerabilities.
Contract: ReputationMarket
Function: createMarket

Purpose: Simplified wrapper to create a market with the default configuration.
Returns: None.
Modifiers: whenNotPaused.
Visibility: public payable.
Detailed Information:
Delegates the creation process to createMarketWithConfig using the default configuration.
Potential Vulnerabilities: Proper validation required for profile eligibility and balance.
Function: createMarketWithConfig

Purpose: Creates a new market for a profile using the specified configuration.
Returns: None.
Modifiers: whenNotPaused.
Visibility: public payable.
Detailed Information:
Validates the user’s ability to create a market.
Deducts ETH for creation cost and sets up market parameters.
Potential Vulnerabilities:
Ensure proper handling of msg.value for refunds.
Admins bypass certain checks (acceptable per logic).
Function: addMarketConfig

Purpose: Adds a new market configuration option.
Returns: The index of the new configuration.
Modifiers: onlyAdmin, whenNotPaused.
Visibility: public.
Detailed Information:
Validates inputs for liquidity and base price.
Appends the new configuration to the list.
Potential Vulnerabilities: None identified.
Function: buyVotes

Purpose: Allows participants to purchase votes in a market.
Returns: None.
Modifiers: whenNotPaused, activeMarket.
Visibility: public payable.
Detailed Information:
Calculates costs, updates vote counts, and handles funds distribution.
Potential Vulnerabilities:
Ensure accurate fee and donation calculation.
Validate edge cases for vote purchase amounts.
Function: sellVotes

Purpose: Allows participants to sell votes in a market.
Returns: None.
Modifiers: whenNotPaused, activeMarket.
Visibility: public.
Detailed Information:
Computes sale proceeds, deducts fees, and updates vote counts.
Potential Vulnerabilities:
Ensure precision in proceeds calculation.
Handle edge cases for minimal vote sales.
Function: graduateMarket

Purpose: Marks a market as graduated, making it inactive.
Returns: None.
Modifiers: whenNotPaused, activeMarket.
Visibility: public.
Detailed Information:
Ensures only authorized contracts can perform this action.
Potential Vulnerabilities: Ensure the authorizedAddress logic is secure.
Function: withdrawDonations

Purpose: Allows donation recipients to withdraw accumulated funds.
Returns: Amount withdrawn.
Modifiers: whenNotPaused, nonReentrant.
Visibility: public.
Detailed Information:
Transfers escrowed donations to the recipient.
Potential Vulnerabilities:
Reentrancy attacks mitigated by nonReentrant.
