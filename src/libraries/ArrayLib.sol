// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @title ArrayLib
/// @author @cryptonoyaiba | Etherspot
/// @notice Library for common array operations
/// @dev Provides utility functions for address arrays
library ArrayLib {
    /// @notice Checks if an array contains a specific address
    /// @param _A The array to search in
    /// @param _a The address to search for
    /// @return bool True if the address is in the array, false otherwise
    function _contains(address[] memory _A, address _a) internal pure returns (bool) {
        (, bool isIn) = _indexOf(_A, _a);
        return isIn;
    }

    /// @notice Finds the index of an address in an array
    /// @param _A The array to search in
    /// @param _a The address to search for
    /// @return uint256 The index of the address in the array
    /// @return bool True if the address is found, false otherwise
    function _indexOf(address[] memory _A, address _a) internal pure returns (uint256, bool) {
        uint256 length = _A.length;
        for (uint256 i; i < length; ++i) {
            if (_A[i] == _a) {
                return (i, true);
            }
        }
        return (0, false);
    }

    /// @notice Removes an element from a storage array
    /// @dev Replaces the element with the last element and pops the array
    /// @param _data The storage array to modify
    /// @param _element The address element to remove
    function _removeElement(address[] storage _data, address _element) internal {
        uint256 length = _data.length;
        // remove item from array and resize array
        for (uint256 i; i < length; ++i) {
            if (_data[i] == _element) {
                if (length > 1) {
                    _data[i] = _data[length - 1];
                }
                _data.pop();
                break;
            }
        }
    }

    /// @notice Removes an element from a memory array
    /// @dev Creates a new array without the specified element
    /// @param _data The memory array to process
    /// @param _element The address element to remove
    /// @return address[] A new array without the specified element
    function _removeElement(address[] memory _data, address _element) internal pure returns (address[] memory) {
        address[] memory newData = new address[](_data.length - 1);
        uint256 j;
        for (uint256 i; i < _data.length; ++i) {
            if (_data[i] != _element) {
                newData[j] = _data[i];
                ++j;
            }
        }
        return newData;
    }
}
