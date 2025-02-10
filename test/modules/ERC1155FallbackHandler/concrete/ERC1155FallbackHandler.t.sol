// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {ModuleManager} from "../../../../src/erc7579-ref-impl/core/ModuleManager.sol";
import {CALLTYPE_SINGLE} from "../../../../src/erc7579-ref-impl/libs/ModeLib.sol";
import {MODULE_TYPE_FALLBACK} from "../../../../src/erc7579-ref-impl/interfaces/IERC7579Module.sol";
import {ModularEtherspotWallet} from "../../../../src/wallet/ModularEtherspotWallet.sol";
import {ERC1155FallbackHandler} from "../../../../src/modules/fallbacks/ERC1155FallbackHandler.sol";
import {TestERC1155} from "../../../../src/test/TestERC1155.sol";
import "../../../TestAdvancedUtils.t.sol";
import {console2} from "forge-std/console2.sol";

contract ERC1155FallbackHandlerTest is TestAdvancedUtils {
    ModularEtherspotWallet mew;
    TestERC1155 tokenA;
    TestERC1155 tokenB;
    ERC1155FallbackHandler fallback1155;

    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/

    // Installs fallback handler
    function _installERC1155Fallback(
        bytes4 _selector,
        address[] memory _tokens
    ) internal {
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Setup initCode
        bytes memory initData = abi.encode(
            _selector,
            CALLTYPE_SINGLE,
            _tokens,
            hex""
        );
        // Install ERC1155FallbackHandler
        mew.installModule(
            MODULE_TYPE_FALLBACK,
            address(fallback1155),
            initData
        );
        vm.stopPrank();
    }

    // @dev Uninstalls fallback handler
    function _uninstallERC1155Fallback(bytes4 _selector) internal {
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Uninstall ERC1155FallbackHandler
        mew.uninstallModule(
            MODULE_TYPE_FALLBACK,
            address(fallback1155),
            abi.encode(_selector)
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               TESTING
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
        // Deploy ERC1155 tokens
        tokenA = new TestERC1155();
        tokenB = new TestERC1155();
        // Deploy fallback handler
        fallback1155 = new ERC1155FallbackHandler();
    }

    // @dev Should install fallback handler
    function test_installERC1155Fallback() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Expect event to be emitted on installation of fallback handler
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155FallbackHandlerInstalled(
            address(mew)
        );
        // Install fallback handler
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
    }

    // @dev Should install fallback handler with multiple allowed callers
    function test_installERC1155Fallback_multipleTokens() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token addresses will be calling fallback handler)
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        // Expect event to be emitted on installation of fallback handler
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155FallbackHandlerInstalled(
            address(mew)
        );
        // Install fallback handler with multiple allowed callers
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
    }

    // @dev Should install without allowed callers but will fail to call fallback handler
    function test_installERC1155Fallback_noTokens() public {
        // Setup environment
        mew = setupMEW();
        // Create empty allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](0);
        // Expect event to be emitted on installation of fallback handler
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155FallbackHandlerInstalled(
            address(mew)
        );
        // Install fallback handler
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
    }

    // @dev Should fail if fallback handler is already installed for specified selector
    function test_installERC1155Fallback_revertIf_sameSelector() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Install fallback handler tokenA
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
        // Create allowed caller list (token address will be calling fallback handler)
        tokens[0] = address(tokenB);
        // Expect revert as only one fallback handler can be installed for a given selector
        vm.expectRevert("Function selector already used");
        // Install fallback handler tokenA
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
    }

    // @dev Should uninstall the fallback handler
    function test_uninstallERC1155Fallback() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Install fallback handler
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
        // Expect event to be emitted on uninstallation of fallback handler
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155FallbackHandlerUninstalled(
            address(mew)
        );
        // Uninstall fallback handler
        _uninstallERC1155Fallback(fallback1155.onERC1155Received.selector);
    }

    // @dev Should return correct module type
    function test_isModuleType() public {
        // Should be of type fallback
        assertTrue(fallback1155.isModuleType(MODULE_TYPE_FALLBACK));
    }

    // @dev Should allow minting of ERC1155 token to modular wallet
    function test_mintERC1155() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Install fallback handler
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Expect event to be emitted on receive of ERC1155 token
        vm.expectEmit(true, true, true, true);
        emit ERC1155FallbackHandler.ERC1155Received(
            address(mew),
            address(0),
            100,
            1,
            hex""
        );
        // Mint tokenA (and check balance)
        tokenA.mint(address(mew), 100, 1, hex"");
        assertEq(tokenA.balanceOf(address(mew), 100), 1);
    }

    // @dev Should allow minting of multiple ERC1155 token to modular wallet
    function test_mintERC1155_multipleTokens() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token addresses will be calling fallback handler)
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        // Install fallback handler for multiple tokens
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Mint tokenA (and check balance)
        tokenA.mint(address(mew), 100, 1, hex"");
        assertEq(tokenA.balanceOf(address(mew), 100), 1);
        // Mint tokenB (and check balance)
        tokenB.mint(address(mew), 200, 1, hex"");
        assertEq(tokenB.balanceOf(address(mew), 200), 1);
    }

    // @dev Should not allow minting of ERC1155 token to modular wallet if selector is incorrect
    function test_mintERC1155_revertIf_wrongSelector() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Install fallback handler with batch selector
        _installERC1155Fallback(
            fallback1155.onERC1155BatchReceived.selector,
            tokens
        );
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Expect revert due to incorrect selector
        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleManager.InvalidFallbackCaller.selector,
                address(tokenA)
            )
        );
        // Mint tokenA (fallback handler only allowing ERC1155 batches)
        tokenA.mint(address(mew), 100, 1, hex"");
    }

    // @dev Should not allow minting of ERC1155 token to modular wallet if not allowed caller
    function test_mintERC1155_revertIf_wrongAllowedCaller() public {
        mew = setupMEW();
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        _installERC1155Fallback(
            fallback1155.onERC1155BatchReceived.selector,
            tokens
        );
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Expect to revert due to incorrect allowed caller (token address)
        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleManager.InvalidFallbackCaller.selector,
                address(tokenB)
            )
        );
        // Mint tokenB (which isn't an allowed caller of the fallback handler)
        tokenB.mint(address(mew), 100, 1, hex"");
    }

    // @dev Should not allow minting of ERC1155 token to modular wallet if no allowed callers set
    function test_mintERC1155_revertIf_noAllowedCallers() public {
        mew = setupMEW();
        address[] memory tokens = new address[](0);
        _installERC1155Fallback(
            fallback1155.onERC1155BatchReceived.selector,
            tokens
        );
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Expect to revert due to incorrect allowed caller (token address)
        vm.expectRevert(
            abi.encodeWithSelector(
                ModuleManager.InvalidFallbackCaller.selector,
                address(tokenB)
            )
        );
        // Mint tokenB (which isn't an allowed caller of the fallback handler)
        tokenB.mint(address(mew), 100, 1, hex"");
    }

    // @dev Should allow receiving of ERC1155 token to modular wallet
    function test_receiveERC1155() public {
        // Ensure owner1 has enough ETH to pay for gas
        vm.deal(address(owner1), 3 ether);
        // Setup environment
        mew = setupMEW();
        // Prank as owner1
        vm.startPrank(owner1);
        // Mint tokenA (and check balance)
        tokenA.mint(address(owner1), 100, 1, hex"");
        assertEq(tokenA.balanceOf(address(owner1), 100), 1);
        vm.stopPrank();
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Install fallback handler
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
        // Prank as owner1
        vm.startPrank(owner1);
        // Attempt to transfer (and check balances)
        tokenA.safeTransferFrom(address(owner1), address(mew), 100, 1, hex"");
        assertEq(tokenA.balanceOf(address(owner1), 100), 0);
        assertEq(tokenA.balanceOf(address(mew), 100), 1);
    }

    // @dev Should allow batch minting of ERC1155 token to modular wallet
    function test_mintBatchERC1155() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Install fallback handler
        _installERC1155Fallback(
            fallback1155.onERC1155BatchReceived.selector,
            tokens
        );
        // Prank as modular wallet
        vm.startPrank(address(mew));
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
            address(mew),
            address(0),
            ids,
            amounts,
            hex""
        );
        tokenA.batchMint(address(mew), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(mew);
        owners[1] = address(mew);
        uint256[] memory balances = tokenA.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        vm.stopPrank();
    }

    // @dev Should allow batch minting of multiple ERC1155 token to modular wallet
    function test_mintBatchERC1155_multipleTokens() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token addresses will be calling fallback handler)
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        // Install fallback handler for multiple tokens
        _installERC1155Fallback(
            fallback1155.onERC1155BatchReceived.selector,
            tokens
        );
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Mint batch tokenA
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        tokenA.batchMint(address(mew), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(mew);
        owners[1] = address(mew);
        uint256[] memory balances = tokenA.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        // Mint batch tokenB
        ids[0] = 200;
        ids[1] = 201;
        tokenB.batchMint(address(mew), ids, amounts, hex"");
        // Check balances
        balances = tokenB.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        vm.stopPrank();
    }

    // @dev Should allow receiving batch of ERC1155 token to modular wallet
    function test_receiveBatchERC1155() public {
        // Ensure owner1 has enough ETH to pay for gas
        vm.deal(address(owner1), 3 ether);
        // Setup environment
        mew = setupMEW();
        // Prank as owner1
        vm.startPrank(owner1);
        // Mint batch
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        tokenA.batchMint(address(owner1), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(owner1);
        owners[1] = address(owner1);
        uint256[] memory owner1Balances = tokenA.balanceOfBatch(owners, ids);
        assertEq(owner1Balances[0], 1);
        assertEq(owner1Balances[1], 10000);
        // Create allowed caller list (token address will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Install fallback handler
        _installERC1155Fallback(
            fallback1155.onERC1155BatchReceived.selector,
            tokens
        );
        // Prank as owner1
        vm.startPrank(owner1);
        // Attempt to transfer
        tokenA.safeBatchTransferFrom(
            address(owner1),
            address(mew),
            ids,
            amounts,
            hex""
        );
        // Check balances
        owner1Balances = tokenA.balanceOfBatch(owners, ids);
        owners[0] = address(mew);
        owners[1] = address(mew);
        uint256[] memory mewBalances = tokenA.balanceOfBatch(owners, ids);
        assertEq(owner1Balances[0], 0);
        assertEq(owner1Balances[1], 0);
        assertEq(mewBalances[0], 1);
        assertEq(mewBalances[1], 10000);
        vm.stopPrank();
    }

    // @dev Should allow minting of multiple ERC1155 tokens to modular wallet for different selectors
    function test_mintERC1155_multipleTokens_multipleSelectors() public {
        // Setup environment
        mew = setupMEW();
        // Create allowed caller list (token addresses will be calling fallback handler)
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        // Install fallback handler for tokensA with onERC1155Received selector
        _installERC1155Fallback(
            fallback1155.onERC1155Received.selector,
            tokens
        );
        tokens[0] = address(tokenB);
        // Install fallback handler for tokensA with onERC1155BatchReceived selector
        _installERC1155Fallback(
            fallback1155.onERC1155BatchReceived.selector,
            tokens
        );
        // Prank as modular wallet
        vm.startPrank(address(mew));
        // Mint tokenA (and check balance)
        tokenA.mint(address(mew), 100, 1, hex"");
        assertEq(tokenA.balanceOf(address(mew), 100), 1);
        // Mint tokenB batch (and check balance)
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = 100;
        ids[1] = 101;
        amounts[0] = 1;
        amounts[1] = 10000;
        tokenB.batchMint(address(mew), ids, amounts, hex"");
        // Check balances
        address[] memory owners = new address[](2);
        owners[0] = address(mew);
        owners[1] = address(mew);
        uint256[] memory balances = tokenB.balanceOfBatch(owners, ids);
        assertEq(balances[0], 1);
        assertEq(balances[1], 10000);
        vm.stopPrank();
    }
}
