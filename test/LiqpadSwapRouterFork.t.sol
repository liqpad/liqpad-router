// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LiqpadSwapRouter} from "../src/LiqpadSwapRouter.sol";
import {IAerodromeRouter} from "../src/interfaces/IAerodromeRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAeroFactory {
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
}

interface IAeroQuoter {
    function getAmountsOut(uint256 amountIn, IAerodromeRouter.Route[] calldata routes)
        external
        view
        returns (uint256[] memory amounts);
}

interface ILiveFactory {
    function isLiqpadLaunch(address) external view returns (bool);
    function VVV() external view returns (address);
    function poolManager() external view returns (address);
    function launchHook() external view returns (address);
}

interface ILiveHook {
    function launchPools(PoolId)
        external
        view
        returns (address token, address creator, bool registered, bool initialized);
}

contract LiqpadSwapRouterForkTest is Test {
    using PoolIdLibrary for PoolKey;
    address constant FACTORY = 0x38472Ca56a93CAa68459fD11FDd2EEb130D06b29;
    address constant MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant HOOK = 0xC5a862dD09Df3585e0A5d3BC32AC4Fe7efE0A0cc;
    address constant VVV = 0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant AERO_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERO_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH_VVV_POOL = 0x01784ef301D79e4B2DF3a21ad9a536d4cF09A5Ce;
    address constant USDC_WETH_POOL = 0xcDAC0d6c6C59727a65F871236188350531885C43;
    address constant LAUNCH = 0xB200000000000000000000defA12971e32B3BB07;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
    }

    function testReferenceLaunchAndRegisteredPool() public {
        LiqpadSwapRouter router =
            new LiqpadSwapRouter(FACTORY, MANAGER, HOOK, VVV, PERMIT2, AERO_ROUTER, AERO_FACTORY, WETH, USDC);
        assertTrue(router.factory().isLiqpadLaunch(LAUNCH));
        assertEq(ILiveFactory(FACTORY).VVV(), VVV);
        assertEq(ILiveFactory(FACTORY).poolManager(), MANAGER);
        assertEq(ILiveFactory(FACTORY).launchHook(), HOOK);
        PoolKey memory key = router.poolKey(LAUNCH);
        (address token, address creator, bool registered, bool initialized) = ILiveHook(HOOK).launchPools(key.toId());
        assertEq(token, LAUNCH);
        assertTrue(creator != address(0));
        assertTrue(registered);
        assertTrue(initialized);
        // Base-native B20 bytecode is 0xef. Foundry's local fork EVM currently raises
        // OpcodeNotFound when executing it, so live B20 transfer execution must be
        // simulated on a Base node before broadcast rather than asserted locally.
        assertEq(LAUNCH.code, hex"ef");
    }

    function testAerodromePoolsAndLiveQuotes() public view {
        assertEq(IAeroFactory(AERO_FACTORY).getPool(WETH, VVV, false), WETH_VVV_POOL);
        assertEq(IAeroFactory(AERO_FACTORY).getPool(USDC, WETH, false), USDC_WETH_POOL);

        IAerodromeRouter.Route[] memory ethRoutes = new IAerodromeRouter.Route[](1);
        ethRoutes[0] = IAerodromeRouter.Route(WETH, VVV, false, AERO_FACTORY);
        uint256[] memory ethQuote = IAeroQuoter(AERO_ROUTER).getAmountsOut(0.001 ether, ethRoutes);
        assertGt(ethQuote[1], 0);

        IAerodromeRouter.Route[] memory usdcRoutes = new IAerodromeRouter.Route[](2);
        usdcRoutes[0] = IAerodromeRouter.Route(USDC, WETH, false, AERO_FACTORY);
        usdcRoutes[1] = IAerodromeRouter.Route(WETH, VVV, false, AERO_FACTORY);
        uint256[] memory usdcQuote = IAeroQuoter(AERO_ROUTER).getAmountsOut(1e6, usdcRoutes);
        assertGt(usdcQuote[2], 0);
    }

    function testLiveAerodromeETHToVVV() public {
        address user = makeAddr("aero-eth-user");
        vm.deal(user, 0.001 ether);
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route(WETH, VVV, false, AERO_FACTORY);
        vm.prank(user);
        uint256[] memory amounts = IAerodromeRouter(AERO_ROUTER).swapExactETHForTokens{value: 0.001 ether}(
            1, routes, user, block.timestamp + 60
        );
        assertGt(amounts[1], 0);
        assertEq(IERC20(VVV).balanceOf(user), amounts[1]);
    }

    function testLiveAerodromeUSDCToVVV() public {
        address user = makeAddr("aero-usdc-user");
        deal(USDC, user, 1e6);
        IAerodromeRouter.Route[] memory routes = new IAerodromeRouter.Route[](2);
        routes[0] = IAerodromeRouter.Route(USDC, WETH, false, AERO_FACTORY);
        routes[1] = IAerodromeRouter.Route(WETH, VVV, false, AERO_FACTORY);
        vm.startPrank(user);
        IERC20(USDC).approve(AERO_ROUTER, 1e6);
        uint256[] memory amounts =
            IAerodromeRouter(AERO_ROUTER).swapExactTokensForTokens(1e6, 1, routes, user, block.timestamp + 60);
        vm.stopPrank();
        assertGt(amounts[2], 0);
        assertEq(IERC20(VVV).balanceOf(user), amounts[2]);
    }
}
