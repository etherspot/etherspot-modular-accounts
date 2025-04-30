// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {IERC7579Account} from "../../../../src/interfaces/base/IERC7579Account.sol";
import {MODULE_TYPE_VALIDATOR} from "../../../../src/types/Constants.sol";
import {ModularTestBase} from "../../../ModularTestBase.sol";

contract GuardianRecoveryTestUtils is ModularTestBase {
    // Guardian addresses
    address[] guardians;

    /*//////////////////////////////////////////////////////////////
                        TEST HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _testSetup() internal {
        _testInit();
        guardians = new address[](3);
        guardians[0] = guardian1.pub;
        guardians[1] = guardian2.pub;
        guardians[2] = guardian3.pub;
    }

    // Install validator with minimal setup - just one owner
    function _installValidatorWithSetup() internal {
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = eoa.pub;
        address[] memory initialGuardians = new address[](0);
        bytes memory initData = abi.encode(initialOwners, initialGuardians);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
    }

    // Install validator with one owner and all three guardians
    function _installValidatorWithAllGuardians() internal {
        address[] memory initialOwners = new address[](1);
        initialOwners[0] = eoa.pub;
        bytes memory initData = abi.encode(initialOwners, guardians);
        _installModule(eoa.pub, SCW, MODULE_TYPE_VALIDATOR, address(GUARDIAN_RECOVERY_VALIDATOR), initData);
    }

    // Add guardians to a wallet after installation
    function _addGuardians(address walletAddress) internal {
        for (uint256 i; i < guardians.length; ++i) {
            vm.prank(eoa.pub);
            MOCK_EXECUTOR.executeViaAccount(
                IERC7579Account(walletAddress),
                address(GUARDIAN_RECOVERY_VALIDATOR),
                0,
                abi.encodeWithSelector(GUARDIAN_RECOVERY_VALIDATOR.addGuardian.selector, walletAddress, guardians[i])
            );
        }
    }

    // Get the current proposal information in a readable format
    function _getProposalInfo(address walletAddress, uint256 proposalId)
        internal
        view
        returns (
            address proposedOwner,
            uint256 approvalCount,
            address[] memory approvers,
            bool resolved,
            uint256 proposedAt
        )
    {
        return GUARDIAN_RECOVERY_VALIDATOR.getProposal(walletAddress, proposalId);
    }
}
