// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";

contract EscrowTest is Test {
    Escrow escrow;
    address buyer = address(0x1);
    address seller = address(0x2);
    address arbiter = address(0x3);
    uint256 constant AMOUNT = 1 ether;
    uint256 constant DEADLINE = 1 days;

    // Events for testing
    event EscrowCreated(uint256 indexed escrowId, address indexed buyer, address indexed seller, address arbiter, uint256 amount, uint256 deadline, string description);
    event EscrowFunded(uint256 indexed escrowId, uint256 amount);
    event FundsReleased(uint256 indexed escrowId, uint256 amount);
    event RefundRequested(uint256 indexed escrowId);
    event DisputeResolved(uint256 indexed escrowId, bool releasedToSeller);

    function setUp() public {
        escrow = new Escrow();
        vm.deal(buyer, 10 ether);
    }

    // Helper function to create and return escrow ID
    function createEscrow() internal returns (uint256) {
        vm.prank(buyer);
        return escrow.createEscrow(seller, arbiter, AMOUNT, block.timestamp + DEADLINE, "Test Escrow");
    }

    // Helper function to create and fund escrow
    function createAndFundEscrow() internal returns (uint256) {
        uint256 escrowId = createEscrow();
        vm.prank(buyer);
        escrow.fundEscrow{value: AMOUNT}(escrowId);
        return escrowId;
    }

    // Helper function to create, fund, and dispute escrow
    function createFundAndDisputeEscrow() internal returns (uint256) {
        uint256 escrowId = createAndFundEscrow();
        vm.warp(block.timestamp + DEADLINE + 1);
        vm.prank(buyer);
        escrow.requestRefund(escrowId);
        return escrowId;
    }

    // Helper function to get escrow status
    function getEscrowStatus(uint256 escrowId) internal view returns (Escrow.Status) {
        (,,,,,, Escrow.Status status,) = escrow.escrows(escrowId);
        return status;
    }

    // Tests for createEscrow
    function test_CreateEscrow_Success() public {
        uint256 escrowId = createEscrow();
        (address buyer_, address seller_, address arbiter_, uint256 amount_,, string memory description_, Escrow.Status status_, bool isDisputed_) = escrow.escrows(escrowId);
        
        assertEq(buyer_, buyer);
        assertEq(seller_, seller);
        assertEq(arbiter_, arbiter);
        assertEq(amount_, AMOUNT);
        assertEq(description_, "Test Escrow");
        assertEq(uint(status_), uint(Escrow.Status.Created));
        assertFalse(isDisputed_);
    }

    function test_CreateEscrow_EmitsEvent() public {
        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit EscrowCreated(0, buyer, seller, arbiter, AMOUNT, block.timestamp + DEADLINE, "Test Escrow");
        escrow.createEscrow(seller, arbiter, AMOUNT, block.timestamp + DEADLINE, "Test Escrow");
    }

    function test_CreateEscrow_InvalidInputs() public {
        vm.startPrank(buyer);
        vm.expectRevert("Invalid seller address");
        escrow.createEscrow(address(0), arbiter, AMOUNT, block.timestamp + DEADLINE, "Test");
        
        vm.expectRevert("Invalid arbiter address");
        escrow.createEscrow(seller, address(0), AMOUNT, block.timestamp + DEADLINE, "Test");
        
        vm.expectRevert("Buyer cannot be seller");
        escrow.createEscrow(buyer, arbiter, AMOUNT, block.timestamp + DEADLINE, "Test");
        
        vm.expectRevert("Buyer cannot be arbiter");
        escrow.createEscrow(seller, buyer, AMOUNT, block.timestamp + DEADLINE, "Test");
        
        vm.expectRevert("Seller cannot be arbiter");
        escrow.createEscrow(seller, seller, AMOUNT, block.timestamp + DEADLINE, "Test");
        
        vm.expectRevert("Amount must be greater than zero");
        escrow.createEscrow(seller, arbiter, 0, block.timestamp + DEADLINE, "Test");
        
        vm.expectRevert("Deadline must be in the future");
        escrow.createEscrow(seller, arbiter, AMOUNT, block.timestamp - 1, "Test");
        vm.stopPrank();
    }

    // Tests for fundEscrow
    function test_FundEscrow_Success() public {
        uint256 escrowId = createEscrow();
        
        vm.prank(buyer);
        vm.expectEmit(true, false, false, true);
        emit EscrowFunded(escrowId, AMOUNT);
        escrow.fundEscrow{value: AMOUNT}(escrowId);

        assertEq(uint(getEscrowStatus(escrowId)), uint(Escrow.Status.Funded));
        assertEq(address(escrow).balance, AMOUNT);
    }

    function test_FundEscrow_Failures() public {
        uint256 escrowId = createEscrow();
        
        vm.prank(seller);
        vm.expectRevert("Only buyer allowed");
        escrow.fundEscrow{value: AMOUNT}(escrowId);

        vm.prank(buyer);
        vm.expectRevert("Escrow does not exist");
        escrow.fundEscrow{value: AMOUNT}(999);

        vm.prank(buyer);
        escrow.fundEscrow{value: AMOUNT}(escrowId);
        vm.expectRevert("Escrow must be in Created state");
        escrow.fundEscrow{value: AMOUNT}(escrowId);
    }

    function test_FundEscrow_IncorrectAmountAndDeadline() public {
        uint256 escrowId = createEscrow();
        
        vm.prank(buyer);
        vm.expectRevert("Incorrect amount sent");
        escrow.fundEscrow{value: AMOUNT - 1}(escrowId);

        vm.warp(block.timestamp + DEADLINE + 1);
        vm.prank(buyer);
        vm.expectRevert("Escrow deadline has passed");
        escrow.fundEscrow{value: AMOUNT}(escrowId);
    }

    // Tests for releaseFunds
    function test_ReleaseFunds_Success() public {
        uint256 escrowId = createAndFundEscrow();
        uint256 initialBalance = seller.balance;
        
        vm.prank(seller);
        vm.expectEmit(true, false, false, true);
        emit FundsReleased(escrowId, AMOUNT);
        escrow.releaseFunds(escrowId);

        assertEq(uint(getEscrowStatus(escrowId)), uint(Escrow.Status.Released));
        assertEq(address(escrow).balance, 0);
        assertEq(seller.balance, initialBalance + AMOUNT);
    }

    function test_ReleaseFunds_Failures() public {
        uint256 escrowId = createAndFundEscrow();
        
        vm.prank(buyer);
        vm.expectRevert("Only seller allowed");
        escrow.releaseFunds(escrowId);

        vm.prank(seller);
        vm.expectRevert("Escrow does not exist");
        escrow.releaseFunds(999);
        
        uint256 unfundedId = createEscrow();
        vm.prank(seller);
        vm.expectRevert("Escrow must be in Funded state");
        escrow.releaseFunds(unfundedId);
    }

    function test_ReleaseFunds_FailsWhenDisputed() public {
        uint256 escrowId = createAndFundEscrow();
        
        vm.warp(block.timestamp + DEADLINE + 1);
        vm.prank(buyer);
        escrow.requestRefund(escrowId);

        vm.prank(seller);
        vm.expectRevert("Escrow is in dispute");
        escrow.releaseFunds(escrowId);
    }

    // Tests for requestRefund
    function test_RequestRefund_Success() public {
        uint256 escrowId = createAndFundEscrow();

        vm.warp(block.timestamp + DEADLINE + 1);
        vm.prank(buyer);
        vm.expectEmit(true, false, false, true);
        emit RefundRequested(escrowId);
        escrow.requestRefund(escrowId);

        (
            address buyer_,
            address seller_,
            address arbiter_,
            uint256 amount_,
            uint256 deadline_,
            string memory description_,
            Escrow.Status status_,
            bool isDisputed_
        ) = escrow.escrows(escrowId);
        assertEq(uint(status_), uint(Escrow.Status.Disputed), "Status should be Disputed");
        assertTrue(isDisputed_, "Should be disputed");
        assertEq(amount_, AMOUNT, "Amount should remain unchanged");
        assertEq(address(escrow).balance, AMOUNT, "Contract balance should remain unchanged");
    }

    function test_RequestRefund_Failures() public {
        uint256 escrowId = createAndFundEscrow();

        vm.warp(block.timestamp + DEADLINE + 1);
        vm.prank(seller);
        vm.expectRevert("Only buyer allowed");
        escrow.requestRefund(escrowId);

        vm.prank(buyer);
        vm.expectRevert("Escrow does not exist");
        escrow.requestRefund(999);

        uint256 unfundedId = createEscrow();
        vm.warp(block.timestamp + DEADLINE + 1);
        vm.prank(buyer);
        vm.expectRevert("Escrow must be in Funded state");
        escrow.requestRefund(unfundedId);

        vm.prank(buyer);
        vm.warp(block.timestamp);
        vm.expectRevert("Deadline not yet passed");
        escrow.requestRefund(escrowId);
    }

    // Tests for resolveDispute
    function test_ResolveDispute_ReleaseToSeller() public {
        uint256 escrowId = createFundAndDisputeEscrow();
        uint256 initialSellerBalance = seller.balance;

        vm.prank(arbiter);
        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(escrowId, true);
        escrow.resolveDispute(escrowId, true);

        (
            address buyer_,
            address seller_,
            address arbiter_,
            uint256 amount_,
            ,, Escrow.Status status_,
            bool isDisputed_
        ) = escrow.escrows(escrowId);
        assertEq(uint(status_), uint(Escrow.Status.Released), "Status should be Released");
        assertFalse(isDisputed_, "Should not be disputed");
        assertEq(amount_, 0, "Amount should be zero");
        assertEq(address(escrow).balance, 0, "Contract balance should be zero");
        assertEq(seller.balance, initialSellerBalance + AMOUNT, "Seller balance mismatch");
    }

    function test_ResolveDispute_RefundToBuyer() public {
        uint256 escrowId = createFundAndDisputeEscrow();
        uint256 initialBuyerBalance = buyer.balance;

        vm.prank(arbiter);
        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(escrowId, false);
        escrow.resolveDispute(escrowId, false);

        (
            address buyer_,
            address seller_,
            address arbiter_,
            uint256 amount_,
            ,, Escrow.Status status_,
            bool isDisputed_
        ) = escrow.escrows(escrowId);
        assertEq(uint(status_), uint(Escrow.Status.Refunded), "Status should be Refunded");
        assertFalse(isDisputed_, "Should not be disputed");
        assertEq(amount_, 0, "Amount should be zero");
        assertEq(address(escrow).balance, 0, "Contract balance should be zero");
        assertEq(buyer.balance, initialBuyerBalance + AMOUNT, "Buyer balance mismatch");
    }

    function test_ResolveDispute_Failures() public {
        uint256 escrowId = createFundAndDisputeEscrow();

        vm.prank(buyer);
        vm.expectRevert("Only arbiter allowed");
        escrow.resolveDispute(escrowId, true);

        vm.prank(seller);
        vm.expectRevert("Only arbiter allowed");
        escrow.resolveDispute(escrowId, true);

        vm.prank(arbiter);
        vm.expectRevert("Escrow does not exist");
        escrow.resolveDispute(999, true);

        uint256 nonDisputedId = createAndFundEscrow();
        vm.prank(arbiter);
        vm.expectRevert("Escrow must be in Disputed state");
        escrow.resolveDispute(nonDisputedId, true);
    }
}