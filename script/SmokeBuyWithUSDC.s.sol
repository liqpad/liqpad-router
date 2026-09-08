// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiqpadSwapRouter} from "../src/LiqpadSwapRouter.sol";
import {LiqpadSmokeBase} from "./utils/LiqpadSmokeBase.sol";

contract SmokeBuyWithUSDC is LiqpadSmokeBase {
    using SafeERC20 for IERC20;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (LiqpadSwapRouter router, address account) = _preflight(privateKey);
        uint256 amountIn = vm.envOr("SMOKE_USDC_BUY_IN", uint256(10_000)); // 0.01 USDC
        require(amountIn != 0 && IERC20(USDC).balanceOf(account) >= amountIn, "INSUFFICIENT_USDC");

        vm.startBroadcast(privateKey);
        IERC20(USDC).forceApprove(ROUTER, amountIn);
        uint256 b20Out = router.swapExactUSDCForB20(
            B20,
            amountIn,
            vm.envOr("SMOKE_MIN_VVV_BUY", uint256(1)),
            vm.envOr("SMOKE_MIN_B20_BUY", uint256(1)),
            account,
            block.timestamp + 10 minutes
        );
        IERC20(USDC).forceApprove(ROUTER, 0);
        vm.stopBroadcast();

        console2.log("USDC spent", amountIn);
        console2.log("B20 received", b20Out);
    }
}
