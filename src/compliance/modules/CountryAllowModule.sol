// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "./AbstractModule.sol";
import "../../registry/interface/IIdentityRegistry.sol";
import "../interface/IModularCompliance.sol";
import "../../token/interface/ILuxShareToken.sol";

/**
 * @title CountryAllowModule
 * @dev Module that allows only specific countries to hold/receive tokens
 * @notice Whitelist-based country restriction
 */
contract CountryAllowModule is AbstractModule {
    // Mapping: compliance => country code => allowed
    mapping(address => mapping(uint16 => bool)) private _allowedCountries;

    event CountryAllowed(address indexed compliance, uint16 indexed country);
    event CountryDisallowed(address indexed compliance, uint16 indexed country);

    /**
     * @dev Allow multiple countries at once
     * @param _countries The country codes to allow
     */
    function batchAllowCountries(uint16[] calldata _countries) external onlyComplianceCall {
        for (uint256 i = 0; i < _countries.length; i++) {
            _allowedCountries[msg.sender][_countries[i]] = true;
            emit CountryAllowed(msg.sender, _countries[i]);
        }
    }

    /**
     * @dev Disallow multiple countries at once
     * @param _countries The country codes to disallow
     */
    function batchDisallowCountries(uint16[] calldata _countries) external onlyComplianceCall {
        for (uint256 i = 0; i < _countries.length; i++) {
            _allowedCountries[msg.sender][_countries[i]] = false;
            emit CountryDisallowed(msg.sender, _countries[i]);
        }
    }

    /** 
     * @dev Allow a country
     * @param _country The country code to allow
     */
    function allowCountry(uint16 _country) external onlyComplianceCall {
        require(!_allowedCountries[msg.sender][_country], "CountryAllowModule: country already allowed");
        _allowedCountries[msg.sender][_country] = true;
        emit CountryAllowed(msg.sender, _country);
    }

    /**
     * @dev Disallow a country
     * @param _country The country code to disallow
     */
    function disallowCountry(uint16 _country) external onlyComplianceCall {
        require(_allowedCountries[msg.sender][_country], "CountryAllowModule: country not allowed");
        _allowedCountries[msg.sender][_country] = false;
        emit CountryDisallowed(msg.sender, _country);
    }

    /**
     * @dev Check if a country is allowed
     * @param _compliance The address of the compliance to check
     * @param _country The country code to check
     * @return true if the country is allowed, false otherwise
     */
    function isCountryAllowed(address _compliance, uint16 _country) public view returns (bool) {
        return _allowedCountries[_compliance][_country];
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
     * @param _to The user address of the recipient
     * @param _compliance The address of the compliance contract
     * @return true if the transfer is allowed, false otherwise
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
        return isCountryAllowed(_compliance, toCountry);
    }

    /**
     * @dev Get module name
     */
    function name() external pure override returns (string memory) {
        return "CountryAllowModule";
    }
}
