// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/* solhint-disable not-rely-on-time */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IPeripheryPayments} from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryPayments.sol";

abstract contract UniswapHelper {
    event UniswapReverted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin);

    uint256 private constant PRICE_DENOMINATOR = 1e26;

    struct UniswapHelperConfig {
        /// @notice Minimum native asset amount to receive from a single swap
        uint256 minSwapAmount;
        uint24 uniswapPoolFee;
        uint8 slippage;
    }

    /// @notice The Uniswap V3 SwapRouter contract
    ISwapRouter public uniswap;
    /// @notice The ERC20 token used for transaction fee payments
    IERC20 internal token;
    /// @notice The ERC-20 token that wraps the native asset for current chain
    IERC20 internal wrappedNative;
    UniswapHelperConfig private uniswapHelperConfig;
    bool private initialized;

    error AlreadyInitialized();

    function _initUniswapHelper(
        IERC20 _token,
        IERC20 _wrappedNative,
        ISwapRouter _uniswap,
        UniswapHelperConfig memory _uniswapHelperConfig
    ) internal {
        if (initialized) revert AlreadyInitialized();

        // Approve router for token
        _token.approve(address(_uniswap), type(uint256).max);

        token = _token;
        wrappedNative = _wrappedNative;
        uniswap = _uniswap;
        _setUniswapHelperConfiguration(_uniswapHelperConfig);

        initialized = true;
    }

    function _setUniswapHelperConfiguration(UniswapHelperConfig memory _uniswapHelperConfig) internal {
        uniswapHelperConfig = _uniswapHelperConfig;
    }

    function _maybeSwapTokenToWeth(IERC20 tokenIn, uint256 amountToSwap, uint256 quote) internal returns (uint256) {
        if (amountToSwap == 0) {
            return 0;
        }
        // uint256 expectedOutput = tokenToWei(amountToSwap, quote);
        uint256 amountOutMin = addSlippage(tokenToWei(amountToSwap, quote), uniswapHelperConfig.slippage);
        // Compare expected output (in wei) vs minSwapAmount (also in wei)
        if (amountOutMin < uniswapHelperConfig.minSwapAmount) {
            return 0;
        }
        return swapToToken(
            address(tokenIn), address(wrappedNative), amountToSwap, amountOutMin, uniswapHelperConfig.uniswapPoolFee
        );
    }

    function addSlippage(uint256 amount, uint8 slippage) private pure returns (uint256) {
        return amount * (10000 - slippage) / 10000;
    }

    function tokenToWei(uint256 amount, uint256 price) public view returns (uint256) {
        if (price == 0) return 0;
        uint8 tokenDecimals = IERC20Metadata(address(token)).decimals();
        // Price is in PRICE_DENOMINATOR units and represents ETH per token
        // For USDC: if 1 USDC = 0.0005 ETH, then price = 0.0005 * 1e26 = 5e22
        // amount * price gives us ETH in wei, but we need to adjust for token decimals
        if (tokenDecimals < 18) {
            // For tokens with fewer decimals (like USDC with 6 decimals)
            // We need to scale UP the token amount to 18 decimals before applying price
            uint256 decimalAdjustment = 10 ** (18 - tokenDecimals);
            return (amount * decimalAdjustment * price) / PRICE_DENOMINATOR;
        } else if (tokenDecimals > 18) {
            // For tokens with more decimals than ETH
            uint256 decimalAdjustment = 10 ** (tokenDecimals - 18);
            return (amount * price) / (PRICE_DENOMINATOR * decimalAdjustment);
        } else {
            // For tokens with 18 decimals
            return (amount * price) / PRICE_DENOMINATOR;
        }
    }

    function weiToToken(uint256 amount, uint256 price) public view returns (uint256) {
        if (price == 0) return 0;
        uint8 tokenDecimals = IERC20Metadata(address(token)).decimals();
        // For tokens with fewer decimals than ETH (e.g., USDC with 6 decimals)
        if (tokenDecimals < 18) {
            uint256 decimalAdjustment = 10 ** (18 - tokenDecimals);
            return (amount * PRICE_DENOMINATOR) / price / decimalAdjustment;
        }
        // For tokens with more decimals than ETH (rare case)
        else if (tokenDecimals > 18) {
            uint256 decimalAdjustment = 10 ** (tokenDecimals - 18);
            return (amount * PRICE_DENOMINATOR) / price * decimalAdjustment;
        }
        // For tokens with the same number of decimals as ETH
        else {
            return (amount * PRICE_DENOMINATOR) / price;
        }
    }

    function unwrapWeth(uint256 amount) internal {
        IPeripheryPayments(address(uniswap)).unwrapWETH9(amount, address(this));
    }

    // swap ERC-20 tokens at market price
    function swapToToken(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, uint24 fee)
        internal
        returns (uint256 amountOut)
    {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
            tokenIn, //tokenIn
            tokenOut, //tokenOut
            fee,
            address(uniswap),
            block.timestamp, //deadline
            amountIn,
            amountOutMin,
            0
        );
        try uniswap.exactInputSingle(params) returns (uint256 _amountOut) {
            amountOut = _amountOut;
        } catch {
            emit UniswapReverted(tokenIn, tokenOut, amountIn, amountOutMin);
            amountOut = 0;
        }
    }
}
