// SPDX-License-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title Escrow
/// @notice A decentralized escrow system for secure peer-to-peer transactions
contract Escrow is ReentrancyGuard {
    /// @notice Struct to store escrow details
    struct EscrowDetails {
        address buyer;
        address seller;
        address arbiter;
        uint256 amount;
        uint256 deadline;
        string description;
        Status status;
        bool isDisputed;
    }

    /// @notice Enum to represent escrow status
    enum Status { Created, Funded, Released, Refunded, Disputed }

    /// @notice Mapping to store escrow details by ID
    mapping(uint256 => EscrowDetails) public escrows;

    /// @notice Counter for generating unique escrow IDs
    uint256 private nextEscrowId;

    /// @notice Event emitted when an escrow is created
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        address arbiter,
        uint256 amount,
        uint256 deadline,
        string description
    );

    /// @notice Event emitted when an escrow is funded
    event EscrowFunded(uint256 indexed escrowId, uint256 amount);

    /// @notice Event emitted when funds are released to the seller
    event FundsReleased(uint256 indexed escrowId, uint256 amount);

    /// @notice Event emitted when a refund is requested
    event RefundRequested(uint256 indexed escrowId);

    /// @notice Modifier to restrict access to the buyer of an escrow
    modifier onlyBuyer(uint256 escrowId) {
        require(msg.sender == escrows[escrowId].buyer, "Only buyer allowed");
        _;
    }

    /// @notice Modifier to restrict access to the seller of an escrow
    modifier onlySeller(uint256 escrowId) {
        require(msg.sender == escrows[escrowId].seller, "Only seller allowed");
        _;
    }

    /// @notice Modifier to restrict access to the arbiter of an escrow
    modifier onlyArbiter(uint256 escrowId) {
        require(msg.sender == escrows[escrowId].arbiter, "Only arbiter allowed");
        _;
    }

    /// @notice Creates a new escrow agreement
    /// @param seller The address of the seller
    /// @param arbiter The address of the arbiter
    /// @param amount The escrow amount in wei
    /// @param deadline The deadline timestamp for the escrow
    /// @param description A description of the escrow agreement
    /// @return escrowId The unique ID of the created escrow
    function createEscrow(
        address seller,
        address arbiter,
        uint256 amount,
        uint256 deadline,
        string memory description
    ) external returns (uint256 escrowId) {
        require(seller != address(0), "Invalid seller address");
        require(arbiter != address(0), "Invalid arbiter address");
        require(msg.sender != seller, "Buyer cannot be seller");
        require(msg.sender != arbiter, "Buyer cannot be arbiter");
        require(seller != arbiter, "Seller cannot be arbiter");
        require(amount > 0, "Amount must be greater than zero");
        require(deadline > block.timestamp, "Deadline must be in the future");

        escrowId = nextEscrowId++;
        escrows[escrowId] = EscrowDetails({
            buyer: msg.sender,
            seller: seller,
            arbiter: arbiter,
            amount: amount,
            deadline: deadline,
            description: description,
            status: Status.Created,
            isDisputed: false
        });

        emit EscrowCreated(escrowId, msg.sender, seller, arbiter, amount, deadline, description);
        return escrowId;
    }

    /// @notice Funds an existing escrow with the agreed amount
    /// @param escrowId The ID of the escrow to fund
    function fundEscrow(uint256 escrowId) external payable onlyBuyer(escrowId) nonReentrant {
        EscrowDetails storage escrow = escrows[escrowId];
        require(escrow.buyer != address(0), "Escrow does not exist");
        require(escrow.status == Status.Created, "Escrow must be in Created state");
        require(msg.value == escrow.amount, "Incorrect amount sent");
        require(block.timestamp <= escrow.deadline, "Escrow deadline has passed");

        escrow.status = Status.Funded;
        emit EscrowFunded(escrowId, msg.value);
    }

    /// @notice Releases funds to the seller
    /// @param escrowId The ID of the escrow to release funds from
    function releaseFunds(uint256 escrowId) external onlySeller(escrowId) nonReentrant {
        EscrowDetails storage escrow = escrows[escrowId];
        require(escrow.buyer != address(0), "Escrow does not exist");
        require(escrow.status == Status.Funded, "Escrow must be in Funded state");
        require(!escrow.isDisputed, "Escrow is in dispute");

        uint256 amount = escrow.amount;
        escrow.status = Status.Released;
        escrow.amount = 0; 

        (bool success, ) = escrow.seller.call{value: amount}("");
        require(success, "Transfer to seller failed");

        emit FundsReleased(escrowId, amount);
    }

    /// @notice Requests a refund for an escrow, marking it as disputed
    /// @param escrowId The ID of the escrow to request a refund for
    function requestRefund(uint256 escrowId) external onlyBuyer(escrowId) {
        EscrowDetails storage escrow = escrows[escrowId];
        require(escrow.buyer != address(0), "Escrow does not exist");
        require(escrow.status == Status.Funded, "Escrow must be in Funded state");
        require(block.timestamp > escrow.deadline, "Deadline not yet passed");

        escrow.status = Status.Disputed;
        escrow.isDisputed = true;
        emit RefundRequested(escrowId);
    }
}