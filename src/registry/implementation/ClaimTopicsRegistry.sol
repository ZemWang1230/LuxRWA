// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

import "../interface/IClaimTopicsRegistry.sol";
import "../storage/RegistryStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ClaimTopicsRegistry
 * @dev Implementation of IClaimTopicsRegistry using Diamond Storage pattern
 * @notice Manages claim topics required for investor verification
 */
contract ClaimTopicsRegistry is IClaimTopicsRegistry, Ownable {
    using RegistryStorage for RegistryStorage.ClaimTopicsRegistryLayout;

    /**
     * @dev Constructor
     * @notice This constructor is used to initialize the ClaimTopicsRegistry
     * Set the owner of the ClaimTopicsRegistry to the msg.sender
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Add a trusted claim topic (For example: KYC=1, AML=2).
     * Only owner can call.
     * emits `ClaimTopicAdded` event
     * cannot add more than 15 topics for 1 token as adding more could create gas issues
     * @param _claimTopic The claim topic index
     */
    function addClaimTopic(uint256 _claimTopic) external override onlyOwner {
        RegistryStorage.ClaimTopicsRegistryLayout storage s = RegistryStorage.claimTopicsLayout();
        
        require(!s.claimTopicExists[_claimTopic], "ClaimTopicsRegistry: topic already exists");
        require(s.claimTopics.length < 15, "ClaimTopicsRegistry: cannot add more than 15 topics");

        s.claimTopics.push(_claimTopic);
        s.claimTopicExists[_claimTopic] = true;

        emit ClaimTopicAdded(_claimTopic);
    }

    /**
     * @dev Remove a trusted claim topic (For example: KYC=1, AML=2).
     * Only owner can call.
     * emits `ClaimTopicRemoved` event
     * @param _claimTopic The claim topic index
     */
    function removeClaimTopic(uint256 _claimTopic) external override onlyOwner {
        RegistryStorage.ClaimTopicsRegistryLayout storage s = RegistryStorage.claimTopicsLayout();
        
        require(s.claimTopicExists[_claimTopic], "ClaimTopicsRegistry: topic does not exist");

        // Find and remove the topic from the array
        uint256 length = s.claimTopics.length;
        for (uint256 i = 0; i < length; i++) {
            if (s.claimTopics[i] == _claimTopic) {
                s.claimTopics[i] = s.claimTopics[length - 1];
                s.claimTopics.pop();
                break;
            }
        }

        delete s.claimTopicExists[_claimTopic];

        emit ClaimTopicRemoved(_claimTopic);
    }

    /**
     * @dev Get the trusted claim topics for the security token
     * @return Array of trusted claim topics
     */
    function getClaimTopics() external view override returns (uint256[] memory) {
        return RegistryStorage.claimTopicsLayout().claimTopics;
    }
}

