// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DemoCertificateIssuer} from "../contracts/DemoCertificateIssuer.sol";
import {WattLockASC} from "../contracts/WattLockASC.sol";
import {EvmV1Decoder} from "@gluwa/asc-contracts/contracts/common/EvmV1Decoder.sol";

contract WattLockHarness is WattLockASC {
    constructor(address issuer, uint64 sourceChainKey, uint256 sourceEvmChainId)
        WattLockASC(issuer, sourceChainKey, sourceEvmChainId)
    {}

    /// @dev Test-only entry point representing ASCBase after its native proof check succeeds.
    function processVerifiedForTest(bytes32 queryId, bytes calldata encodedTransaction) external {
        require(!processedQueries[queryId], "Query already processed");
        processedQueries[queryId] = true;
        settlementExecutionActive = true;
        _processAndEmitEvent(SETTLE_ACTION, queryId, encodedTransaction);
        settlementExecutionActive = false;
    }
}

contract WattLockTest is Test {
    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint64 internal constant ENERGY_WH = 1_000;
    uint128 internal constant REWARD = 1 ether;

    address internal constant BUYER = address(0xB0B);
    address internal constant PROVIDER = address(0xCAFE);
    address internal constant ATTACKER = address(0xBAD);

    DemoCertificateIssuer internal issuer;
    WattLockHarness internal wattLock;

    function setUp() public {
        issuer = new DemoCertificateIssuer(address(this));
        wattLock = new WattLockHarness(address(issuer), 1, SEPOLIA_CHAIN_ID);
        vm.deal(BUYER, 10 ether);
    }

    function testReserveIsTerminalAndOnlyOwnerCanReserve() public {
        bytes32 certificateId = keccak256("certificate-terminal");
        bytes32 jobId = keccak256("job-terminal");
        bytes32 commitment = keccak256("commitment");
        uint64 expiresAt = uint64(block.timestamp + 2 days);

        issuer.issueCertificate(certificateId, BUYER, ENERGY_WH, expiresAt);

        vm.prank(ATTACKER);
        vm.expectRevert(DemoCertificateIssuer.NotCertificateOwner.selector);
        issuer.reserveCertificate(certificateId, jobId, commitment);

        vm.prank(BUYER);
        issuer.reserveCertificate(certificateId, jobId, commitment);

        vm.prank(BUYER);
        vm.expectRevert(DemoCertificateIssuer.CertificateAlreadyReserved.selector);
        issuer.reserveCertificate(certificateId, jobId, commitment);
    }

    function testValidReservationSettlesExactFundedJob() public {
        bytes32 certificateId = keccak256("certificate-allowed");
        bytes32 jobId = keccak256("job-allowed");
        uint64 deadline = uint64(block.timestamp + 1 days);
        _openJob(jobId, deadline);

        bytes32 commitment = wattLock.allocationHashFor(certificateId, jobId);
        bytes memory receipt = _reservationReceipt(
            address(issuer),
            certificateId,
            commitment,
            BUYER,
            jobId,
            ENERGY_WH,
            deadline + 1 days,
            SEPOLIA_CHAIN_ID,
            true
        );

        wattLock.processVerifiedForTest(keccak256("proof-allowed"), receipt);

        (,,,,, WattLockASC.JobStatus status) = wattLock.jobs(jobId);
        assertEq(uint256(status), uint256(WattLockASC.JobStatus.Settled));
        assertTrue(wattLock.consumedCertificates(certificateId));
        assertEq(PROVIDER.balance, REWARD);
        assertEq(address(wattLock).balance, 0);
    }

    function testRejectsCommitmentForAnotherJob() public {
        bytes32 certificateId = keccak256("certificate-wrong-job");
        bytes32 jobA = keccak256("job-a");
        bytes32 jobB = keccak256("job-b");
        uint64 deadline = uint64(block.timestamp + 1 days);
        _openJob(jobA, deadline);
        _openJob(jobB, deadline);

        bytes32 commitmentForA = wattLock.allocationHashFor(certificateId, jobA);
        bytes memory receipt = _reservationReceipt(
            address(issuer),
            certificateId,
            commitmentForA,
            BUYER,
            jobB,
            ENERGY_WH,
            deadline + 1 days,
            SEPOLIA_CHAIN_ID,
            true
        );

        vm.expectRevert(WattLockASC.AllocationCommitmentMismatch.selector);
        wattLock.processVerifiedForTest(keccak256("proof-wrong-job"), receipt);

        (,,,,, WattLockASC.JobStatus statusA) = wattLock.jobs(jobA);
        (,,,,, WattLockASC.JobStatus statusB) = wattLock.jobs(jobB);
        assertEq(uint256(statusA), uint256(WattLockASC.JobStatus.Funded));
        assertEq(uint256(statusB), uint256(WattLockASC.JobStatus.Funded));
        assertEq(PROVIDER.balance, 0);
    }

    function testRejectsSameCertificateAfterSettlement() public {
        bytes32 certificateId = keccak256("certificate-replay");
        bytes32 jobA = keccak256("job-replay-a");
        bytes32 jobB = keccak256("job-replay-b");
        uint64 deadline = uint64(block.timestamp + 1 days);
        _openJob(jobA, deadline);
        _openJob(jobB, deadline);

        bytes32 commitmentA = wattLock.allocationHashFor(certificateId, jobA);
        bytes memory receiptA = _reservationReceipt(
            address(issuer),
            certificateId,
            commitmentA,
            BUYER,
            jobA,
            ENERGY_WH,
            deadline + 1 days,
            SEPOLIA_CHAIN_ID,
            true
        );
        wattLock.processVerifiedForTest(keccak256("proof-replay-a"), receiptA);

        bytes32 commitmentB = wattLock.allocationHashFor(certificateId, jobB);
        bytes memory receiptB = _reservationReceipt(
            address(issuer),
            certificateId,
            commitmentB,
            BUYER,
            jobB,
            ENERGY_WH,
            deadline + 1 days,
            SEPOLIA_CHAIN_ID,
            true
        );
        vm.expectRevert(WattLockASC.CertificateAlreadyConsumed.selector);
        wattLock.processVerifiedForTest(keccak256("proof-replay-b"), receiptB);

        assertEq(PROVIDER.balance, REWARD);
    }

    function testRejectsExactProofQueryReplay() public {
        bytes32 certificateId = keccak256("certificate-query-replay");
        bytes32 jobId = keccak256("job-query-replay");
        uint64 deadline = uint64(block.timestamp + 1 days);
        _openJob(jobId, deadline);

        bytes32 commitment = wattLock.allocationHashFor(certificateId, jobId);
        bytes memory receipt = _reservationReceipt(
            address(issuer),
            certificateId,
            commitment,
            BUYER,
            jobId,
            ENERGY_WH,
            deadline + 1 days,
            SEPOLIA_CHAIN_ID,
            true
        );
        bytes32 queryId = keccak256("proof-query-replay");

        wattLock.processVerifiedForTest(queryId, receipt);

        vm.expectRevert("Query already processed");
        wattLock.processVerifiedForTest(queryId, receipt);
        assertEq(PROVIDER.balance, REWARD);
    }

    function testRejectsWrongSourceIssuerAndFailedReceipt() public {
        bytes32 certificateId = keccak256("certificate-source");
        bytes32 jobId = keccak256("job-source");
        uint64 deadline = uint64(block.timestamp + 1 days);
        _openJob(jobId, deadline);
        bytes32 commitment = wattLock.allocationHashFor(certificateId, jobId);

        bytes memory wrongIssuer = _reservationReceipt(
            ATTACKER, certificateId, commitment, BUYER, jobId, ENERGY_WH, deadline + 1 days, SEPOLIA_CHAIN_ID, true
        );
        vm.expectRevert(WattLockASC.UntrustedSourceIssuer.selector);
        wattLock.processVerifiedForTest(keccak256("proof-wrong-issuer"), wrongIssuer);

        bytes memory failedReceipt = _reservationReceipt(
            address(issuer),
            certificateId,
            commitment,
            BUYER,
            jobId,
            ENERGY_WH,
            deadline + 1 days,
            SEPOLIA_CHAIN_ID,
            false
        );
        vm.expectRevert(WattLockASC.FailedSourceTransaction.selector);
        wattLock.processVerifiedForTest(keccak256("proof-failed-receipt"), failedReceipt);
    }

    function testRejectsWrongSourceChainOwnerAndCertificateExpiry() public {
        bytes32 certificateId = keccak256("certificate-semantics");
        bytes32 jobId = keccak256("job-semantics");
        uint64 deadline = uint64(block.timestamp + 1 days);
        _openJob(jobId, deadline);
        bytes32 commitment = wattLock.allocationHashFor(certificateId, jobId);

        bytes memory wrongChain = _reservationReceipt(
            address(issuer), certificateId, commitment, BUYER, jobId, ENERGY_WH, deadline + 1 days, 1, true
        );
        vm.expectRevert(WattLockASC.WrongSourceChain.selector);
        wattLock.processVerifiedForTest(keccak256("proof-wrong-chain"), wrongChain);

        bytes memory wrongOwner = _reservationReceipt(
            address(issuer),
            certificateId,
            commitment,
            ATTACKER,
            jobId,
            ENERGY_WH,
            deadline + 1 days,
            SEPOLIA_CHAIN_ID,
            true
        );
        vm.expectRevert(WattLockASC.CertificateOwnerMismatch.selector);
        wattLock.processVerifiedForTest(keccak256("proof-wrong-owner"), wrongOwner);

        bytes memory expiredBeforeSettlement = _reservationReceipt(
            address(issuer), certificateId, commitment, BUYER, jobId, ENERGY_WH, deadline - 1, SEPOLIA_CHAIN_ID, true
        );
        vm.expectRevert(WattLockASC.CertificateExpiresBeforeSettlement.selector);
        wattLock.processVerifiedForTest(keccak256("proof-expired-certificate"), expiredBeforeSettlement);
    }

    function testAllocationHashMatchesIndependentReference() public {
        bytes32 certificateId = keccak256("certificate-reference");
        bytes32 jobId = keccak256("job-reference");
        uint64 deadline = uint64(block.timestamp + 1 days);
        _openJob(jobId, deadline);

        bytes32 expected = keccak256(
            abi.encode(
                keccak256("WATTLOCK_V1"),
                SEPOLIA_CHAIN_ID,
                address(issuer),
                block.chainid,
                address(wattLock),
                certificateId,
                jobId,
                BUYER,
                PROVIDER,
                REWARD,
                ENERGY_WH,
                deadline
            )
        );

        assertEq(wattLock.allocationHashFor(certificateId, jobId), expected);
    }

    function testIssuerEventMatchesDestinationDecoderSchema() public {
        bytes32 certificateId = keccak256("certificate-abi");
        bytes32 jobId = keccak256("job-abi");
        bytes32 commitment = keccak256("commitment-abi");
        uint64 expiry = uint64(block.timestamp + 1 days);
        issuer.issueCertificate(certificateId, BUYER, ENERGY_WH, expiry);

        vm.recordLogs();
        vm.prank(BUYER);
        issuer.reserveCertificate(certificateId, jobId, commitment);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(issuer));
        assertEq(entries[0].topics.length, 4);
        assertEq(entries[0].topics[0], wattLock.CERTIFICATE_RESERVED_EVENT_SIGNATURE());
        assertEq(entries[0].topics[1], certificateId);
        assertEq(entries[0].topics[2], commitment);
        assertEq(address(uint160(uint256(entries[0].topics[3]))), BUYER);

        (bytes32 emittedJobId, uint64 emittedEnergyWh, uint64 emittedExpiry, uint256 emittedChainId) =
            abi.decode(entries[0].data, (bytes32, uint64, uint64, uint256));
        assertEq(emittedJobId, jobId);
        assertEq(emittedEnergyWh, ENERGY_WH);
        assertEq(emittedExpiry, expiry);
        assertEq(emittedChainId, block.chainid);
    }

    function testRejectsZeroJobId() public {
        vm.prank(BUYER);
        vm.expectRevert(WattLockASC.InvalidJobId.selector);
        wattLock.openJob{value: REWARD}(bytes32(0), PROVIDER, ENERGY_WH, uint64(block.timestamp + 1 days));
    }

    function testBuyerCanReclaimOnlyAfterDeadline() public {
        bytes32 jobId = keccak256("job-reclaim");
        uint64 deadline = uint64(block.timestamp + 1 days);
        _openJob(jobId, deadline);

        vm.prank(BUYER);
        vm.expectRevert(WattLockASC.JobDeadlineInvalid.selector);
        wattLock.reclaimExpiredJob(jobId);

        vm.warp(deadline + 1);
        vm.prank(BUYER);
        wattLock.reclaimExpiredJob(jobId);

        (,,,,, WattLockASC.JobStatus status) = wattLock.jobs(jobId);
        assertEq(uint256(status), uint256(WattLockASC.JobStatus.Reclaimed));
        assertEq(address(wattLock).balance, 0);
    }

    function _openJob(bytes32 jobId, uint64 deadline) internal {
        vm.prank(BUYER);
        wattLock.openJob{value: REWARD}(jobId, PROVIDER, ENERGY_WH, deadline);
    }

    function _reservationReceipt(
        address emitter,
        bytes32 certificateId,
        bytes32 commitment,
        address certificateOwner,
        bytes32 jobId,
        uint64 energyWh,
        uint64 certificateExpiresAt,
        uint256 sourceChainId,
        bool succeeded
    ) internal view returns (bytes memory) {
        bytes32[] memory topics = new bytes32[](4);
        topics[0] = keccak256("CertificateReserved(bytes32,bytes32,address,bytes32,uint64,uint64,uint256)");
        topics[1] = certificateId;
        topics[2] = commitment;
        topics[3] = bytes32(uint256(uint160(certificateOwner)));

        EvmV1Decoder.LogEntryTuple[] memory logs = new EvmV1Decoder.LogEntryTuple[](1);
        logs[0] = EvmV1Decoder.LogEntryTuple({
            address_: emitter, topics: topics, data: abi.encode(jobId, energyWh, certificateExpiresAt, sourceChainId)
        });

        bytes[] memory chunks = new bytes[](3);
        chunks[0] = abi.encode(
            uint64(0),
            uint64(0),
            address(0),
            false,
            address(issuer),
            uint256(0),
            abi.encodeWithSelector(
                bytes4(keccak256("reserveCertificate(bytes32,bytes32,bytes32)")), certificateId, jobId, commitment
            )
        );
        chunks[1] = abi.encode(uint128(0), uint256(0), bytes32(0), bytes32(0));
        chunks[2] = abi.encode(uint8(succeeded ? 1 : 0), uint64(0), logs, bytes(""));
        return abi.encode(uint8(0), chunks);
    }
}
