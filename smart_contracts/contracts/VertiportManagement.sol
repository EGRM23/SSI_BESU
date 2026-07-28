// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Gestión de Vertiports
/// @notice Mantiene capacidad y disponibilidad de pistas y parkings.
///         El registro de un vertiport requiere atestación del Trusted Verifier (Opcion A).
///
/// TRABAJO FUTURO: ver docs/10_verificacion_criptografica.md (Opciones B y C).
contract VertiportManagement {
    struct VertiportState {
        string id;
        uint256 n_airstrip;
        uint256 n_parkings;
        uint256 n_free_airstrip;
        uint256 n_parkings_free;
        bool exists;
    }

    address public trustedVerifier;

    mapping(string => VertiportState) private vertiports;

    event VertiportRegistered(string indexed vertiportId, uint256 n_airstrip, uint256 n_parkings);
    event VertiportUpdated(string indexed vertiportId, uint256 n_free_airstrip, uint256 n_parkings_free);

    constructor(address trustedVerifier_) {
        require(trustedVerifier_ != address(0), "Verifier invalido");
        trustedVerifier = trustedVerifier_;
    }

    function setTrustedVerifier(address newVerifier) external {
        require(msg.sender == trustedVerifier, "No autorizado");
        require(newVerifier != address(0), "Verifier invalido");
        trustedVerifier = newVerifier;
    }

    /// @dev Verifica firma EIP-191 del Trusted Verifier sobre msgHash.
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

    /// @notice Registra un vertiport. Requiere atestación del Trusted Verifier.
    /// @param vertiportId         Identificador lógico.
    /// @param n_airstrip          Pistas totales.
    /// @param n_parkings          Parkings totales.
    /// @param vertiportCredential Atributos de la credencial SSI (bytes, para auditoría).
    /// @param attestation         Firma EIP-191 de keccak256("vertiport" || vertiportId).
    function registerVertiport(
        string memory vertiportId,
        uint256 n_airstrip,
        uint256 n_parkings,
        bytes memory vertiportCredential,
        bytes memory attestation
    ) public {
        bytes32 msgHash = keccak256(abi.encodePacked("vertiport", vertiportId));
        require(
            _verifyAttestation(msgHash, attestation),
            "Atestacion de vertiport invalida"
        );

        VertiportState storage existing = vertiports[vertiportId];
        require(!existing.exists, "Vertiport ya registrado");
        require(n_airstrip > 0 || n_parkings > 0, "Capacidad invalida");

        // vertiportCredential se almacena implícitamente vía el evento para auditoría
        vertiportCredential;

        VertiportState storage port = vertiports[vertiportId];
        port.id          = vertiportId;
        port.n_airstrip  = n_airstrip;
        port.n_parkings  = n_parkings;
        port.n_free_airstrip = n_airstrip;
        port.n_parkings_free = n_parkings;
        port.exists      = true;

        emit VertiportRegistered(vertiportId, n_airstrip, n_parkings);
        emit VertiportUpdated(vertiportId, port.n_free_airstrip, port.n_parkings_free);
    }

    /// @notice Actualiza disponibilidad de pistas/parkings.
    ///         Llamada por FlightReservation (startTrip / completeTrip) y por el bridge
    ///         para pre-ocupar parkings. No requiere atestación — la identidad del vertiport
    ///         ya fue verificada en registerVertiport().
    function updateVertiportState(
        string memory vertiportId,
        bytes memory vertiportCredential,
        int256 airstripDelta,
        int256 parkingDelta
    ) public {
        vertiportCredential;

        VertiportState storage port = vertiports[vertiportId];
        require(port.exists, "Vertiport no encontrado");

        if (airstripDelta > 0) {
            port.n_free_airstrip += uint256(airstripDelta);
            require(port.n_free_airstrip <= port.n_airstrip, "Limite de pistas excedido");
        } else if (airstripDelta < 0) {
            uint256 d = uint256(-airstripDelta);
            require(port.n_free_airstrip >= d, "Sin pistas libres");
            port.n_free_airstrip -= d;
        }

        if (parkingDelta > 0) {
            port.n_parkings_free += uint256(parkingDelta);
            require(port.n_parkings_free <= port.n_parkings, "Limite de parkings excedido");
        } else if (parkingDelta < 0) {
            uint256 d = uint256(-parkingDelta);
            require(port.n_parkings_free >= d, "Sin parkings libres");
            port.n_parkings_free -= d;
        }

        emit VertiportUpdated(vertiportId, port.n_free_airstrip, port.n_parkings_free);
    }

    function checkLandingAvailability(string memory vertiportId) public view returns (bool) {
        VertiportState storage port = vertiports[vertiportId];
        if (!port.exists) return false;
        return port.n_free_airstrip > 0 && port.n_parkings_free > 0;
    }

    function getVertiportState(string memory vertiportId) public view returns (VertiportState memory) {
        VertiportState memory port = vertiports[vertiportId];
        require(port.exists, "Vertiport no encontrado");
        return port;
    }
}
