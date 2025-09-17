// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IOracle} from "../../../src/interfaces/IOracle.sol";
import {GasTankPaymaster} from "../../../src/paymaster/GasTankPaymaster.sol";
import {UniswapHelper} from "../../../src/paymaster/utils/UniswapHelper.sol";
import {TestERC20} from "../../../src/test/TestERC20.sol";
import {TestUSDC} from "../../../src/test/TestUSDC.sol";
import {TestWETH} from "../../../src/test/TestWETH.sol";
import {TestOracle} from "../../../src/test/TestOracle.sol";
import {TestUniswapV3} from "../../../src/test/TestUniswapV3.sol";
import {IStakeManager} from "ERC4337/interfaces/IStakeManager.sol";
import {PackedUserOperation} from "ERC4337/interfaces/PackedUserOperation.sol";
import {IPaymaster} from "ERC4337/interfaces/IPaymaster.sol";
import "../../ModularTestBase.sol";
import {MockSequencerUptimeFeed} from "../utils/MockSequencerUptimeFeed.sol";
import {MockFailingSequencerFeed} from "../utils/MockFailingSequencerFeed.sol";

contract GasTankPaymasterTestUtils is ModularTestBase {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Contract instances
    GasTankPaymaster internal gasTankUSDC;
    GasTankPaymaster internal gasTankUSDT;
    TestUniswapV3 internal uniswapV3;
    TestOracle internal usdtOracle;
    TestOracle internal usdcOracle;
    TestOracle internal nativeOracle;

    // Test addresses and keys
    User internal verifyingSigner;
    User internal feeReceiver;

    // Test variables
    uint256 internal constant USDT_INITIAL_MINT = 1000000 * 10 ** 18;
    uint256 internal constant USDT_DEPOSIT_AMOUNT = 100 * 10 ** 18;
    uint256 internal constant USDT_WITHDRAW_AMOUNT = 50 * 10 ** 18;
    uint256 internal constant USDC_INITIAL_MINT = 1000000 * 10 ** 6;
    uint256 internal constant USDC_DEPOSIT_AMOUNT = 100 * 10 ** 6;
    uint256 internal constant USDC_WITHDRAW_AMOUNT = 50 * 10 ** 6;
    uint256 internal constant PRICE_DENOMINATOR = 1e26;

    /*//////////////////////////////////////////////////////////////
                        SETUP & CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function _testSetup() internal {
        _testInit();
        // Create test accounts
        verifyingSigner = _createUser("VerifyingSigner");
        feeReceiver = _createUser("FeeReceiver");
        // Create mock uniswap and oracle
        uniswapV3 = new TestUniswapV3(weth);
        // Fund the mock uniswap with tokens for swaps
        usdc.mint(address(uniswapV3), 20000 * 10 ** 6);
        usdt.mint(address(uniswapV3), 20000 * 10 ** 18);
        vm.deal(address(uniswapV3), 10 ether);
        vm.prank(address(uniswapV3));
        weth.deposit{value: 10 ether}();
        // Create oracles with realistic USD prices
        // USDT: $1.00 (1e8 with 8 decimals)
        usdtOracle = new TestOracle(1e8, 8);     // $1.00
        // USDC: $1.00 (1e8 with 8 decimals)  
        usdcOracle = new TestOracle(1e8, 8);     // $1.00
        // ETH: $2000.00 (2000e8 with 8 decimals)
        nativeOracle = new TestOracle(2000e8, 8); // $2000.00
        // Mint tokens to users
        deal({token: address(usdc), to: alice.pub, give: USDC_INITIAL_MINT});
        deal({token: address(usdc), to: bob.pub, give: USDC_INITIAL_MINT});
        deal({token: address(usdc), to: feeReceiver.pub, give: USDC_INITIAL_MINT});
        deal({token: address(usdc), to: address(scw), give: USDC_INITIAL_MINT});
        deal({token: address(usdt), to: alice.pub, give: USDT_INITIAL_MINT});
        deal({token: address(usdt), to: bob.pub, give: USDT_INITIAL_MINT});
        deal({token: address(usdt), to: feeReceiver.pub, give: USDT_INITIAL_MINT});
        deal({token: address(usdt), to: address(scw), give: USDT_INITIAL_MINT});
        vm.deal(deployer.pub, 10000 ether);
        vm.deal(alice.pub, 10 ether);
        vm.deal(bob.pub, 10 ether);
        vm.deal(feeReceiver.pub, 10000 ether);
        vm.startPrank(deployer.pub);
        // Create paymaster configurations
        GasTankPaymaster.GasTankPaymasterConfig memory paymasterConfigUSDC = GasTankPaymaster.GasTankPaymasterConfig({
            tokenUsdFeed: IOracle(address(usdcOracle)),
            nativeUsdFeed: IOracle(address(nativeOracle)),
            sequencerUptimeFeed: AggregatorV2V3Interface(address(0)), // No sequencer feed by default
            minEPBalance: 1 ether,
            cachedPriceTimestamp: 0,
            tokenMaxAge: 24 hours,
            nativeMaxAge: 5 minutes,
            postOpCost: 35000,
            cachedTokenPrice: 0,
            markup: PRICE_DENOMINATOR * 12 / 10,
            minFeeReceiverTokenBalance: 10 * 10 ** 6, // 10 USDC minimum
            stalePriceMarkup: 120 // 120 = 20% markup
        });
        GasTankPaymaster.GasTankPaymasterConfig memory paymasterConfigUSDT = GasTankPaymaster.GasTankPaymasterConfig({
            tokenUsdFeed: IOracle(address(usdtOracle)),
            nativeUsdFeed: IOracle(address(nativeOracle)),
            sequencerUptimeFeed: AggregatorV2V3Interface(address(0)), // No sequencer feed by default
            minEPBalance: 1 ether,
            cachedPriceTimestamp: 0,
            tokenMaxAge: 24 hours,
            nativeMaxAge: 5 minutes,
            postOpCost: 35000,
            cachedTokenPrice: 0,
            markup: PRICE_DENOMINATOR * 12 / 10,
            minFeeReceiverTokenBalance: 10 * 10 ** 18, // 10 USDT minimum
            stalePriceMarkup: 120 // 120 = 20% markup
        });
        UniswapHelper.UniswapHelperConfig memory uniswapConfig =
            UniswapHelper.UniswapHelperConfig({minSwapAmount: 0.0001 ether, uniswapPoolFee: 3000, slippage: 50});
        // Deploy gas tank contracts
        gasTankUSDC = new GasTankPaymaster(deployer.pub, verifyingSigner.pub, feeReceiver.pub, entrypoint);
        gasTankUSDC.setup(
            IERC20Metadata(address(usdc)),
            IERC20Metadata(address(weth)),
            ISwapRouter(address(uniswapV3)),
            paymasterConfigUSDC,
            uniswapConfig
        );
        gasTankUSDT = new GasTankPaymaster(deployer.pub, verifyingSigner.pub, feeReceiver.pub, entrypoint);
        gasTankUSDT.setup(
            IERC20Metadata(address(usdt)),
            IERC20Metadata(address(weth)),
            ISwapRouter(address(uniswapV3)),
            paymasterConfigUSDT,
            uniswapConfig
        );
        // Add stake to the paymasters
        entrypoint.depositTo{value: 1000 ether}(address(gasTankUSDC));
        gasTankUSDC.addStake{value: 1000 ether}(86400);
        entrypoint.depositTo{value: 1000 ether}(address(gasTankUSDT));
        gasTankUSDT.addStake{value: 1000 ether}(86400);
        vm.stopPrank();
        _installModule(eoa.pub, scw, MODULE_TYPE_VALIDATOR, address(moecdsav), hex"");
    }

    /*//////////////////////////////////////////////////////////////
                        GAS TANK OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function _depositToGasTank(GasTankPaymaster _gasTank, address _token, address _user, uint256 _amount) internal {
        vm.startPrank(_user);
        IERC20(_token).approve(address(_gasTank), _amount);
        _gasTank.gasTankDeposit(_amount);
        vm.stopPrank();
    }

    function _depositToGasTankForWallet(
        GasTankPaymaster _gasTank,
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        vm.startPrank(_from);
        IERC20(_token).approve(address(_gasTank), _amount);
        _gasTank.gasTankDeposit(_to, _amount);
        vm.stopPrank();
    }

    function _withdrawFromGasTank(GasTankPaymaster _gasTank, address _token, address _user, uint256 _amount) internal {
        vm.prank(_user);
        _gasTank.gasTankWithdraw(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                      USER OPERATION CREATION
    //////////////////////////////////////////////////////////////*/

    function _createUserOperation(
        address _sender,
        bytes memory _callData,
        uint256 _maxFeePerGas,
        uint256 _maxPriorityFeePerGas,
        uint256 _signerKey
    ) internal view returns (PackedUserOperation memory) {
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: _sender,
            nonce: entrypoint.getNonce(_sender, 0),
            initCode: bytes(""),
            callData: _callData,
            accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
            preVerificationGas: 2000000,
            gasFees: bytes32(abi.encodePacked(uint128(_maxFeePerGas), uint128(_maxPriorityFeePerGas))),
            paymasterAndData: bytes(""),
            signature: bytes("")
        });
        return userOp;
    }

    function _createUserOperationWithPaymaster(
        address _sender,
        bytes memory _callData,
        uint256 _maxFeePerGas,
        uint256 _maxPriorityFeePerGas,
        uint256 _signerKey,
        address _paymaster
    ) internal view returns (PackedUserOperation memory) {
        PackedUserOperation memory userOp =
            _createUserOperation(_sender, _callData, _maxFeePerGas, _maxPriorityFeePerGas, _signerKey);
        userOp.nonce = _getNonce(_sender, address(moecdsav));
        // Add paymaster data
        userOp.paymasterAndData = abi.encodePacked(_paymaster);
        // Sign the user operation
        bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerKey, ECDSA.toEthSignedMessageHash(userOpHash));
        userOp.signature = abi.encodePacked(r, s, v);
        return userOp;
    }

    function _createUserOperationWithGasTankPaymaster(
        GasTankPaymaster _gasTank,
        address _sender,
        uint256 _senderKey,
        bytes memory _callData,
        uint256 _maxFeePerGas,
        uint256 _maxPriorityFeePerGas,
        uint256 _signerKey,
        uint48 _validUntil,
        uint48 _validAfter
    ) internal view returns (PackedUserOperation memory userOp) {
        // Create base user operation
        userOp = PackedUserOperation({
            sender: _sender,
            nonce: _getNonce(_sender, address(moecdsav)),
            initCode: bytes(""),
            callData: _callData,
            accountGasLimits: bytes32(abi.encodePacked(uint128(2000000), uint128(2000000))),
            preVerificationGas: 2000000,
            gasFees: bytes32(abi.encodePacked(uint128(_maxFeePerGas), uint128(_maxPriorityFeePerGas))),
            paymasterAndData: bytes(""),
            signature: bytes("")
        });
        // Set up the paymaster data structure for hash calculation
        userOp.paymasterAndData = abi.encodePacked(
            address(_gasTank),
            uint128(300000), // verificationGasLimit
            uint128(300000) // postOpGasLimit
        );
        // Create paymaster signature
        {
            bytes32 paymasterHash = _gasTank.getHash(userOp, _validUntil, _validAfter);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerKey, ECDSA.toEthSignedMessageHash(paymasterHash));
            bytes memory paymasterSignature = abi.encodePacked(r, s, v);
            // Create the complete paymaster data
            bytes memory paymasterData = abi.encodePacked(_validUntil, _validAfter, paymasterSignature);
            userOp.paymasterAndData = abi.encodePacked(
                address(_gasTank),
                uint128(300000), // verificationGasLimit
                uint128(300000), // postOpGasLimit
                paymasterData
            );
        }
        // Sign the final UserOp with complete paymasterAndData
        {
            bytes32 userOpHash = entrypoint.getUserOpHash(userOp);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_senderKey, ECDSA.toEthSignedMessageHash(userOpHash));
            userOp.signature = abi.encodePacked(r, s, v);
        }
        return userOp;
    }

    /*//////////////////////////////////////////////////////////////
                    PAYMASTER CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function _configurePaymaster(
        GasTankPaymaster _gasTank,
        uint256 _markup,
        uint128 _minEPBalance,
        uint48 _postOpCost,
        uint48 _tokenMaxAge,
        uint48 _nativeMaxAge
    ) internal {
        // Get current config to preserve oracle settings
        GasTankPaymaster.GasTankPaymasterConfig memory currentConfig = _gasTank.getPaymasterConfig();
        currentConfig.markup = _markup;
        currentConfig.minEPBalance = _minEPBalance;
        currentConfig.postOpCost = _postOpCost;
        currentConfig.tokenMaxAge = _tokenMaxAge;
        currentConfig.nativeMaxAge = _nativeMaxAge;
        vm.prank(deployer.pub);
        _gasTank.configurePaymaster(currentConfig);
    }

    function _setVerifyingSigner(GasTankPaymaster _gasTank, address payable _newVerifyingSigner) internal {
        _gasTank.setVerifyingSigner(_newVerifyingSigner);
    }

    function _setFeeReceiver(GasTankPaymaster _gasTank, address payable _newFeeReceiver) internal {
        _gasTank.setFeeReceiver(_newFeeReceiver);
    }

    function _setSwapRouter(GasTankPaymaster _gasTank, address _newSwapRouter) internal {
        _gasTank.setSwapRouter(ISwapRouter(_newSwapRouter));
    }

    function _transferOwnership(GasTankPaymaster _gasTank, address _newOwner) internal {
        _gasTank.transferOwnership(_newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                      ENTRYPOINT INTERACTIONS
    //////////////////////////////////////////////////////////////*/

    function _addStake(GasTankPaymaster _gasTank, uint256 _amount, uint32 _unstakeDelaySec) internal {
        vm.deal(address(scw), _amount);
        _gasTank.addStake{value: _amount}(_unstakeDelaySec);
    }

    function _depositToEntryPoint(GasTankPaymaster _gasTank, uint256 _amount) internal {
        vm.deal(address(scw), _amount);
        _gasTank.deposit{value: _amount}();
    }

    function _withdrawFromEntryPoint(GasTankPaymaster _gasTank, address payable _withdrawAddress, uint256 _amount)
        internal
    {
        _gasTank.withdrawTo(_withdrawAddress, _amount);
    }

    function _getEntryPointDeposit(GasTankPaymaster _gasTank) internal view returns (uint256) {
        IStakeManager.DepositInfo memory depositInfo = entrypoint.getDepositInfo(address(_gasTank));
        return depositInfo.deposit;
    }

    function _getEntryPointStake(GasTankPaymaster _gasTank) internal view returns (uint256) {
        IStakeManager.DepositInfo memory depositInfo = entrypoint.getDepositInfo(address(_gasTank));
        return depositInfo.stake;
    }

    /*//////////////////////////////////////////////////////////////
                          UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getBasicCalldata() internal returns (bytes memory) {
        bytes memory setValueOnTarget = abi.encodeCall(MockTarget.setValue, 1337);
        return abi.encodeCall(
            IERC7579Account.execute,
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(mockTar), uint256(0), setValueOnTarget))
        );
    }

    function _createBasicUserOp() internal returns (PackedUserOperation memory) {
        return _createUserOperation(
            address(scw), // sender
            _getBasicCalldata(), // callData
            1 gwei, // maxFeePerGas
            1 gwei, // maxPriorityFeePerGas
            eoa.priv // signerKey
        );
    }

    /*//////////////////////////////////////////////////////////////
                          SEQUENCER HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setSequencerUptimeFeed(GasTankPaymaster _gasTank, AggregatorV2V3Interface _sequencerFeed) internal {
        vm.prank(deployer.pub);
        _gasTank.setSequencerUptimeFeed(_sequencerFeed);
    }

    function _createMockSequencerFeed() internal returns (MockSequencerUptimeFeed) {
        return new MockSequencerUptimeFeed();
    }

    function _createFailingSequencerFeed() internal returns (MockFailingSequencerFeed) {
        return new MockFailingSequencerFeed();
    }
}
