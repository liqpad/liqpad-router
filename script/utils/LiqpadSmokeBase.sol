// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LiqpadSwapRouter} from "../../src/LiqpadSwapRouter.sol";
import {ILiqpadFactory} from "../../src/interfaces/ILiqpadFactory.sol";

abstract contract LiqpadSmokeBase is Script {
    address internal constant ROUTER = 0xf05ce37534a00C6815EE062FF6A10603C49c28A9;
    address internal constant FACTORY = 0x38472Ca56a93CAa68459fD11FDd2EEb130D06b29;
    address internal constant B20 = 0xB200000000000000000000defA12971e32B3BB07;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    function _preflight(uint256 privateKey) internal view returns (LiqpadSwapRouter router, address account) {
        require(block.chainid == 8453, "BASE_MAINNET_ONLY");
        require(privateKey != 0, "PRIVATE_KEY_REQUIRED");
        require(ROUTER.code.length != 0 && B20.code.length != 0, "DEPENDENCY_NO_CODE");
        require(ILiqpadFactory(FACTORY).isLiqpadLaunch(B20), "NOT_LIQPAD_LAUNCH");
        router = LiqpadSwapRouter(payable(ROUTER));
        require(address(router.factory()) == FACTORY, "ROUTER_FACTORY_MISMATCH");
        account = vm.addr(privateKey);
    }

    function _validateSell(address account, uint256 amountIn) internal view {
        require(amountIn != 0 && amountIn <= IERC20(B20).balanceOf(account), "INVALID_SELL_AMOUNT");
    }
}
