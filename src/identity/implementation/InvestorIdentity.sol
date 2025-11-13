// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Identity.sol";

/**
 * @title InvestorIdentity
 * @dev Identity contract for investors
 * @notice Extends base Identity with investor-specific features
 */
contract InvestorIdentity is Identity {
    using IdentityStorage for IdentityStorage.Layout;

    /**
     * @dev Emitted when investor verification status changes
     */
    event InvestorVerificationUpdated(
        address indexed investor,
        bool kycValid,
        bool amlValid,
        bool accreditationValid
    );

    /**
     * @dev Initialize investor identity
     * @param _owner Owner address
     * @param _investorName Investor name
     */
    function initializeInvestor(address _owner, string memory _investorName) public {
        initialize(_owner, _investorName, true, false);
    }

    /**
     * @dev Check if investor has valid KYC claim
     * @return hasKYC Whether investor has valid KYC
     */
    function hasKYCClaim() public view returns (bool hasKYC) {
        return _hasValidClaimForTopic(IdentityStorage.KYC_CLAIM);
    }

    /**
     * @dev Check if investor has valid AML claim
     * @return hasAML Whether investor has valid AML
     */
    function hasAMLClaim() public view returns (bool hasAML) {
        return _hasValidClaimForTopic(IdentityStorage.AML_CLAIM);
    }

    /**
     * @dev Check if investor has valid accreditation claim
     * @return hasAccreditation Whether investor has valid accreditation
     */
    function hasAccreditationClaim() public view returns (bool hasAccreditation) {
        return _hasValidClaimForTopic(IdentityStorage.ACCREDITATION_CLAIM);
    }

    /**
     * @dev Check if investor is fully verified (has both KYC and AML)
     * @return verified Whether investor is fully verified
     */
    function isFullyVerified() public view returns (bool verified) {
        return hasKYCClaim() && hasAMLClaim();
    }

    /**
     * @dev Get investor verification status
     * @return kycValid KYC validity
     * @return amlValid AML validity
     * @return accreditationValid Accreditation validity
     */
    function getVerificationStatus()
        public
        view
        returns (
            bool kycValid,
            bool amlValid,
            bool accreditationValid
        )
    {
        return (hasKYCClaim(), hasAMLClaim(), hasAccreditationClaim());
    }

    /**
     * @dev Get country claim data
     * @return countryCode Country code bytes
     */
    function getCountryClaim() public view returns (bytes memory countryCode) {
        bytes32[] memory countryClaims = getClaimIdsByTopic(IdentityStorage.COUNTRY_CLAIM);
        
        if (countryClaims.length > 0 && isClaimValid(countryClaims[0])) {
            (, , , , bytes memory data, ) = getClaim(countryClaims[0]);
            return data;
        }
        
        return "";
    }

    /**
     * @dev Validate investor-specific claim
     * @param _claimId Claim ID to validate
     * @return valid Whether the claim is valid for investor
     */
    function validateInvestorClaim(bytes32 _claimId) public view returns (bool valid) {
        if (!isClaimValid(_claimId)) {
            return false;
        }

        (uint256 topic, , , , , ) = getClaim(_claimId);
        
        // Validate that claim topic is relevant for investors
        return topic == IdentityStorage.KYC_CLAIM ||
               topic == IdentityStorage.AML_CLAIM ||
               topic == IdentityStorage.ACCREDITATION_CLAIM ||
               topic == IdentityStorage.COUNTRY_CLAIM;
    }

    /**
     * @dev Get all verification claims
     * @return kycClaims KYC claim IDs
     * @return amlClaims AML claim IDs
     * @return accreditationClaims Accreditation claim IDs
     */
    function getVerificationClaims()
        public
        view
        returns (
            bytes32[] memory kycClaims,
            bytes32[] memory amlClaims,
            bytes32[] memory accreditationClaims
        )
    {
        return (
            getClaimIdsByTopic(IdentityStorage.KYC_CLAIM),
            getClaimIdsByTopic(IdentityStorage.AML_CLAIM),
            getClaimIdsByTopic(IdentityStorage.ACCREDITATION_CLAIM)
        );
    }

    /**
     * @dev Internal function to check if identity has valid claim for topic
     */
    function _hasValidClaimForTopic(uint256 _topic) internal view returns (bool) {
        bytes32[] memory claimsForTopic = getClaimIdsByTopic(_topic);
        
        for (uint256 i = 0; i < claimsForTopic.length; i++) {
            if (isClaimValid(claimsForTopic[i])) {
                return true;
            }
        }
        
        return false;
    }
}

