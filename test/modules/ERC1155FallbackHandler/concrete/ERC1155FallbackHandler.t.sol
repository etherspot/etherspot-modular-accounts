// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {ModuleManager} from "ERC7579/core/ModuleManager.sol";
import {CALLTYPE_SINGLE} from "ERC7579/libs/ModeLib.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ERC1155FallbackHandler} from "../../../../src/modules/fallbacks/ERC1155FallbackHandler.sol";
import {TestERC1155} from "../../../../src/test/TestERC1155.sol";
import "../../../ModularTestBase.sol";
import {console2} from "forge-std/console2.sol";

contract ERC1155FallbackHandlerTest is ModularTestBase {
    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    bytes4 internal immutable ON_RECEIVED_SELECTOR =
        bytes4(erc1155fb.onERC1155Received.selector);
    bytes4 internal immutable ON_BATCH_RECEIVED_SELECTOR =
        bytes4(erc1155fb.onERC1155BatchReceived.selector);
    TestERC1155 enjin;
    TestERC1155 axie;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        _testInit();
        // Deploy ERC1155 tokens
        enjin = new TestERC1155();
        axie = new TestERC1155();
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    // @dev Should install fallback handler
    function test_installERC1155Fallback() public {
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Expect event to be emitted on installation of fallback handler
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155FallbackHandlerInstalled(
            address(scw)
        );
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
    }

    // @dev Should install fallback handler with multiple allowed callers
    function test_installERC1155Fallback_multipleTokens() public {
        // Create allowed caller list (token addresses will be calling fallback handler)
        address[] memory tokens = new address[](2);
        tokens[0] = address(enjin);
        tokens[1] = address(axie);
        // Expect event to be emitted on installation of fallback handler
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155FallbackHandlerInstalled(
            address(scw)
        );
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
    }

    // @dev Should install without allowed callers but will fail to call fallback handler
    function test_installERC1155Fallback_noTokens() public {
        // Create empty allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](0);
        // Expect event to be emitted on installation of fallback handler
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155FallbackHandlerInstalled(
            address(scw)
        );
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
    }

    // @dev Should fail if fallback handler is already installed for specified selector
    function test_installERC1155Fallback_revertIf_sameSelector() public {
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler enjin
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
        // Create allowed caller list (token address will be calling fallback handler)
        tokens[0] = address(axie);
        // Expect revert as only one fallback handler can be installed for a given selector
        vm.expectRevert("Function selector already used");
        // Install fallback handler enjin
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
    }

    // @dev Should uninstall the fallback handler
    function test_uninstallERC1155Fallback() public {
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
        // Expect event to be emitted on uninstallation of fallback handler
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155FallbackHandlerUninstalled(
            address(scw)
        );
        // Install fallback handler
        _uninstallModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR)
        );
    }

    // @dev Should return correct module type
    function test_isModuleType() public {
        // Should be of type fallback
        assertTrue(erc1155fb.isModuleType(MODULE_TYPE_FALLBACK));
    }

    // @dev Should allow minting of ERC1155 token to modular wallet
    function test_mintERC1155() public {
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
        // Prank as modular wallet
        vm.startPrank(address(scw));
        // Expect event to be emitted on receive of ERC1155 token
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155Received(
            address(scw),
            address(0),
            100,
            1,
            hex""
        );
        // Mint enjin (and check balance)
        enjin.mint(address(scw), 100, 1, hex"");
        assertEq(enjin.balanceOf(address(scw), 100), 1);
    }

    // @dev Should allow minting of multiple ERC1155 token to modular wallet
    function test_mintERC1155_multipleTokens() public {
        // Create allowed caller list (token addresses will be calling fallback handler)
        address[] memory tokens = new address[](2);
        tokens[0] = address(enjin);
        tokens[1] = address(axie);
        // Install fallback handler for multiple tokens
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
        // Prank as modular wallet
        vm.startPrank(address(scw));
        // Mint enjin (and check balance)
        enjin.mint(address(scw), 100, 1, hex"");
        assertEq(enjin.balanceOf(address(scw), 100), 1);
        // Mint axie (and check balance)
        axie.mint(address(scw), 200, 1, hex"");
        assertEq(axie.balanceOf(address(scw), 200), 1);
    }

    // @dev Should not allow minting of ERC1155 token to modular wallet if selector is incorrect
    function test_mintERC1155_revertIf_wrongSelector() public {
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler with batch selector
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(
                ON_BATCH_RECEIVED_SELECTOR,
                CALLTYPE_SINGLE,
                tokens,
                hex""
            )
        );
        // Prank as modular wallet
        vm.startPrank(address(scw));
        // Expect revert due to incorrect selector
        _toRevert(
            ModuleManager.InvalidFallbackCaller.selector,
            abi.encode(address(enjin))
        );
        // Mint enjin (fallback handler only allowing ERC1155 batches)
        enjin.mint(address(scw), 100, 1, hex"");
    }

    // @dev Should not allow minting of ERC1155 token to modular wallet if not allowed caller
    function test_mintERC1155_revertIf_wrongAllowedCaller() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(
                ON_BATCH_RECEIVED_SELECTOR,
                CALLTYPE_SINGLE,
                tokens,
                hex""
            )
        );
        // Prank as modular wallet
        vm.startPrank(address(scw));
        // Expect to revert due to incorrect allowed caller (token address)
        _toRevert(
            ModuleManager.InvalidFallbackCaller.selector,
            abi.encode(address(axie))
        );
        // Mint axie (which isn't an allowed caller of the fallback handler)
        axie.mint(address(scw), 100, 1, hex"");
    }

    // @dev Should not allow minting of ERC1155 token to modular wallet if no allowed callers set
    function test_mintERC1155_revertIf_noAllowedCallers() public {
        address[] memory tokens = new address[](0);
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(
                ON_BATCH_RECEIVED_SELECTOR,
                CALLTYPE_SINGLE,
                tokens,
                hex""
            )
        );
        // Prank as modular wallet
        vm.startPrank(address(scw));
        // Expect to revert due to incorrect allowed caller (token address)
        _toRevert(
            ModuleManager.InvalidFallbackCaller.selector,
            abi.encode(address(axie))
        );
        // Mint axie (which isn't an allowed caller of the fallback handler)
        axie.mint(address(scw), 100, 1, hex"");
    }

    // @dev Should allow receiving of ERC1155 token to modular wallet
    function test_receiveERC1155() public {
        // Prank as eoa.pub
        vm.startPrank(eoa.pub);
        // Mint enjin (and check balance)
        enjin.mint(address(eoa.pub), 100, 1, hex"");
        assertEq(enjin.balanceOf(address(eoa.pub), 100), 1);
        vm.stopPrank();
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
        // Prank as eoa.pub
        vm.startPrank(eoa.pub);
        // Attempt to transfer (and check balances)
        enjin.safeTransferFrom(address(eoa.pub), address(scw), 100, 1, hex"");
        assertEq(enjin.balanceOf(address(eoa.pub), 100), 0);
        assertEq(enjin.balanceOf(address(scw), 100), 1);
    }

    // @dev Should allow batch minting of ERC1155 token to modular wallet
    function test_mintBatchERC1155() public {
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(
                ON_BATCH_RECEIVED_SELECTOR,
                CALLTYPE_SINGLE,
                tokens,
                hex""
            )
        );
        // Prank as modular wallet
        vm.startPrank(address(scw));
        // Mint batch
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        // Expect event to be emitted on receive of ERC1155 batch
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155BatchReceived(
            address(scw),
            address(0),
            ids,
            amounts,
            hex""
        );
        enjin.batchMint(address(scw), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(scw);
        owners[1] = address(scw);
        uint256[] memory balances = enjin.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        vm.stopPrank();
    }

    // @dev Should allow batch minting of multiple ERC1155 token to modular wallet
    function test_mintBatchERC1155_multipleTokens() public {
        // Create allowed caller list (token addresses will be calling fallback handler)
        address[] memory tokens = new address[](2);
        tokens[0] = address(enjin);
        tokens[1] = address(axie);
        // Install fallback handler for multiple tokens
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(
                ON_BATCH_RECEIVED_SELECTOR,
                CALLTYPE_SINGLE,
                tokens,
                hex""
            )
        );
        // Prank as modular wallet
        vm.startPrank(address(scw));
        // Mint batch enjin
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        enjin.batchMint(address(scw), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(scw);
        owners[1] = address(scw);
        uint256[] memory balances = enjin.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        // Mint batch axie
        ids[0] = 200;
        ids[1] = 201;
        axie.batchMint(address(scw), ids, amounts, hex"");
        // Check balances
        balances = axie.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        vm.stopPrank();
    }

    // @dev Should allow receiving batch of ERC1155 token to modular wallet
    function test_receiveBatchERC1155() public {
        // Prank as eoa.pub
        vm.startPrank(eoa.pub);
        // Mint batch
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        enjin.batchMint(address(eoa.pub), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(eoa.pub);
        owners[1] = address(eoa.pub);
        uint256[] memory eoaBalances = enjin.balanceOfBatch(owners, ids);
        assertEq(eoaBalances[0], 1);
        assertEq(eoaBalances[1], 10000);
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(
                ON_BATCH_RECEIVED_SELECTOR,
                CALLTYPE_SINGLE,
                tokens,
                hex""
            )
        );
        // Prank as eoa.pub
        vm.startPrank(eoa.pub);
        // Attempt to transfer
        enjin.safeBatchTransferFrom(
            address(eoa.pub),
            address(scw),
            ids,
            amounts,
            hex""
        );
        // Check balances
        eoaBalances = enjin.balanceOfBatch(owners, ids);
        owners[0] = address(scw);
        owners[1] = address(scw);
        uint256[] memory mewBalances = enjin.balanceOfBatch(owners, ids);
        assertEq(eoaBalances[0], 0);
        assertEq(eoaBalances[1], 0);
        assertEq(mewBalances[0], 1);
        assertEq(mewBalances[1], 10000);
        vm.stopPrank();
    }

    // @dev Should allow minting of multiple ERC1155 tokens to modular wallet for different selectors
    function test_mintERC1155_multipleTokens_multipleSelectors() public {
        // Create allowed caller list (token addresses will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(enjin);
        // Install fallback handler for Enjin with onERC1155Received selector
        // Install fallback handler
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(ON_RECEIVED_SELECTOR, CALLTYPE_SINGLE, tokens, hex"")
        );
        tokens[0] = address(axie);
        // Install fallback handler for Axie with onERC1155BatchReceived selector
        _installModule(
            eoa.pub,
            scw,
            MODULE_TYPE_FALLBACK,
            address(erc1155fb),
            abi.encode(
                ON_BATCH_RECEIVED_SELECTOR,
                CALLTYPE_SINGLE,
                tokens,
                hex""
            )
        );
        // Prank as modular wallet
        vm.startPrank(address(scw));
        // Mint enjin (and check balance)
        enjin.mint(address(scw), 100, 1, hex"");
        assertEq(enjin.balanceOf(address(scw), 100), 1);
        // Mint axie batch (and check balance)
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        axie.batchMint(address(scw), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(scw);
        owners[1] = address(scw);
        uint256[] memory balances = axie.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        vm.stopPrank();
    }
}
