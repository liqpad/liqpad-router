// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console2} from "forge-std/Script.sol";
import {LiqpadSwapRouter} from "../src/LiqpadSwapRouter.sol";
import {LiqpadSmokeBase} from "./utils/LiqpadSmokeBase.sol";

contract SmokeBuyWithETH is LiqpadSmokeBase {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        (LiqpadSwapRouter router, address account) = _preflight(privateKey);
        uint256 amountIn = vm.envOr("SMOKE_ETH_BUY_IN", uint256(1_000_000_000_000));
        require(amountIn != 0 && account.balance >= amountIn, "INSUFFICIENT_ETH");

        vm.startBroadcast(privateKey);
        uint256 b20Out = router.swapExactETHForB20{value: amountIn}(
            B20,
            vm.envOr("SMOKE_MIN_VVV_BUY", uint256(1)),
            vm.envOr("SMOKE_MIN_B20_BUY", uint256(1)),
            account,
            block.timestamp + 10 minutes
        );
        vm.stopBroadcast();

        console2.log("ETH spent", amountIn);
        console2.log("B20 received", b20Out);
    }
}
