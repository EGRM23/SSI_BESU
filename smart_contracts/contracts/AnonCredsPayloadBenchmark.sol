// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// Transport benchmark only: this contract does not verify AnonCreds CL proofs.
contract AnonCredsPayloadBenchmark {
    event PresentationSubmitted(bytes32 indexed proofHash, bytes32 indexed schemaIdHash, bytes32 indexed credDefIdHash, uint256 payloadBytes, uint256 nonRevokedTo);
    function submitPresentation(bytes calldata proof, bytes32 schemaIdHash, bytes32 credDefIdHash, uint256 nonRevokedTo) external {
        emit PresentationSubmitted(keccak256(proof), schemaIdHash, credDefIdHash, proof.length, nonRevokedTo);
    }
}
