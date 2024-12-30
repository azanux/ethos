// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "../../contracts/EthosVouch.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/utils/ContractAddressManager.sol";
import "../../contracts/utils/SignatureVerifier.sol";
import "../../contracts/EthosProfile.sol";

contract EthosVouchTest is Test {
    EthosVouch private ethosVouch;
    ERC1967Proxy private proxy;
    ContractAddressManager private contractAddressManager;
    SignatureVerifier private signatureVerifier;
    EthosProfile ethosProfile;

    address private OWNER = address(0x123);
    address private ADMIN = address(0x456);
    address private EXPECTED_SIGNER = address(0x789);
    address private FEE_PROTOCOL_ACC = address(0xABC);
    address private SLASHER = address(0x321);
    address private USER = address(0xDEF);
    address private USER1 = address(0xDEA);
    address private USER2 = address(0xDEB);

    address private SUBJECT = address(0xABC);
    address private SUBJECT1 = address(0xABD);
    address private SUBJECT2 = address(0xABF);

    address private MOCK_PROFILE = address(0x111);
    address private WRONG_ADDRESS_0 = address(0x111);
    address private PROFILE_CREATOR_0 = address(0x222);
    address private PROFILE_CREATOR_1 = address(0x333);
    address private VOUCHER_0 = address(0x444);
    address private VOUCHER_1 = address(0x555);
    uint256 private constant MINIMUM_VOUCH_AMOUNT = 0.0001 ether;

    function setUp() public {
        // Deploy supporting contracts
        vm.prank(OWNER);
        contractAddressManager = new ContractAddressManager();

        vm.prank(OWNER);
        signatureVerifier = new SignatureVerifier();

        // Deploy EthosVouch implementation
        vm.prank(OWNER);
        EthosVouch ethosVouchImpl = new EthosVouch();

        // Create proxy and initialize EthosVouch
        bytes memory initData = abi.encodeWithSelector(
            ethosVouchImpl.initialize.selector,
            OWNER,
            ADMIN,
            EXPECTED_SIGNER,
            address(signatureVerifier), // Mock Signature Verifier
            address(contractAddressManager), // Mock ContractAddressManager
            FEE_PROTOCOL_ACC,
            100, // Entry protocol fee basis points (1%)
            200, // Entry donation fee basis points (2%)
            300, // Entry vouchers pool fee basis points (1%)
            50 // Exit fee basis points (0.5%)
        );

        vm.prank(OWNER);
        proxy = new ERC1967Proxy(address(ethosVouchImpl), initData);

        // Attach proxy to EthosVouch ABI
        ethosVouch = EthosVouch(address(proxy));

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
        vm.deal(USER, 10 ether); // Add ETH to USER for testing
        vm.deal(USER1, 10 ether); // Add ETH to USER for testing
        vm.deal(USER2, 10 ether); // Add ETH to USER for testing
        // Simulation de fonds pour les adresses
        vm.deal(VOUCHER_0, 5 ether);
        vm.deal(VOUCHER_1, 5 ether);
    }

    // --- Initialization Tests ---
    function testInitialization() public {
        assertEq(ethosVouch.entryProtocolFeeBasisPoints(), 100, "Incorrect entry protocol fee");
        assertEq(ethosVouch.entryDonationFeeBasisPoints(), 200, "Incorrect entry donation fee");
        assertEq(ethosVouch.entryVouchersPoolFeeBasisPoints(), 300, "Incorrect voucher pool fee");
        assertEq(ethosVouch.exitFeeBasisPoints(), 50, "Incorrect exit fee");
        assertEq(ethosVouch.protocolFeeAddress(), FEE_PROTOCOL_ACC, "Incorrect protocol fee address");
        assertEq(ethosVouch.expectedSigner(), EXPECTED_SIGNER, "Incorrect expected signer");
        assertEq(ethosVouch.signatureVerifier(), address(signatureVerifier), "Incorrect signature verifier");
        assertEq(ethosVouch.configuredMinimumVouchAmount(), MINIMUM_VOUCH_AMOUNT, "Incorrect minimum voucher amount");
        assertEq(ethosVouch.unhealthyResponsePeriod(), 24 hours, "Incorrect unhealthy response period");
        assertEq(ethosVouch.maximumVouches(), 256, "Incorrect minimum voucher");
    }

    function testCheckContractAddressManager() public {
        assertEq(
            contractAddressManager.getContractAddressForName("ETHOS_PROFILE"),
            address(ethosProfile),
            "Incorrect contract address"
        );
    }

    // --- Upgradeability Tests ---
    function testUpgradeNotByOwner() public {
        vm.startPrank(ADMIN);
        vm.expectRevert();
        ethosVouch.upgradeToAndCall(address(0x456), bytes(""));
        vm.stopPrank();
    }

    function testUpgradeByOnwer() public {
        vm.prank(ADMIN);
        ethosVouch.updateUnhealthyResponsePeriod(360);

        vm.prank(ADMIN);
        ethosVouch.updateMaximumVouches(100);

        vm.prank(ADMIN);
        ethosVouch.setMinimumVouchAmount(0.1 ether);

        assertEq(ethosVouch.unhealthyResponsePeriod(), 360, "Incorrect unhealthy period");
        assertEq(ethosVouch.maximumVouches(), 100, "Incorrect minimum voucher");
        assertEq(ethosVouch.configuredMinimumVouchAmount(), 0.1 ether, "Incorrect minimum voucher amount");
        // Deploy EthosVouch implementation
        vm.prank(ADMIN);
        EthosVouch ethosVouchImpl = new EthosVouch();

        vm.startPrank(OWNER);
        ethosVouch.upgradeToAndCall(address(ethosVouchImpl), bytes(""));
        vm.stopPrank();

        assertEq(ethosVouch.entryProtocolFeeBasisPoints(), 100, "Incorrect entry protocol fee");
        assertEq(ethosVouch.entryDonationFeeBasisPoints(), 200, "Incorrect entry donation fee");
        assertEq(ethosVouch.entryVouchersPoolFeeBasisPoints(), 300, "Incorrect voucher pool fee");
        assertEq(ethosVouch.exitFeeBasisPoints(), 50, "Incorrect exit fee");
        assertEq(ethosVouch.protocolFeeAddress(), FEE_PROTOCOL_ACC, "Incorrect protocol fee address");
        assertEq(ethosVouch.expectedSigner(), EXPECTED_SIGNER, "Incorrect expected signer");
        assertEq(ethosVouch.signatureVerifier(), address(signatureVerifier), "Incorrect signature verifier");

        assertEq(ethosVouch.hasRole(ethosVouch.OWNER_ROLE(), OWNER), true, "Owner role mismatch");

        assertEq(ethosVouch.configuredMinimumVouchAmount(), 0.1 ether, "Incorrect minimum voucher amount");
        assertEq(ethosVouch.unhealthyResponsePeriod(), 360, "Incorrect unhealthy period");
        assertEq(ethosVouch.maximumVouches(), 100, "Incorrect minimum voucher");
    }

    function testUpgradeWithZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        ethosVouch.upgradeToAndCall(address(0), bytes(""));
        vm.stopPrank();
    }

    // --- Vouching Tests ---

    function testVouchById() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(PROFILE_CREATOR_0);
        ethosProfile.inviteAddress(PROFILE_CREATOR_1);
        ethosProfile.inviteAddress(SUBJECT);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);

        vm.prank(PROFILE_CREATOR_0);
        ethosProfile.createProfile(1);

        vm.prank(PROFILE_CREATOR_1);
        ethosProfile.createProfile(1);

        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);

        vm.stopPrank();

        vm.startPrank(USER);
        ethosVouch.vouchByProfileId{value: 1 ether}(5, "Valid comment", "Metadata");
        vm.stopPrank();

        uint256 vouchId = ethosVouch.vouchCount() - 1;
        assertEq(vouchId, 0, "vouchID mismatch");
        //EthosVouch.Vouch memory vouch = ethosVouch.vouches(vouchId);
        //assertEq(vouch.authorAddress, OWNER, "Author mismatch");
        //assertEq(vouch.comment, "Valid comment", "Comment mismatch");
    }

    function testVouchByAddress() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(PROFILE_CREATOR_0);
        ethosProfile.inviteAddress(PROFILE_CREATOR_1);
        ethosProfile.inviteAddress(SUBJECT);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);

        vm.prank(PROFILE_CREATOR_0);
        ethosProfile.createProfile(1);

        vm.prank(PROFILE_CREATOR_1);
        ethosProfile.createProfile(1);

        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);

        vm.stopPrank();

        vm.startPrank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT, "Valid comment", "Metadata");
        vm.stopPrank();

        uint256 vouchId = ethosVouch.vouchCount() - 1;
        assertEq(vouchId, 0, "vouchID mismatch");
        //EthosVouch.Vouch memory vouch = ethosVouch.vouches(vouchId);
        //assertEq(vouch.authorAddress, OWNER, "Author mismatch");
        //assertEq(vouch.comment, "Valid comment", "Comment mismatch");
    }

    function testVouchRevertsOnInvalidProfile() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        ethosVouch.vouchByAddress{value: MINIMUM_VOUCH_AMOUNT}(
            address(0), // Invalid profile
            "Invalid comment",
            "Invalid metadata"
        );
        vm.stopPrank();
    }

    function testSelfVouchReverts() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        ethosVouch.vouchByAddress{value: MINIMUM_VOUCH_AMOUNT}(
            OWNER, // Self-vouch
            "Invalid comment",
            "Invalid metadata"
        );
        vm.stopPrank();
    }

    function testVouchRevertsOnInsufficientAmount() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(SUBJECT);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);
        vm.stopPrank();

        vm.startPrank(USER);
        vm.expectRevert();
        ethosVouch.vouchByAddress{value: MINIMUM_VOUCH_AMOUNT - 1}(SUBJECT, "Comment", "Metadata");
        vm.stopPrank();
    }

    // --- Unvouch Tests ---
    function testUnvouchWork() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(SUBJECT);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT, "Comment", "Metadata");

        uint256 vouchId = ethosVouch.vouchCount() - 1;
        printVouch(vouchId);

        vm.prank(USER);
        ethosVouch.unvouch(vouchId);
        printVouch(vouchId);

        //EthosVouch.Vouch memory vouch = ethosVouch.vouches(vouchId);
        //assertTrue(vouch.archived, "Vouch should be archived");
    }

    // --- Unvouch Tests ---
    function testUnvouchWorkUnhealthy() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(SUBJECT);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT, "Comment", "Metadata");

        uint256 vouchId = ethosVouch.vouchCount() - 1;
        printVouch(vouchId);

        vm.prank(USER);
        ethosVouch.unvouchUnhealthy(vouchId);
        printVouch(vouchId);

        //EthosVouch.Vouch memory vouch = ethosVouch.vouches(vouchId);
        //assertTrue(vouch.archived, "Vouch should be archived");
    }

    function testUnvouchRevertsIfNotAuthor() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(SUBJECT);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT, "Comment", "Metadata");

        uint256 vouchId = ethosVouch.vouchCount() - 1;
        printVouch(vouchId);

        vm.prank(OWNER);
        vm.expectRevert();
        ethosVouch.unvouch(vouchId);
        printVouch(vouchId);
    }

    function testUnvouchFailsIfAlreadyUnvouchedBis() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(SUBJECT);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT, "Comment", "Metadata");

        uint256 vouchId = ethosVouch.vouchCount() - 1;
        printVouch(vouchId);

        vm.prank(USER);
        ethosVouch.unvouch(vouchId);

        vm.prank(USER);
        vm.expectRevert();
        ethosVouch.unvouch(vouchId);
        printVouch(vouchId);
    }

    // --- Fee Tests ---
    function testProtocolFeeDistribution() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(SUBJECT);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);

        uint256 initialFeeBalance = address(FEE_PROTOCOL_ACC).balance;

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT, "Comment", "Metadata");

        uint256 expectedFee = (1 ether * 100) / 10000; // 1% protocol fee
        uint256 newFeeBalance = address(FEE_PROTOCOL_ACC).balance;
    }

    // --- Slashing Tests ---
    function testSlashReducesBalance() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(SUBJECT);
        ethosProfile.inviteAddress(SUBJECT1);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT1);
        ethosProfile.createProfile(1);

        uint256 initialFeeBalance = address(FEE_PROTOCOL_ACC).balance;

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT, "Comment", "Metadata");

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT1, "Comment", "Metadata");

        uint256 vouchId = ethosVouch.vouchCount() - 1;
        //uint256 initialBalance = 0;
        uint256 initialBalance = getBalanceVouch(vouchId) + getBalanceVouch(vouchId - 1);

        vm.prank(SLASHER);
        uint256 slashAmount = ethosVouch.slash(2, 500); // Slash 5%

        uint256 newBalance = getBalanceVouch(vouchId) + getBalanceVouch(vouchId - 1);

        console.log("Slash amount: ", slashAmount);
        console.log("Initial balance: ", initialBalance);
        console.log("New balance: ", newBalance);
        console.log("Slash amount", initialBalance - newBalance);
        console.log("new balance calculate", (initialBalance * 95) / 100);

        assertEq(newBalance, 2 + (initialBalance * 95) / 100, "Slash calculation mismatch");
    }

    function testSlashRevertsIfNotSlasher() public {
        vm.startPrank(OWNER);
        // Invite users
        ethosProfile.inviteAddress(USER);
        ethosProfile.inviteAddress(SUBJECT);
        ethosProfile.inviteAddress(SUBJECT1);
        vm.stopPrank();

        // Create profiles
        vm.prank(USER);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT);
        ethosProfile.createProfile(1);
        vm.prank(SUBJECT1);
        ethosProfile.createProfile(1);

        uint256 initialFeeBalance = address(FEE_PROTOCOL_ACC).balance;

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT, "Comment", "Metadata");

        vm.prank(USER);
        ethosVouch.vouchByAddress{value: 1 ether}(SUBJECT1, "Comment", "Metadata");

        uint256 vouchId = ethosVouch.vouchCount() - 1;
        //uint256 initialBalance = 0;
        uint256 initialBalance = getBalanceVouch(vouchId) + getBalanceVouch(vouchId - 1);

        vm.prank(OWNER);
        vm.expectRevert();
        uint256 slashAmount = ethosVouch.slash(2, 500); // Slash 5%

        uint256 newBalance = getBalanceVouch(vouchId) + getBalanceVouch(vouchId - 1);
    }

    // Test: Mise à jour de la période d'inactivité
    function testUpdateUnhealthyResponsePeriod() public {
        vm.startPrank(ADMIN);
        ethosVouch.updateUnhealthyResponsePeriod(3600);
        assertEq(ethosVouch.unhealthyResponsePeriod(), 3600, "Incorrect unhealthy period");
        vm.stopPrank();
    }

    function testConstructorSetsCorrectInitialParams() public {
        assertEq(ethosVouch.hasRole(ethosVouch.OWNER_ROLE(), OWNER), true, "admin incorrect");
        assertEq(ethosVouch.hasRole(ethosVouch.ADMIN_ROLE(), ADMIN), true, "Administrateur incorrect");
        assertEq(ethosVouch.expectedSigner(), EXPECTED_SIGNER, "expectedSigner incorrect");
        assertEq(address(ethosVouch.signatureVerifier()), address(signatureVerifier), "SignatureVerifier incorrect");
        assertEq(ethosVouch.unhealthyResponsePeriod(), 24 hours, "unhealthyResponsePeriod incorrect");
    }

    function printVouch(uint256 vouchId) public {
        (
            bool archived,
            bool unhealthy,
            uint256 authorProfileId,
            address authorAddress,
            uint256 vouchId,
            uint256 subjectProfileId,
            uint256 balance,
            string memory comment,
            string memory metadata,
        ) = ethosVouch.vouches(vouchId);

        console.log("Vouch ID: ", vouchId);
        console.log("Archived: ", archived);
        console.log("Unhealthy: ", unhealthy);
        console.log("Author Profile ID: ", authorProfileId);
        console.log("Author Address: ", authorAddress);
        console.log("Subject Profile ID: ", subjectProfileId);
        console.log("Balance: ", balance);
        console.log("Comment: ", comment);
        console.log("Metadata: ", metadata);
    }

    function getBalanceVouch(uint256 vouchId) public returns (uint256) {
        (
            bool archived,
            bool unhealthy,
            uint256 authorProfileId,
            address authorAddress,
            uint256 vouchId,
            uint256 subjectProfileId,
            uint256 balance,
            string memory comment,
            string memory metadata,
        ) = ethosVouch.vouches(vouchId);

        return balance;
    }
}
