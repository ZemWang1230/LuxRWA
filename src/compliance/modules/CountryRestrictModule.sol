// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./AbstractModule.sol";
import "../../registry/interface/IIdentityRegistry.sol";
import "../interface/IModularCompliance.sol";
import "../../token/interface/ILuxShareToken.sol";

/**
 * @title CountryRestrictModule
 * @dev Module that restricts specific countries from holding/receiving tokens
 * @notice Blacklist-based country restriction
 */
contract CountryRestrictModule is AbstractModule {
    // Mapping: compliance => country code => restricted
    mapping(address => mapping(uint16 => bool)) private _restrictedCountries;

    event CountryRestricted(address indexed compliance, uint16 indexed country);
    event CountryUnrestricted(address indexed compliance, uint16 indexed country);

    /**
     * @dev Add a country restriction
     * @param _country The country code to restrict
     */
    function addCountryRestriction(uint16 _country) external onlyComplianceCall {
        require((_restrictedCountries[msg.sender])[_country] == false, "CountryRestrictModule: country already restricted");
        (_restrictedCountries[msg.sender])[_country] = true;
        emit CountryRestricted(msg.sender, _country);
    }

    /**
     * @dev Remove a country restriction
     * @param _country The country code to remove
     */
    function removeCountryRestriction(uint16 _country) external onlyComplianceCall {
        require((_restrictedCountries[msg.sender])[_country] == true, "CountryRestrictModule: country not restricted");
        (_restrictedCountries[msg.sender])[_country] = false;
        emit CountryUnrestricted(msg.sender, _country);
    }

    /**
     * @dev Restrict multiple countries at once
     * @param _countries The country codes to restrict
     */
    function batchRestrictCountries(uint16[] calldata _countries) external onlyComplianceCall {
        require(_countries.length < 195, "maximum 195 can be restricted in one batch");
        for (uint256 i = 0; i < _countries.length; i++) {
            require((_restrictedCountries[msg.sender])[_countries[i]] == false, "CountryRestrictModule: country already restricted");
            (_restrictedCountries[msg.sender])[_countries[i]] = true;
            emit CountryRestricted(msg.sender, _countries[i]);
        }
    }

    /**
     * @dev Unrestrict multiple countries at once
     * @param _countries The country codes to unrestrict
     */
    function batchUnrestrictCountries(uint16[] calldata _countries) external onlyComplianceCall {
        require(_countries.length < 195, "maximum 195 can be unrestricted in one batch");
        for (uint256 i = 0; i < _countries.length; i++) {
            require((_restrictedCountries[msg.sender])[_countries[i]] == true, "CountryRestrictModule: country not restricted");
            (_restrictedCountries[msg.sender])[_countries[i]] = false;
            emit CountryUnrestricted(msg.sender, _countries[i]);
        }
    }

    /**
     * @dev Check if a country is restricted
     * @param _compliance The address of the compliance to check
     * @param _country The country code to check
     * @return true if the country is restricted, false otherwise
     */
    function isCountryRestricted(address _compliance, uint16 _country) public view returns (bool) {
        return ((_restrictedCountries[_compliance])[_country]);
    }

    /**
     * @dev Check if compliance can bind to this module
     * @return true if the compliance can bind to this module, false otherwise
     */
    function canComplianceBind(address /* _compliance */) external pure override returns (bool) {
        return true;
    }

    /**
     * @dev Check if module is plug and play
     * @return true if the module is plug and play, false otherwise
     */
    function isPlugAndPlay() external pure override returns (bool) {
        return true;
    }

    /**
     * @dev Module transfer action (no state changes needed)
     */
    function moduleTransferAction(address _from, address _to, uint256 _value) 
        external 
        override 
        onlyBoundCompliance(msg.sender) 
    {
        // No action needed
    }

    /**
     * @dev Module mint action (no state changes needed)
     */
    function moduleMintAction(address _to, uint256 _value) 
        external 
        override 
        onlyBoundCompliance(msg.sender) 
    {
        // No action needed
    }

    /**
     * @dev Module burn action (no state changes needed)
     */
    function moduleBurnAction(address _from, uint256 _value) 
        external 
        override 
        onlyBoundCompliance(msg.sender) 
    {
        // No action needed
    }

    /**
     * @dev Module check - verify country restrictions
     */
    function moduleCheck(
        address /* _from */,
        address _to,
        uint256 /* _value */,
        address _compliance
    ) external view override returns (bool) {
        IModularCompliance modularCompliance = IModularCompliance(_compliance);
        address tokenBound = modularCompliance.getTokenBound();
        IIdentityRegistry identityRegistry = ILuxShareToken(tokenBound).identityRegistry();
        uint16 toCountry = identityRegistry.investorCountry(_to);
        return !isCountryRestricted(_compliance, toCountry);
    }

    /**
     * @dev Get module name
     */
    function name() external pure override returns (string memory) {
        return "CountryRestrictModule";
    }
}
