// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/// @title Gestión de estados de eVTOLs
/// @notice Mantiene el estado operativo y ubicación de cada eVTOL.
///         El registro de un eVTOL requiere atestación del Trusted Verifier (Opcion A).
///
/// TRABAJO FUTURO: ver docs/10_verificacion_criptografica.md (Opciones B y C).
contract EVTOLManagement {
    enum EVTOLState { PARKED, EXPECTING, IN_USE, MAINTENANCE }

    struct EVTOL {
        uint256 id;
        EVTOLState state;
        string currentVertiportId;
        string activeTripId;
        bool exists;
    }

    address public trustedVerifier;

    mapping(uint256 => EVTOL) private evtols;

    event EVTOLRegistered(uint256 indexed id, string currentVertiportId);
    event EVTOLStateChanged(
        uint256 indexed id,
        EVTOLState previousState,
        EVTOLState newState,
        string currentVertiportId,
        string activeTripId
    );

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

    /// @notice Registra un eVTOL en estado PARKED. Requiere atestación del Trusted Verifier.
    /// @param id                 Identificador único del eVTOL.
    /// @param initialVertiportId Vertiport donde está inicialmente.
    /// @param evtolCredential    Atributos de la credencial SSI (bytes, para auditoría).
    /// @param attestation        Firma EIP-191 de keccak256("evtol" || id).
    function registerEVTOL(
        uint256 id,
        string memory initialVertiportId,
        bytes memory evtolCredential,
        bytes memory attestation
    ) public {
        require(!evtols[id].exists, "EVTOL ya registrado");

        bytes32 msgHash = keccak256(abi.encodePacked("evtol", id));
        require(
            _verifyAttestation(msgHash, attestation),
            "Atestacion de eVTOL invalida"
        );

        evtolCredential;

        EVTOL storage e = evtols[id];
        e.id                = id;
        e.state             = EVTOLState.PARKED;
        e.currentVertiportId = initialVertiportId;
        e.activeTripId      = "";
        e.exists            = true;

        emit EVTOLRegistered(id, initialVertiportId);
        emit EVTOLStateChanged(id, EVTOLState.PARKED, EVTOLState.PARKED, initialVertiportId, "");
    }

    function assignToTrip(uint256 id, string memory tripId) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.PARKED, "EVTOL no esta PARKED");
        require(bytes(e.activeTripId).length == 0, "Ya tiene viaje activo");
        require(bytes(tripId).length > 0, "tripId vacio");

        EVTOLState previous = e.state;
        e.state = EVTOLState.EXPECTING;
        e.activeTripId = tripId;
        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    function startTrip(uint256 id) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.EXPECTING, "EVTOL no esta EXPECTING");
        require(bytes(e.activeTripId).length > 0, "No hay viaje activo");

        EVTOLState previous = e.state;
        e.state = EVTOLState.IN_USE;
        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    function completeTrip(uint256 id, string memory destinationVertiportId) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.IN_USE, "EVTOL no esta IN_USE");
        require(bytes(e.activeTripId).length > 0, "No hay viaje activo");

        EVTOLState previous = e.state;
        e.state = EVTOLState.PARKED;
        e.currentVertiportId = destinationVertiportId;
        e.activeTripId = "";
        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    function setMaintenance(uint256 id) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.PARKED, "Solo PARKED puede ir a MAINTENANCE");
        require(bytes(e.activeTripId).length == 0, "No debe tener viaje activo");

        EVTOLState previous = e.state;
        e.state = EVTOLState.MAINTENANCE;
        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    function finishMaintenance(uint256 id) public {
        EVTOL storage e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        require(e.state == EVTOLState.MAINTENANCE, "EVTOL no esta en MAINTENANCE");

        EVTOLState previous = e.state;
        e.state = EVTOLState.PARKED;
        emit EVTOLStateChanged(id, previous, e.state, e.currentVertiportId, e.activeTripId);
    }

    function getEVTOL(uint256 id) public view returns (EVTOL memory) {
        EVTOL memory e = evtols[id];
        require(e.exists, "EVTOL no encontrado");
        return e;
    }

    function isAvailable(uint256 id) public view returns (bool) {
        EVTOL storage e = evtols[id];
        if (!e.exists) return false;
        if (e.state != EVTOLState.PARKED) return false;
        if (bytes(e.activeTripId).length != 0) return false;
        return true;
    }
}
