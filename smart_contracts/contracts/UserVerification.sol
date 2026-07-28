// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Verificacion de usuarios aptos para volar
/// @notice Mantiene un registro on-chain de si un usuario puede reservar vuelos.
///         La autorizacion la firma off-chain Django (Trusted Verifier — Opcion A).
///
/// TRABAJO FUTURO:
///   Esta implementacion usa el patron Trusted Verifier (Opcion A): un backend
///   centralizado firma las atestaciones con una clave secp256k1. El contrato
///   verifica la firma con ecrecover(). El punto de confianza sigue siendo
///   centralizado. Ver docs/10_verificacion_criptografica.md para la hoja de
///   ruta hacia Opcion B (ZK-SNARK) u Opcion C (credenciales BBS+/secp256k1
///   verificables directamente on-chain sin backend intermediario).
contract UserVerification {
    address public issuer;
    address public trustedVerifier;

    mapping(address => bool) private _canRide;

    event IssuerChanged(address indexed previousIssuer, address indexed newIssuer);
    event RiderPermissionSet(address indexed user, bool canRide);

    constructor(address initialIssuer) {
        require(initialIssuer != address(0), "Issuer invalido");
        issuer = initialIssuer;
        trustedVerifier = initialIssuer;
        emit IssuerChanged(address(0), initialIssuer);
    }

    modifier onlyIssuer() {
        require(msg.sender == issuer, "No autorizado: solo issuer");
        _;
    }

    function setIssuer(address newIssuer) external onlyIssuer {
        require(newIssuer != address(0), "Issuer invalido");
        address previous = issuer;
        issuer = newIssuer;
        emit IssuerChanged(previous, newIssuer);
    }

    function setTrustedVerifier(address newVerifier) external onlyIssuer {
        require(newVerifier != address(0), "Verifier invalido");
        trustedVerifier = newVerifier;
    }

    /// @dev Verifica que `sig` sea una firma EIP-191 del hash dado por `trustedVerifier`.
    ///      Reemplaza el mock anterior (return true).
    function _verifyAttestation(bytes32 msgHash, bytes memory sig) internal view returns (bool) {
        if (sig.length != 65) return false;

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;

        bytes32 ethHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash)
        );
        address signer = ecrecover(ethHash, v, r, s);
        return signer != address(0) && signer == trustedVerifier;
    }

    /// @notice Registra o actualiza el permiso de un usuario para volar.
    /// @param user        Address del usuario en la red Besu.
    /// @param canRide     Permiso otorgado por la credencial SSI verificada off-chain.
    /// @param attestation Firma EIP-191 de keccak256("user" || user || canRide)
    ///                    producida por el Trusted Verifier (Django).
    function setRiderPermission(
        address user,
        bool canRide,
        bytes memory attestation
    ) public onlyIssuer {
        require(user != address(0), "Usuario invalido");

        bytes32 msgHash = keccak256(abi.encodePacked("user", user, canRide));
        require(
            _verifyAttestation(msgHash, attestation),
            "Atestacion de usuario invalida"
        );

        _canRide[user] = canRide;
        emit RiderPermissionSet(user, canRide);
    }

    /// @notice Devuelve true si el usuario esta autorizado para volar.
    function canUserRide(address user) external view returns (bool) {
        return _canRide[user];
    }
}
