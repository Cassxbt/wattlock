// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ASCBase} from "@gluwa/asc-contracts/contracts/readability/ASCBase.sol";
import {EvmV1Decoder} from "@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol";
import {INativeQueryVerifier} from "@gluwa/asc-contracts/contracts/write-ability/common/INativeQueryVerifier.sol";

/// @notice Proof-gated, destination-chain settlement for one certificate-backed compute job.
/// @dev This contract verifies a proved Sepolia receipt via ASCBase, then validates the exact
/// CertificateReserved log before releasing a pre-funded CC3 test-CTC escrow.
contract WattLockASC is ASCBase, ReentrancyGuard {
    enum JobStatus {
        None,
        Funded,
        Settled,
        Reclaimed
    }

    struct Job {
        address buyer;
        address provider;
        uint128 reward;
        uint64 requiredEnergyWh;
        uint64 settlementDeadline;
        JobStatus status;
    }

    uint8 public constant SETTLE_ACTION = 0;
    bytes32 public constant ALLOCATION_DOMAIN = keccak256("WATTLOCK_V1");
    bytes32 public constant CERTIFICATE_RESERVED_EVENT_SIGNATURE =
        keccak256("CertificateReserved(bytes32,bytes32,address,bytes32,uint64,uint64,uint256)");

    address public immutable demoIssuer;
    uint64 public immutable expectedSourceChainKey;
    uint256 public immutable expectedSourceEvmChainId;

    bool internal settlementExecutionActive;

    mapping(bytes32 jobId => Job job) public jobs;
    mapping(bytes32 certificateId => bool consumed) public consumedCertificates;

    error InvalidAction();
    error InvalidJobId();
    error JobAlreadyExists();
    error JobDoesNotExist();
    error JobNotFunded();
    error JobAlreadySettled();
    error JobDeadlineInvalid();
    error JobDeadlinePassed();
    error InvalidProvider();
    error InvalidReward();
    error CertificateAlreadyConsumed();
    error CertificateExpiresBeforeSettlement();
    error CertificateOwnerMismatch();
    error EnergyMismatch();
    error AllocationCommitmentMismatch();
    error FailedSourceTransaction();
    error InvalidReservationEvent();
    error UntrustedSourceIssuer();
    error WrongSourceChain();
    error WrongSourceChainKey();
    error DirectExecutionDisabled();
    error PaymentFailed();
    error OnlyBuyer();

    event JobFunded(
        bytes32 indexed jobId,
        address indexed buyer,
        address indexed provider,
        uint128 reward,
        uint64 requiredEnergyWh,
        uint64 settlementDeadline
    );
    event JobSettled(
        bytes32 indexed jobId,
        bytes32 indexed certificateId,
        bytes32 indexed queryId,
        address provider,
        uint128 reward,
        bytes32 allocationHash
    );
    event JobReclaimed(bytes32 indexed jobId, address indexed buyer, uint128 reward);

    constructor(address issuer, uint64 sourceChainKey, uint256 sourceEvmChainId) {
        if (issuer == address(0)) revert UntrustedSourceIssuer();
        demoIssuer = issuer;
        expectedSourceChainKey = sourceChainKey;
        expectedSourceEvmChainId = sourceEvmChainId;
    }

    receive() external payable {}

    function openJob(bytes32 jobId, address provider, uint64 requiredEnergyWh, uint64 settlementDeadline)
        external
        payable
    {
        if (jobs[jobId].status != JobStatus.None) revert JobAlreadyExists();
        if (jobId == bytes32(0)) revert InvalidJobId();
        if (provider == address(0) || provider.code.length != 0) revert InvalidProvider();
        if (msg.value == 0 || msg.value > type(uint128).max) revert InvalidReward();
        if (requiredEnergyWh == 0) revert EnergyMismatch();
        if (settlementDeadline <= block.timestamp) revert JobDeadlineInvalid();

        jobs[jobId] = Job({
            buyer: msg.sender,
            provider: provider,
            reward: uint128(msg.value),
            requiredEnergyWh: requiredEnergyWh,
            settlementDeadline: settlementDeadline,
            status: JobStatus.Funded
        });

        emit JobFunded(jobId, msg.sender, provider, uint128(msg.value), requiredEnergyWh, settlementDeadline);
    }

    /// @notice Returns the exact commitment the source reservation must emit for a job.
    function allocationHashFor(bytes32 certificateId, bytes32 jobId) public view returns (bytes32) {
        Job storage job = jobs[jobId];
        if (job.status == JobStatus.None) revert JobDoesNotExist();

        return keccak256(
            abi.encode(
                ALLOCATION_DOMAIN,
                expectedSourceEvmChainId,
                demoIssuer,
                block.chainid,
                address(this),
                certificateId,
                jobId,
                job.buyer,
                job.provider,
                job.reward,
                job.requiredEnergyWh,
                job.settlementDeadline
            )
        );
    }

    function reclaimExpiredJob(bytes32 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.status == JobStatus.None) revert JobDoesNotExist();
        if (msg.sender != job.buyer) revert OnlyBuyer();
        if (job.status == JobStatus.Settled) revert JobAlreadySettled();
        if (job.status != JobStatus.Funded) revert JobNotFunded();
        if (block.timestamp <= job.settlementDeadline) revert JobDeadlineInvalid();

        job.status = JobStatus.Reclaimed;
        uint128 reward = job.reward;
        (bool paid,) = job.buyer.call{value: reward}("");
        if (!paid) revert PaymentFailed();

        emit JobReclaimed(jobId, job.buyer, reward);
    }

    /// @notice The only supported proof entry point. It pins Attestcoin to Sepolia's configured
    /// chain key before delegating proof verification to the official ASCBase implementation.
    function settleWithProof(
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
        bytes32 lowerEndpointDigest,
        bytes32[] calldata continuityRoots
    ) external returns (bool success) {
        if (chainKey != expectedSourceChainKey) revert WrongSourceChainKey();

        settlementExecutionActive = true;
        success = this.execute(
            SETTLE_ACTION,
            chainKey,
            blockHeight,
            encodedTransaction,
            merkleRoot,
            siblings,
            lowerEndpointDigest,
            continuityRoots
        );
        settlementExecutionActive = false;
    }

    function _processAndEmitEvent(uint8 action, bytes32 queryId, bytes memory encodedTransaction)
        internal
        override
        nonReentrant
    {
        if (!settlementExecutionActive) revert DirectExecutionDisabled();
        if (action != SETTLE_ACTION) revert InvalidAction();

        EvmV1Decoder.CommonTxFields memory sourceTransaction = EvmV1Decoder.decodeCommonTxFields(encodedTransaction);
        if (sourceTransaction.to != demoIssuer || sourceTransaction.data.length != 100) {
            revert InvalidReservationEvent();
        }
        bytes memory sourceData = sourceTransaction.data;
        bytes4 sourceSelector;
        assembly ("memory-safe") {
            sourceSelector := mload(add(sourceData, 32))
        }
        if (sourceSelector != bytes4(keccak256("reserveCertificate(bytes32,bytes32,bytes32)"))) {
            revert InvalidReservationEvent();
        }

        EvmV1Decoder.ReceiptFields memory receipt = EvmV1Decoder.decodeReceiptFields(encodedTransaction);
        if (receipt.receiptStatus != 1) revert FailedSourceTransaction();

        EvmV1Decoder.LogEntry[] memory logs =
            EvmV1Decoder.getLogsByEventSignature(receipt, CERTIFICATE_RESERVED_EVENT_SIGNATURE);
        if (logs.length != 1) revert InvalidReservationEvent();

        EvmV1Decoder.LogEntry memory reservation = logs[0];
        if (reservation.address_ != demoIssuer) revert UntrustedSourceIssuer();
        if (reservation.topics.length != 4 || reservation.topics[0] != CERTIFICATE_RESERVED_EVENT_SIGNATURE) {
            revert InvalidReservationEvent();
        }
        if (reservation.data.length != 128) revert InvalidReservationEvent();

        bytes32 certificateId = reservation.topics[1];
        bytes32 reservationHash = reservation.topics[2];
        uint256 ownerTopic = uint256(reservation.topics[3]);
        if (ownerTopic >> 160 != 0) revert InvalidReservationEvent();
        address certificateOwner = address(uint160(ownerTopic));
        (bytes32 jobId, uint64 energyWh, uint64 certificateExpiresAt, uint256 sourceEvmChainId) =
            abi.decode(reservation.data, (bytes32, uint64, uint64, uint256));

        if (sourceEvmChainId != expectedSourceEvmChainId) revert WrongSourceChain();
        if (consumedCertificates[certificateId]) revert CertificateAlreadyConsumed();

        Job storage job = jobs[jobId];
        if (job.status == JobStatus.None) revert JobDoesNotExist();
        if (job.status == JobStatus.Settled) revert JobAlreadySettled();
        if (job.status != JobStatus.Funded) revert JobNotFunded();
        if (block.timestamp > job.settlementDeadline) revert JobDeadlinePassed();
        if (certificateOwner != job.buyer) revert CertificateOwnerMismatch();
        if (energyWh != job.requiredEnergyWh) revert EnergyMismatch();
        if (certificateExpiresAt < job.settlementDeadline) revert CertificateExpiresBeforeSettlement();
        if (reservationHash != allocationHashFor(certificateId, jobId)) revert AllocationCommitmentMismatch();

        consumedCertificates[certificateId] = true;
        job.status = JobStatus.Settled;

        (bool paid,) = job.provider.call{value: job.reward}("");
        if (!paid) revert PaymentFailed();

        emit JobSettled(jobId, certificateId, queryId, job.provider, job.reward, reservationHash);
    }
}
