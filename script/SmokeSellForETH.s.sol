// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LiqpadSwapRouter} from "../src/LiqpadSwapRouter.sol";
import {LiqpadSmokeBase} from "./utils/LiqpadSmokeBase.sol";

contract SmokeSellForETH is LiqpadSmokeBase {
    using SafeERC20 for IERC20;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (LiqpadSwapRouter router, address account) = _preflight(privateKey);
        uint256 amountIn = vm.envUint("SMOKE_SELL_B20_IN");
        _validateSell(account, amountIn);

        vm.startBroadcast(privateKey);
        IERC20(B20).forceApprove(ROUTER, amountIn);
        uint256 ethOut = router.swapExactB20ForETH(
            B20,
            amountIn,
            vm.envOr("SMOKE_MIN_VVV_SELL", uint256(1)),
            vm.envOr("SMOKE_MIN_ETH_SELL", uint256(1)),
            account,
            block.timestamp + 10 minutes
        );
        IERC20(B20).forceApprove(ROUTER, 0);
        vm.stopBroadcast();

        console2.log("B20 sold", amountIn);
        console2.log("ETH received", ethOut);
    }
}
