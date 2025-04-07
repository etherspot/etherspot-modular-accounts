// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestERC20} from "./TestERC20.sol";
import {TestWETH} from "./TestWETH.sol";

contract TestUniswapV2 {
    TestWETH public weth;

    constructor(TestWETH _weth) {
        weth = _weth;
    }

    event MockUniswapExchangeEvent(uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        uint256 amountOut = amountOutMin + 1 ether;
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountOut;
        emit MockUniswapExchangeEvent(amountIn, amountOut, path[0], path[path.length - 1]);
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        // Mints the output token to the recipeint
        IERC20(path[path.length - 1]).transfer(to, amountOut);
        return amounts;
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts)
    {
        uint256 amountIn = msg.value;
        uint256 amountOut = amountOutMin + 1 ether;
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountOut;
        emit MockUniswapExchangeEvent(amountIn, amountOut, path[0], path[path.length - 1]);
        weth.deposit{value: amountIn}();
        TestERC20(path[path.length - 1]).mint(to, amountOut);

        return amounts;
    }

    function unwrapWETH9(uint256 amountMinimum, address recipient) public payable {
        uint256 balanceWETH9 = weth.balanceOf(address(this));
        require(balanceWETH9 >= amountMinimum, "Insufficient WETH9");
        if (balanceWETH9 > 0) {
            weth.withdraw(balanceWETH9);
            payable(recipient).transfer(balanceWETH9);
        }
    }

    receive() external payable {}
}
