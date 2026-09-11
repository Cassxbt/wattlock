// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Testnet model of an external energy-certificate issuer. It intentionally proves only
/// on-chain certificate state, never physical generation or real-world energy matching.
contract DemoCertificateIssuer is Ownable {
    struct Certificate {
        address owner;
        uint64 energyWh;
        uint64 expiresAt;
        bool reserved;
    }

    error CertificateAlreadyExists();
    error CertificateDoesNotExist();
    error CertificateAlreadyReserved();
    error CertificateExpired();
    error NotCertificateOwner();
    error ZeroAddress();
    error ZeroEnergy();
    error ZeroAllocationHash();
    error ZeroJobId();

    mapping(bytes32 certificateId => Certificate certificate) public certificates;

    event CertificateIssued(bytes32 indexed certificateId, address indexed owner, uint64 energyWh, uint64 expiresAt);
    event CertificateReserved(
        bytes32 indexed certificateId,
        bytes32 indexed allocationHash,
        address indexed certificateOwner,
        bytes32 jobId,
        uint64 energyWh,
        uint64 certificateExpiresAt,
        uint256 sourceEvmChainId
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function issueCertificate(bytes32 certificateId, address certificateOwner, uint64 energyWh, uint64 expiresAt)
        external
        onlyOwner
    {
        if (certificates[certificateId].owner != address(0)) revert CertificateAlreadyExists();
        if (certificateOwner == address(0)) revert ZeroAddress();
        if (energyWh == 0) revert ZeroEnergy();
        if (expiresAt <= block.timestamp) revert CertificateExpired();

        certificates[certificateId] =
            Certificate({owner: certificateOwner, energyWh: energyWh, expiresAt: expiresAt, reserved: false});

        emit CertificateIssued(certificateId, certificateOwner, energyWh, expiresAt);
    }

    /// @notice Permanently binds a certificate to one destination-chain allocation commitment.
    function reserveCertificate(bytes32 certificateId, bytes32 jobId, bytes32 allocationHash) external {
        Certificate storage certificate = certificates[certificateId];
        if (certificate.owner == address(0)) revert CertificateDoesNotExist();
        if (msg.sender != certificate.owner) revert NotCertificateOwner();
        if (certificate.reserved) revert CertificateAlreadyReserved();
        if (block.timestamp > certificate.expiresAt) revert CertificateExpired();
        if (jobId == bytes32(0)) revert ZeroJobId();
        if (allocationHash == bytes32(0)) revert ZeroAllocationHash();

        certificate.reserved = true;

        emit CertificateReserved(
            certificateId,
            allocationHash,
            certificate.owner,
            jobId,
            certificate.energyWh,
            certificate.expiresAt,
            block.chainid
        );
    }
}
