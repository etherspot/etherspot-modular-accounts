// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
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
import "../../TestAdvancedUtils.t.sol";

contract GasTankPaymasterTestUtils is TestAdvancedUtils {
    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                              VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Contract instances
    ModularEtherspotWallet internal mew;
    GasTankPaymaster internal gasTankUSDC;
    GasTankPaymaster internal gasTankUSDT;
    TestERC20 internal usdt;
    TestUSDC internal usdc;
    TestWETH internal weth;
    TestUniswapV3 internal uniswapV3;
    TestOracle internal usdtOracle;
    TestOracle internal usdcOracle;
    TestOracle internal nativeOracle;

    // Test addresses and keys
    address internal user1;
    uint256 internal user1Key;
    address internal user2;
    uint256 internal user2Key;
    address payable internal verifyingSigner;
    uint256 internal verifyingSignerKey;
    address payable internal immutable beneficiary;

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

    constructor() {
        beneficiary = payable(address(uint160(uint256(keccak256(abi.encodePacked("beneficiary"))))));
    }

    function _testSetup() internal {
        // Create test accounts
        (user1, user1Key) = makeAddrAndKey("user1");
        (user2, user2Key) = makeAddrAndKey("user2");
        (verifyingSigner, verifyingSignerKey) = _makePayableAddrAndKey("verifyingSigner");
        mew = setupMEW();
        // Deploy test tokens
        usdt = new TestERC20();
        usdc = new TestUSDC();
        weth = new TestWETH();
        // Create mock uniswap and oracle
        uniswapV3 = new TestUniswapV3(weth);
        // Fund the mock uniswap with tokens for swaps
        usdc.mint(address(uniswapV3), 20000 * 10 ** 6);
        usdt.mint(address(uniswapV3), 20000 * 10 ** 18);
        vm.deal(address(uniswapV3), 10 ether);
        vm.prank(address(uniswapV3));
        weth.deposit{value: 10 ether}();
        // Create oracles
        usdtOracle = new TestOracle(100000000, 8);
        usdcOracle = new TestOracle(100000000, 8);
        nativeOracle = new TestOracle(200000000000, 8);
        // Mint tokens to users
        usdc.mint(user1, USDC_INITIAL_MINT);
        usdc.mint(user2, USDC_INITIAL_MINT);
        usdc.mint(verifyingSigner, USDC_INITIAL_MINT);
        usdt.mint(user1, USDT_INITIAL_MINT);
        usdt.mint(user2, USDT_INITIAL_MINT);
        usdt.mint(verifyingSigner, USDT_INITIAL_MINT);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(verifyingSigner, 10000 ether);
        // Create paymaster configurations
        GasTankPaymaster.GasTankPaymasterConfig memory paymasterConfigUSDC = GasTankPaymaster.GasTankPaymasterConfig({
            tokenUsdFeed: IOracle(address(usdcOracle)),
            nativeUsdFeed: IOracle(address(nativeOracle)),
            minEPBalance: 1 ether,
            cachedPriceTimestamp: 0,
            priceMaxAge: 1 hours,
            postOpCost: 35000,
            cachedTokenPrice: 0,
            markup: PRICE_DENOMINATOR * 12 / 10,
            minVSTokenBalance: 10 * 10 ** 6 // 10 USDC minimum
        });
        GasTankPaymaster.GasTankPaymasterConfig memory paymasterConfigUSDT = GasTankPaymaster.GasTankPaymasterConfig({
            tokenUsdFeed: IOracle(address(usdtOracle)),
            nativeUsdFeed: IOracle(address(nativeOracle)),
            minEPBalance: 1 ether,
            cachedPriceTimestamp: 0,
            priceMaxAge: 1 hours,
            postOpCost: 35000,
            cachedTokenPrice: 0,
            markup: PRICE_DENOMINATOR * 12 / 10,
            minVSTokenBalance: 10 * 10 ** 18 // 10 USDT minimum
        });
        UniswapHelper.UniswapHelperConfig memory uniswapConfig =
            UniswapHelper.UniswapHelperConfig({minSwapAmount: 0.0001 ether, uniswapPoolFee: 3000, slippage: 50});
        // Deploy gas tank contracts
        vm.startPrank(verifyingSigner);
        gasTankUSDC = new GasTankPaymaster(
            verifyingSigner,
            entrypoint,
            ISwapRouter(address(uniswapV3)),
            IERC20Metadata(address(usdc)),
            IERC20Metadata(address(weth)),
            paymasterConfigUSDC,
            uniswapConfig
        );
        gasTankUSDT = new GasTankPaymaster(
            verifyingSigner,
            entrypoint,
            ISwapRouter(address(uniswapV3)),
            IERC20Metadata(address(usdt)),
            IERC20Metadata(address(weth)),
            paymasterConfigUSDT,
            uniswapConfig
        );
        // Add stake to the paymasters
        entrypoint.depositTo{value: 1000 ether}(address(gasTankUSDC));
        gasTankUSDC.addStake{value: 1000 ether}(86400);
        entrypoint.depositTo{value: 1000 ether}(address(gasTankUSDT));
        gasTankUSDT.addStake{value: 1000 ether}(86400);
        vm.stopPrank();
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
        userOp.nonce = getNonce(_sender, address(ecdsaValidator));
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
            nonce: getNonce(_sender, address(ecdsaValidator)),
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

    function _executeUserOp(PackedUserOperation memory _op) internal {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = _op;
        entrypoint.handleOps(ops, beneficiary);
    }

    /*//////////////////////////////////////////////////////////////
                    PAYMASTER CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function _configurePaymaster(
        GasTankPaymaster _gasTank,
        uint256 _markup,
        uint128 _minEPBalance,
        uint48 _postOpCost,
        uint48 _priceMaxAge
    ) internal {
        // Get current config to preserve oracle settings
        GasTankPaymaster.GasTankPaymasterConfig memory currentConfig = _gasTank.getPaymasterConfig();
        currentConfig.markup = _markup;
        currentConfig.minEPBalance = _minEPBalance;
        currentConfig.postOpCost = _postOpCost;
        currentConfig.priceMaxAge = _priceMaxAge;
        vm.prank(verifyingSigner);
        _gasTank.configurePaymaster(currentConfig);
    }

    function _setSwapRouter(GasTankPaymaster _gasTank, address _newSwapRouter) internal {
        _gasTank.setSwapRouter(ISwapRouter(_newSwapRouter));
    }

    function _setSupportedToken(GasTankPaymaster _gasTank, address _newToken) internal {
        _gasTank.setSupportedToken(IERC20(_newToken));
    }

    function _setWrappedNativeToken(GasTankPaymaster _gasTank, address _newWrappedNative) internal {
        _gasTank.setWrappedNativeToken(IERC20(_newWrappedNative));
    }

    function _transferOwnership(GasTankPaymaster _gasTank, address _newOwner) internal {
        _gasTank.transferOwnership(_newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                      ENTRYPOINT INTERACTIONS
    //////////////////////////////////////////////////////////////*/

    function _addStake(GasTankPaymaster _gasTank, uint256 _amount, uint32 _unstakeDelaySec) internal {
        vm.deal(owner1, _amount);
        _gasTank.addStake{value: _amount}(_unstakeDelaySec);
    }

    function _depositToEntryPoint(GasTankPaymaster _gasTank, uint256 _amount) internal {
        vm.deal(owner1, _amount);
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
            (ModeLib.encodeSimpleSingle(), ExecutionLib.encodeSingle(address(target), uint256(0), setValueOnTarget))
        );
    }

    function _createBasicUserOp() internal returns (PackedUserOperation memory) {
        return _createUserOperation(
            address(mew), // sender
            _getBasicCalldata(), // callData
            1 gwei, // maxFeePerGas
            1 gwei, // maxPriorityFeePerGas
            owner1Key // signerKey
        );
    }
}
