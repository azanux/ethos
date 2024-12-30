// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { ReputationMarket } from "../../contracts/ReputationMarket.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/utils/ContractAddressManager.sol";
import "../../contracts/utils/SignatureVerifier.sol";
import "../../contracts/EthosProfile.sol";

contract ReputationMarketTest is Test {
  ReputationMarket private reputationMarket;
  ERC1967Proxy private proxy;

  ContractAddressManager private contractAddressManager;
  SignatureVerifier private signatureVerifier;
  EthosProfile ethosProfile;

  address private OWNER = address(0x123);
  address private ADMIN = address(0x456);
  address private USER = address(0x789);
  address private USER_A = address(0x780);
  address private USER_B = address(0xABC);
  address private DONATION_RECEIVER = address(0xDEF);

  address private EXPECTED_SIGNER = address(0x999);
  address private FEE_PROTOCOL_ACC = address(0x888);
  address private SLASHER = address(0x777);

  uint256 private constant BASE_PRICE = 0.01 ether;
  uint256 private constant CREATION_COST = 0.2 ether;

  function setUp() public {
    // Deploy supporting contracts
    vm.prank(OWNER);
    contractAddressManager = new ContractAddressManager();

    vm.prank(OWNER);
    signatureVerifier = new SignatureVerifier();

    vm.startPrank(OWNER);

    ReputationMarket marketImpl = new ReputationMarket();

    bytes memory initData = abi.encodeWithSelector(
      marketImpl.initialize.selector,
      OWNER,
      ADMIN,
      EXPECTED_SIGNER,
      address(signatureVerifier), // Mock Signature Verifier
      address(contractAddressManager) // Mock ContractAddressManager
    );

    vm.stopPrank();

    proxy = new ERC1967Proxy(address(marketImpl), initData);
    reputationMarket = ReputationMarket(address(proxy));

    vm.prank(OWNER);
    EthosProfile profileImplementation = new EthosProfile();
    ERC1967Proxy profileProxy = new ERC1967Proxy(
      address(profileImplementation),
      abi.encodeWithSelector(
        EthosProfile.initialize.selector,
        OWNER,
        ADMIN,
        EXPECTED_SIGNER,
        address(signatureVerifier), // Mock Signature Verifier
        address(contractAddressManager) // Mock ContractAddressManager
      )
    );
    ethosProfile = EthosProfile(address(profileProxy));

    vm.stopPrank();

    vm.startPrank(ADMIN);
    reputationMarket.setAllowListEnforcement(false);
    reputationMarket.setProtocolFeeAddress(FEE_PROTOCOL_ACC);
    reputationMarket.setEntryProtocolFeeBasisPoints(200); // 1%
    reputationMarket.setExitProtocolFeeBasisPoints(100); // 1%
    vm.stopPrank();

    //Update contract address manager and name
    address[] memory contractAddresses = new address[](2);
    string[] memory names = new string[](2);
    contractAddresses[0] = address(ethosProfile);
    contractAddresses[1] = SLASHER;
    names[0] = "ETHOS_PROFILE";
    names[1] = "SLASHER";

    vm.prank(OWNER);
    contractAddressManager.updateContractAddressesForNames(contractAddresses, names);

    vm.deal(OWNER, 10 ether); // Add ETH to OWNER for testing
    vm.deal(ADMIN, 10 ether); // Add ETH to OWNER for testing
    vm.deal(USER, 10 ether); // Add ETH to USER for testing
    vm.deal(USER_A, 10 ether); // Add ETH to USER for testing
    vm.deal(USER_B, 10 ether); // Add ETH to USER for testing
  }

  function test_implementation() public {
    console.log("ReputationMarket implementation address: %s", address(reputationMarket));

    //check protocol fee
    assertEq(reputationMarket.entryProtocolFeeBasisPoints(), 200);
    assertEq(reputationMarket.exitProtocolFeeBasisPoints(), 100);
  }

  // --- Upgradeability Tests ---
  function testUpgradeNotByOwner() public {
    vm.startPrank(ADMIN);
    vm.expectRevert();
    reputationMarket.upgradeToAndCall(address(0x456), bytes(""));
    vm.stopPrank();

    //check protocol fee
    assertEq(reputationMarket.entryProtocolFeeBasisPoints(), 200);
    assertEq(reputationMarket.exitProtocolFeeBasisPoints(), 100);
  }

  function testUpgradeWithZeroAddress() public {
    vm.startPrank(OWNER);
    vm.expectRevert();
    reputationMarket.upgradeToAndCall(address(0), bytes(""));
    vm.stopPrank();

    //check protocol fee
    assertEq(reputationMarket.entryProtocolFeeBasisPoints(), 200);
    assertEq(reputationMarket.exitProtocolFeeBasisPoints(), 100);
  }

  function testUpgradeReputationByOnwer() public {
    vm.startPrank(ADMIN);
    reputationMarket.setAllowListEnforcement(false);
    reputationMarket.setProtocolFeeAddress(FEE_PROTOCOL_ACC);
    reputationMarket.setEntryProtocolFeeBasisPoints(300); // 5%
    reputationMarket.setExitProtocolFeeBasisPoints(400); // 5%
    vm.stopPrank();

    assertEq(reputationMarket.entryProtocolFeeBasisPoints(), 300);
    assertEq(reputationMarket.exitProtocolFeeBasisPoints(), 400);

    vm.startPrank(OWNER);

    ReputationMarket marketImpl = new ReputationMarket();

    vm.stopPrank();

    vm.startPrank(OWNER);
    reputationMarket.upgradeToAndCall(address(marketImpl), bytes(""));
    vm.stopPrank();

    //check protocol fee
    assertEq(reputationMarket.entryProtocolFeeBasisPoints(), 300);
    assertEq(reputationMarket.exitProtocolFeeBasisPoints(), 400);
  }

  function testMarketCreation() public {
    vm.startPrank(OWNER);
    // Invite users
    ethosProfile.inviteAddress(USER);
    ethosProfile.inviteAddress(USER_A);
    ethosProfile.inviteAddress(USER_B);
    vm.stopPrank();

    // Create profiles
    vm.prank(USER);
    ethosProfile.createProfile(1);

    vm.prank(USER_A);
    ethosProfile.createProfile(1);

    vm.prank(USER_B);
    ethosProfile.createProfile(1);

    vm.stopPrank();

    vm.prank(USER_A);
    reputationMarket.createMarket{ value: 1 ether }();

    vm.prank(USER_B);
    reputationMarket.createMarket{ value: CREATION_COST }();

    vm.prank(ADMIN);
    reputationMarket.createMarketWithConfigAdmin{ value: CREATION_COST }(USER, 1);

    printMarket(2);
    printMarket(3);
    printMarket(4);
  }

  function testMarketAllowedCreation() public {
    vm.startPrank(OWNER);
    // Invite users
    ethosProfile.inviteAddress(USER);
    ethosProfile.inviteAddress(USER_A);
    ethosProfile.inviteAddress(USER_B);
    vm.stopPrank();

    // Create profiles
    vm.prank(USER);
    ethosProfile.createProfile(1);

    vm.prank(USER_A);
    ethosProfile.createProfile(1);

    vm.prank(USER_B);
    ethosProfile.createProfile(1);

    vm.stopPrank();

    vm.prank(ADMIN);
    reputationMarket.setAllowListEnforcement(true);

    vm.prank(ADMIN);
    reputationMarket.setUserAllowedToCreateMarket(2, true);

    vm.prank(USER);
    reputationMarket.createMarket{ value: CREATION_COST }();

    vm.prank(USER_A);
    reputationMarket.createMarket{ value: 0.0001 ether }();

    vm.prank(USER_B);
    reputationMarket.createMarket{ value: CREATION_COST }();

    printMarket(2);
    printMarket(3);
    printMarket(4);
  }

  function printMarket(uint256 profileId) public {
    ReputationMarket.MarketInfo memory marketInfo = reputationMarket.getMarket(profileId);
  }
}
