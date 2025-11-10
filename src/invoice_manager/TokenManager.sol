// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ITokenManager} from "../interfaces/ITokenManager.sol";
import {TokenData} from "../common/Structs.sol";

/**
 * @title TokenManager
 * @notice Manages token whitelisting for invoice processing
 * @author Etherspot
 * @dev Provides token whitelist management functionality to be inherited by InvoiceManager
 */
abstract contract TokenManager is ITokenManager, AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    EnumerableSet.AddressSet internal whitelistedTokens;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error TM_InvalidAddress();
    error TM_TokenNotWhitelisted(address token);
    error TM_TokenAlreadyWhitelisted(address token);
    error TM_EmptyTokenData();

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyWhitelistedTokens(TokenData[] calldata _tokenData) {
        uint256 tokenDataLength = _tokenData.length;
        for (uint256 i; i < tokenDataLength; ++i) {
            if (!whitelistedTokens.contains(_tokenData[i].token)) {
                revert TM_TokenNotWhitelisted(_tokenData[i].token);
            }
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    TOKEN WHITELIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc ITokenManager
    function addTokenToWhitelist(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_token == address(0)) revert TM_InvalidAddress();
        if (whitelistedTokens.contains(_token)) revert TM_TokenAlreadyWhitelisted(_token);

        whitelistedTokens.add(_token);
        emit TokenWhitelisted(_token, msg.sender);
    }

    // @inheritdoc ITokenManager
    function addTokensToWhitelist(address[] calldata _tokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokensLength = _tokens.length;
        if (tokensLength == 0) revert TM_EmptyTokenData();
        for (uint256 i; i < tokensLength; ++i) {
            address token = _tokens[i];
            if (token == address(0)) revert TM_InvalidAddress();
            if (!whitelistedTokens.contains(token)) {
                whitelistedTokens.add(token);
                emit TokenWhitelisted(token, msg.sender);
            }
        }
    }

    // @inheritdoc ITokenManager
    function removeTokenFromWhitelist(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!whitelistedTokens.contains(_token)) revert TM_TokenNotWhitelisted(_token);
        whitelistedTokens.remove(_token);
        emit TokenRemovedFromWhitelist(_token, msg.sender);
    }

    // @inheritdoc ITokenManager
    function removeTokensFromWhitelist(address[] calldata _tokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokensLength = _tokens.length;
        for (uint256 i; i < tokensLength; ++i) {
            address token = _tokens[i];
            if (whitelistedTokens.contains(token)) {
                whitelistedTokens.remove(token);
                emit TokenRemovedFromWhitelist(token, msg.sender);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // @inheritdoc ITokenManager
    function isTokenWhitelisted(address _token) external view returns (bool) {
        return whitelistedTokens.contains(_token);
    }

    // @inheritdoc ITokenManager
    function getWhitelistedTokens() external view returns (address[] memory) {
        return whitelistedTokens.values();
    }

    // @inheritdoc ITokenManager
    function getWhitelistedTokensCount() external view returns (uint256) {
        return whitelistedTokens.length();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to check if a token is whitelisted
     * @param _token Token address to check
     * @return True if token is whitelisted
     */
    function _isTokenWhitelisted(address _token) internal view returns (bool) {
        return whitelistedTokens.contains(_token);
    }

    /**
     * @notice Internal function to validate token data
     * @param _tokenData Array of token data to validate
     * @dev Reverts if any token is not whitelisted or has zero amount
     */
    function _validateTokenData(TokenData[] memory _tokenData) internal view {
        uint256 tokenDataLength = _tokenData.length;
        if (tokenDataLength == 0) revert TM_EmptyTokenData();

        for (uint256 i; i < tokenDataLength; ++i) {
            if (!whitelistedTokens.contains(_tokenData[i].token)) {
                revert TM_TokenNotWhitelisted(_tokenData[i].token);
            }
        }
    }
}
