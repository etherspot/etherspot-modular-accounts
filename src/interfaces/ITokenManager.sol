// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {TokenData} from "../common/Structs.sol";

/**
 * @title ITokenManager
 * @notice Interface for token whitelisting management functionality
 * @author Etherspot
 */
interface ITokenManager {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenWhitelisted(address indexed token, address indexed addedBy);
    event TokenRemovedFromWhitelist(address indexed token, address indexed removedBy);

    /*//////////////////////////////////////////////////////////////
                    TOKEN WHITELIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a token to the whitelist
     * @param _token The token address to whitelist
     */
    function addTokenToWhitelist(address _token) external;

    /**
     * @notice Add multiple tokens to the whitelist
     * @param _tokens Array of token addresses to whitelist
     */
    function addTokensToWhitelist(address[] calldata _tokens) external;

    /**
     * @notice Remove a token from the whitelist
     * @param _token The token address to remove from whitelist
     */
    function removeTokenFromWhitelist(address _token) external;

    /**
     * @notice Remove multiple tokens from the whitelist
     * @param _tokens Array of token addresses to remove from whitelist
     */
    function removeTokensFromWhitelist(address[] calldata _tokens) external;

    /*//////////////////////////////////////////////////////////////
                        TOKEN VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a token is whitelisted
     * @param _token The token address to check
     * @return bool True if token is whitelisted
     */
    function isTokenWhitelisted(address _token) external view returns (bool);

    /**
     * @notice Get all whitelisted tokens
     * @return address[] Array of whitelisted token addresses
     */
    function getWhitelistedTokens() external view returns (address[] memory);

    /**
     * @notice Get the number of whitelisted tokens
     * @return uint256 Number of whitelisted tokens
     */
    function getWhitelistedTokensCount() external view returns (uint256);
}