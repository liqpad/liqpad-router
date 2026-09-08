// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {LiqpadSwapRouter} from "../src/LiqpadSwapRouter.sol";

interface IAeroFactoryCheck {
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
}

interface IAeroRouterCheck {
    function weth() external view returns (address);
    function defaultFactory() external view returns (address);
}

interface ILiqpadFactoryCheck {
    function VVV() external view returns (address);
    function poolManager() external view returns (address);
    function launchHook() external view returns (address);
}

contract DeployLiqpadSwapRouter is Script {
    address constant FACTORY = 0x38472Ca56a93CAa68459fD11FDd2EEb130D06b29;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant HOOK = 0xC5a862dD09Df3585e0A5d3BC32AC4Fe7efE0A0cc;
    address constant VVV = 0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant AERO_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERO_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH_VVV_POOL = 0x01784ef301D79e4B2DF3a21ad9a536d4cF09A5Ce;
    address constant USDC_WETH_POOL = 0xcDAC0d6c6C59727a65F871236188350531885C43;

    function run() external returns (LiqpadSwapRouter router) {
        require(block.chainid == 8453, "BASE_MAINNET_ONLY");
        _preflight();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(deployerPrivateKey != 0, "PRIVATE_KEY_REQUIRED");
        vm.startBroadcast(deployerPrivateKey);
        router = new LiqpadSwapRouter(FACTORY, POOL_MANAGER, HOOK, VVV, PERMIT2, AERO_ROUTER, AERO_FACTORY, WETH, USDC);
        vm.stopBroadcast();
    }

    function _preflight() private view {
        require(FACTORY.code.length != 0, "FACTORY_NO_CODE");
        require(POOL_MANAGER.code.length != 0, "POOL_MANAGER_NO_CODE");
        require(HOOK.code.length != 0, "HOOK_NO_CODE");
        require(VVV.code.length != 0, "VVV_NO_CODE");
        require(PERMIT2.code.length != 0, "PERMIT2_NO_CODE");
        require(AERO_ROUTER.code.length != 0, "AERO_ROUTER_NO_CODE");
        require(AERO_FACTORY.code.length != 0, "AERO_FACTORY_NO_CODE");
        require(WETH.code.length != 0, "WETH_NO_CODE");
        require(USDC.code.length != 0, "USDC_NO_CODE");

        require(ILiqpadFactoryCheck(FACTORY).VVV() == VVV, "FACTORY_VVV_MISMATCH");
        require(ILiqpadFactoryCheck(FACTORY).poolManager() == POOL_MANAGER, "FACTORY_MANAGER_MISMATCH");
        require(ILiqpadFactoryCheck(FACTORY).launchHook() == HOOK, "FACTORY_HOOK_MISMATCH");
        require(IAeroRouterCheck(AERO_ROUTER).weth() == WETH, "AERO_WETH_MISMATCH");
        require(IAeroRouterCheck(AERO_ROUTER).defaultFactory() == AERO_FACTORY, "AERO_FACTORY_MISMATCH");
        require(IAeroFactoryCheck(AERO_FACTORY).getPool(WETH, VVV, false) == WETH_VVV_POOL, "WETH_VVV_POOL_MISMATCH");
        require(IAeroFactoryCheck(AERO_FACTORY).getPool(USDC, WETH, false) == USDC_WETH_POOL, "USDC_WETH_POOL_MISMATCH");
    }
}
