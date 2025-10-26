// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Encrypted Insurance Eligibility
 * - Rules (minAge, maxClaims, minScore) are stored as ciphertexts (euint).
 * - Applicants submit encrypted attributes and receive an encrypted verdict (eligible: 1/0).
 * - Uses only official Zama FHE library & SepoliaConfig.
 */

import {
    FHE,
    ebool,
    euint8,
    euint16,
    externalEuint8,
    externalEuint16
} from "@fhevm/solidity/lib/FHE.sol";

import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract EncryptedInsuranceEligibility is SepoliaConfig {
    /* ---------------------------- Version & Events ---------------------------- */

    function version() external pure returns (string memory) {
        return "EncryptedInsuranceEligibility/1.0.0";
    }

    /// @notice Emitted when encrypted rules are updated.
    event RulesUpdated(bytes32 minAgeH, bytes32 maxClaimsH, bytes32 minScoreH);

    /// @notice Emitted on each application; resultHandle is an encrypted bool (1/0).
    event ApplicationChecked(
        address indexed applicant,
        bytes32 resultHandle
    );

    /* -------------------------------- Ownable -------------------------------- */

    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() {
        owner = msg.sender;
        // Initialize rules with neutral defaults (age=0, claims=255, score=0)
        // to avoid zero-handles when reading before first owner-set.
        _minAge   = FHE.asEuint8(0);
        _maxClaims= FHE.asEuint8(type(uint8).max);
        _minScore = FHE.asEuint16(0);

        // The contract will use these ciphertexts across multiple txs:
        FHE.allowThis(_minAge);
        FHE.allowThis(_maxClaims);
        FHE.allowThis(_minScore);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* ------------------------- Encrypted Rule Storage ------------------------- */

    // Encrypted rule parameters
    euint8  private _minAge;     // applicant.age >= minAge
    euint8  private _maxClaims;  // applicant.claims <= maxClaims
    euint16 private _minScore;   // applicant.score >= minScore

    /**
     * @notice Owner sets the encrypted rules (all inputs must share the same proof).
     * @dev    proof is produced by the Relayer SDK for the batched encrypted input.
     */
    function setRulesEncrypted(
        externalEuint8  minAgeExt,
        externalEuint8  maxClaimsExt,
        externalEuint16 minScoreExt,
        bytes calldata  proof
    ) external onlyOwner {
        // Deserialize + attest
        euint8  minAgeCt   = FHE.fromExternal(minAgeExt,   proof);
        euint8  maxClaimsCt= FHE.fromExternal(maxClaimsExt,proof);
        euint16 minScoreCt = FHE.fromExternal(minScoreExt, proof);

        // Store
        _minAge    = minAgeCt;
        _maxClaims = maxClaimsCt;
        _minScore  = minScoreCt;

        // Re-grant contract reuse rights for future txs
        FHE.allowThis(_minAge);
        FHE.allowThis(_maxClaims);
        FHE.allowThis(_minScore);

        emit RulesUpdated(FHE.toBytes32(_minAge), FHE.toBytes32(_maxClaims), FHE.toBytes32(_minScore));
    }

    /**
     * @notice Plain setters for development/testing only (DON'T USE IN PROD).
     *         They convert clear values to encrypted constants on-chain.
     */
    function setRulesPlain(
        uint8  minAge,
        uint8  maxClaims,
        uint16 minScore
    ) external onlyOwner {
        _minAge    = FHE.asEuint8(minAge);
        _maxClaims = FHE.asEuint8(maxClaims);
        _minScore  = FHE.asEuint16(minScore);

        FHE.allowThis(_minAge);
        FHE.allowThis(_maxClaims);
        FHE.allowThis(_minScore);

        emit RulesUpdated(FHE.toBytes32(_minAge), FHE.toBytes32(_maxClaims), FHE.toBytes32(_minScore));
    }

    /**
     * @notice Return encrypted rule handles for off-chain audits/decryption (optional).
     * @dev    Anyone can read handles; decryptability depends on ACL/public flags.
     */
    function getRuleHandles()
        external
        view
        returns (bytes32 minAgeH, bytes32 maxClaimsH, bytes32 minScoreH)
    {
        return (FHE.toBytes32(_minAge), FHE.toBytes32(_maxClaims), FHE.toBytes32(_minScore));
    }

    /**
     * @notice Optionally mark rules as publicly decryptable (audit / demo).
     */
    function makeRulesPublic() external onlyOwner {
        FHE.makePubliclyDecryptable(_minAge);
        FHE.makePubliclyDecryptable(_maxClaims);
        FHE.makePubliclyDecryptable(_minScore);
    }

    /* --------------------------- Application Checking ------------------------- */

    /**
     * @notice Check eligibility from encrypted inputs:
     *         - age      (uint8)
     *         - claims   (uint8)
     *         - score    (uint16)
     * @param ageExt       external handle of encrypted age
     * @param claimsExt    external handle of encrypted claims count
     * @param scoreExt     external handle of encrypted score
     * @param proof        ZK proof (relayer attestation) for those inputs
     * @return eligibleCt  encrypted bool: 1 = eligible, 0 = not eligible
     *
     * Access control:
     * - Grants user-only decryption rights to msg.sender.
     * - You can flip to makePubliclyDecryptable(eligibleCt) if you need global readability.
     */
    function checkEligibility(
        externalEuint8  ageExt,
        externalEuint8  claimsExt,
        externalEuint16 scoreExt,
        bytes calldata  proof
    ) external returns (ebool eligibleCt) {
        require(proof.length > 0, "Empty proof");

        // Deserialize applicant attributes with attestation verification
        euint8  ageCt    = FHE.fromExternal(ageExt,    proof);
        euint8  claimsCt = FHE.fromExternal(claimsExt, proof);
        euint16 scoreCt  = FHE.fromExternal(scoreExt,  proof);

        // Comparisons (all on ciphertexts)
        // condAge:    age >= minAge
        // condClaims: claims <= maxClaims
        // condScore:  score >= minScore
        ebool condAge    = FHE.ge(ageCt,    _minAge);
        ebool condClaims = FHE.le(claimsCt, _maxClaims);
        ebool condScore  = FHE.ge(scoreCt,  _minScore);

        // eligible = condAge && condClaims && condScore
        ebool ageAndClaims = FHE.and(condAge, condClaims);
        ebool eligible     = FHE.and(ageAndClaims, condScore);

        // ACL: allow contract to reuse and applicant to decrypt privately
        FHE.allowThis(eligible);
        FHE.allow(eligible, msg.sender);

        // Emit result handle for the UI (userDecrypt path)
        bytes32 handle = FHE.toBytes32(eligible);
        emit ApplicationChecked(msg.sender, handle);

        return eligible;
    }

    /**
     * @notice Convenience getter: last result handle for caller is emitted via event;
     *         if you store per-user results on-chain, add a mapping. Here we keep
     *         the contract stateless for results to avoid extra storage costs.
     */

    /* --------------------------- Optional Reset/Utils ------------------------- */

    /**
     * @notice Reset rules to safe defaults without `delete` (delete is not allowed for euint).
     */
    function resetRulesToDefaults() external onlyOwner {
        _minAge    = FHE.asEuint8(0);
        _maxClaims = FHE.asEuint8(type(uint8).max);
        _minScore  = FHE.asEuint16(0);

        FHE.allowThis(_minAge);
        FHE.allowThis(_maxClaims);
        FHE.allowThis(_minScore);

        emit RulesUpdated(FHE.toBytes32(_minAge), FHE.toBytes32(_maxClaims), FHE.toBytes32(_minScore));
    }
}
