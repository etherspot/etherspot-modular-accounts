// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IEntryPoint} from "ERC4337/interfaces/IEntryPoint.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {GasTankPaymaster} from "../src/paymaster/GasTankPaymaster.sol";
import {UniswapHelper} from "../src/paymaster/utils/UniswapHelper.sol";
// Check utils/ScriptConstants.sol for stored config addresses
import {
    OPTIMISM_USDC,
    OPTIMISM_WETH,
    OPTIMISM_USDC_USD_ORACLE,
    OPTIMISM_WETH_USD_ORACLE,
    UNISWAP_ROUTER
} from "./utils/ScriptConstants.sol";

/**
 * @author Etherspot.
 * @title  GasTankPaymasterScript.
 * @dev Deployment script for GasTankPaymaster.
 */
contract GasTankPaymasterScript is Script {
    bytes32 public immutable TEST_SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:testSalt"));
    bytes32 public immutable SALT = bytes32(abi.encodePacked("ModularEtherspotWallet:Create2:salt"));
    address public constant ENTRY_POINT_07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    // address public constant EXPECTED_GAS_TANK_PAYMASTER = address(0);

    /*//////////////////////////////////////////////////////////////
                         CHANGE THESE VALUES
    //////////////////////////////////////////////////////////////*/

    // CHANGE THESE VALUES
    address public constant TOKEN_ADDRESS = OPTIMISM_USDC;
    address public constant WRAPPED_NATIVE_TOKEN_ADDRESS = OPTIMISM_WETH;
    address public constant TOKEN_ORACLE = OPTIMISM_USDC_USD_ORACLE;
    address public constant NATIVE_TOKEN_ORACLE = OPTIMISM_WETH_USD_ORACLE;

    // Address settings
    address public constant DEPLOYER = 0x09FD4F6088f2025427AB1e89257A44747081Ed59;
    address payable public constant VERIFYING_SIGNER = payable(0x09FD4F6088f2025427AB1e89257A44747081Ed59);
    address payable public constant FEE_RECEIVER = payable(0x09FD4F6088f2025427AB1e89257A44747081Ed59);
    // PaymasterConfig settings
    uint256 public constant PRICE_MARKUP = 1e26 * 12 / 10; // 1.2x markup
    uint128 public constant MINIMUM_ENTRYPOINT_BALANCE = 0.0005 ether;
    uint48 public constant POST_OP_COST = 35000;
    uint48 public constant TOKEN_MAX_AGE = 24 hours + 1 minutes;
    uint48 public constant NATIVE_MAX_AGE = 11 minutes;
    uint256 public constant MINIMUM_FEE_RECEIVER_TOKEN_BALANCE_FOR_TOPUP = 10;
    // UniswapHelperConfig settings
    uint256 public constant MINIMUM_SWAP_AMOUNT = 0.0001 ether;
    uint24 public constant UNISWAP_POOL_FEE = 3000; // 0.3%
    uint8 public constant SLIPPAGE = 50; // 0.5%

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console2.log("Starting deployment sequence...");

        /*//////////////////////////////////////////////////////////////
               Configure GasTankPaymaster Constructor Parameters
        //////////////////////////////////////////////////////////////*/

        console2.log("Configuring GasTankPaymaster settings...");

        IEntryPoint ENTRY_POINT = IEntryPoint(ENTRY_POINT_07);
        ISwapRouter SWAP_ROUTER = ISwapRouter(UNISWAP_ROUTER);
        IERC20Metadata TOKEN = IERC20Metadata(TOKEN_ADDRESS);
        IERC20 WRAPPED_NATIVE_TOKEN = IERC20(WRAPPED_NATIVE_TOKEN_ADDRESS);

        // Create paymaster config
        GasTankPaymaster.GasTankPaymasterConfig memory paymasterConfig = GasTankPaymaster.GasTankPaymasterConfig({
            tokenUsdFeed: IOracle(TOKEN_ORACLE),
            nativeUsdFeed: IOracle(NATIVE_TOKEN_ORACLE),
            minEPBalance: MINIMUM_ENTRYPOINT_BALANCE,
            cachedPriceTimestamp: 0,
            tokenMaxAge: TOKEN_MAX_AGE,
            nativeMaxAge: NATIVE_MAX_AGE,
            postOpCost: POST_OP_COST,
            cachedTokenPrice: 0,
            markup: PRICE_MARKUP,
            minFeeReceiverTokenBalance: MINIMUM_FEE_RECEIVER_TOKEN_BALANCE_FOR_TOPUP
        });

        // Create uniswap config
        UniswapHelper.UniswapHelperConfig memory uniswapConfig = UniswapHelper.UniswapHelperConfig({
            minSwapAmount: MINIMUM_SWAP_AMOUNT,
            uniswapPoolFee: UNISWAP_POOL_FEE,
            slippage: SLIPPAGE
        });

        /*//////////////////////////////////////////////////////////////
                            Deploy GasTankPaymaster
        //////////////////////////////////////////////////////////////*/
        console2.log("Deploying GasTankPaymaster...");
        // if (EXPECTED_GAS_TANK_PAYMASTER.code.length == 0) {
        GasTankPaymaster gasTankPaymaster = new GasTankPaymaster(
            DEPLOYER,
            VERIFYING_SIGNER,
            FEE_RECEIVER,
            ENTRY_POINT,
            SWAP_ROUTER,
            TOKEN,
            WRAPPED_NATIVE_TOKEN,
            paymasterConfig,
            uniswapConfig
        );
        // if (address(gasTankPaymaster) != EXPECTED_GAS_TANK_PAYMASTER) {
        //     revert("Unexpected GasTankPaymaster address!!!");
        // } else {
        console2.log("GasTankPaymaster deployed at address", address(gasTankPaymaster));
        //     }
        // } else {
        //     console2.log("Already deployed at address", EXPECTED_GAS_TANK_PAYMASTER);
        // }
        // bytes memory valCode = address(gasTankPaymaster).code;
        // console2.logBytes(valCode);

        console2.log("Finished deployment sequence!");

        /*//////////////////////////////////////////////////////////////
                        Stake Paymaster With EntryPoint
        //////////////////////////////////////////////////////////////*/

        console2.log("Staking paymaster with entrypoint...");
        gasTankPaymaster.addStake{value: 0.01 ether}(1);
        console2.log("Stake amount:", uint256(0.01 ether));
        console2.log("Stake delay:", uint256(1));
        console2.log("Stake balance:", gasTankPaymaster.getDeposit());
        console2.log("Staked paymaster with entrypoint!");

        /*//////////////////////////////////////////////////////////////
                        Update Cached Price On Paymaster
        //////////////////////////////////////////////////////////////*/

        console2.log("Updating cached price on paymaster...");
        gasTankPaymaster.updateCachedPrice(true);
        (, uint256 cachedPrice,,,,) = gasTankPaymaster.getPaymasterStatus();
        if (cachedPrice == 0) {
            revert("Cached price not updated!");
        } else {
            console2.log("Cached price updated! Price:", cachedPrice);
        }
        vm.stopBroadcast();
    }
}
