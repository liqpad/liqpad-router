// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {ILiqpadFactory} from "./interfaces/ILiqpadFactory.sol";
import {IAerodromeRouter} from "./interfaces/IAerodromeRouter.sol";

/// @title LiqpadSwapRouter
/// @notice Exact-input router for official Liqpad B20/VVV pools with fixed Aerodrome ETH/USDC routes.
contract LiqpadSwapRouter is IUnlockCallback, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint24 public constant POOL_FEE = 0;
    int24 public constant TICK_SPACING = 200;

    ILiqpadFactory public immutable factory;
    IPoolManager public immutable poolManager;
    address public immutable launchHook;
    address public immutable VVV;
    address public immutable permit2;
    IAerodromeRouter public immutable aerodromeRouter;
    address public immutable aerodromeFactory;
    address public immutable WETH;
    address public immutable USDC;

    error DeadlineExpired(uint256 deadline);
    error InvalidAddress();
    error InvalidAmount();
    error InvalidLiqpadToken(address token);
    error OnlyPoolManager();
    error SlippageExceeded(uint256 amountOut, uint256 minimum);
    error UnsupportedTokenBehavior(address token, uint256 expected, uint256 received);
    error NativeETHNotAccepted();
    error UnexpectedDelta();

    event SwapExecuted(
        address indexed payer,
        address indexed recipient,
        address indexed b20,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    struct CallbackData {
        PoolKey key;
        address recipient;
        address tokenIn;
        uint256 amountIn;
        uint256 amountOutMinimum;
        bool zeroForOne;
    }

    constructor(
        address factory_,
        address poolManager_,
        address launchHook_,
        address vvv_,
        address permit2_,
        address aerodromeRouter_,
        address aerodromeFactory_,
        address weth_,
        address usdc_
    ) {
        if (
            factory_ == address(0) || poolManager_ == address(0) || launchHook_ == address(0) || vvv_ == address(0)
                || permit2_ == address(0) || aerodromeRouter_ == address(0) || aerodromeFactory_ == address(0)
                || weth_ == address(0) || usdc_ == address(0)
        ) revert InvalidAddress();
        factory = ILiqpadFactory(factory_);
        poolManager = IPoolManager(poolManager_);
        launchHook = launchHook_;
        VVV = vvv_;
        permit2 = permit2_;
        aerodromeRouter = IAerodromeRouter(aerodromeRouter_);
        aerodromeFactory = aerodromeFactory_;
        WETH = weth_;
        USDC = usdc_;
    }

    receive() external payable {
        if (msg.sender != address(aerodromeRouter)) revert NativeETHNotAccepted();
    }

    function poolKey(address b20) public view returns (PoolKey memory key) {
        _validateB20(b20);
        (address c0, address c1) = b20 < VVV ? (b20, VVV) : (VVV, b20);
        key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), POOL_FEE, TICK_SPACING, IHooks(launchHook));
    }

    function swapExactVVVForB20(address b20, uint256 amountIn, uint256 minimumOut, address recipient, uint256 deadline)
        external
        nonReentrant
        returns (uint256)
    {
        return _swapPulled(b20, VVV, amountIn, minimumOut, recipient, deadline);
    }

    function swapExactB20ForVVV(address b20, uint256 amountIn, uint256 minimumOut, address recipient, uint256 deadline)
        external
        nonReentrant
        returns (uint256)
    {
        return _swapPulled(b20, b20, amountIn, minimumOut, recipient, deadline);
    }

    function swapExactETHForB20(
        address b20,
        uint256 minimumVVV,
        uint256 minimumB20,
        address recipient,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountOut) {
        _validateCommon(msg.value, recipient, deadline);
        uint256[] memory amounts = aerodromeRouter.swapExactETHForTokens{value: msg.value}(
            minimumVVV, _routeWethVvv(false), address(this), deadline
        );
        amountOut = _swapHeld(b20, VVV, amounts[amounts.length - 1], minimumB20, recipient, msg.sender);
    }

    function swapExactUSDCForB20(
        address b20,
        uint256 amountIn,
        uint256 minimumVVV,
        uint256 minimumB20,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        _validateCommon(amountIn, recipient, deadline);
        _pullExact(USDC, msg.sender, amountIn);
        uint256 vvvOut = _aeroTokens(USDC, amountIn, minimumVVV, _routeUsdcVvv(false), deadline);
        amountOut = _swapHeld(b20, VVV, vvvOut, minimumB20, recipient, msg.sender);
    }

    function swapExactB20ForETH(
        address b20,
        uint256 amountIn,
        uint256 minimumVVV,
        uint256 minimumETH,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        uint256 vvvOut = _swapPulled(b20, b20, amountIn, minimumVVV, address(this), deadline);
        _approveExact(VVV, address(aerodromeRouter), vvvOut);
        uint256[] memory amounts =
            aerodromeRouter.swapExactTokensForETH(vvvOut, minimumETH, _routeWethVvv(true), recipient, deadline);
        _approveExact(VVV, address(aerodromeRouter), 0);
        amountOut = amounts[amounts.length - 1];
    }

    function swapExactB20ForUSDC(
        address b20,
        uint256 amountIn,
        uint256 minimumVVV,
        uint256 minimumUSDC,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        uint256 vvvOut = _swapPulled(b20, b20, amountIn, minimumVVV, address(this), deadline);
        amountOut = _aeroTokens(VVV, vvvOut, minimumUSDC, _routeUsdcVvv(true), deadline);
        IERC20(USDC).safeTransfer(recipient, amountOut);
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory result) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = poolManager.swap(
            data.key,
            SwapParams({
                zeroForOne: data.zeroForOne,
                amountSpecified: -int256(data.amountIn),
                sqrtPriceLimitX96: data.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            bytes("")
        );
        int128 inputDelta = data.zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = data.zeroForOne ? delta.amount1() : delta.amount0();
        if (inputDelta >= 0 || outputDelta <= 0) revert UnexpectedDelta();
        uint256 paid = uint256(uint128(-inputDelta));
        uint256 amountOut = uint256(uint128(outputDelta));
        if (paid > data.amountIn) revert UnexpectedDelta();
        if (amountOut < data.amountOutMinimum) revert SlippageExceeded(amountOut, data.amountOutMinimum);
        Currency input = data.zeroForOne ? data.key.currency0 : data.key.currency1;
        Currency output = data.zeroForOne ? data.key.currency1 : data.key.currency0;
        poolManager.sync(input);
        IERC20(data.tokenIn).safeTransfer(address(poolManager), paid);
        poolManager.settle();
        poolManager.take(output, data.recipient, amountOut);
        result = abi.encode(amountOut, paid);
    }

    function _swapPulled(
        address b20,
        address tokenIn,
        uint256 amountIn,
        uint256 minimumOut,
        address recipient,
        uint256 deadline
    ) private returns (uint256 amountOut) {
        _validateCommon(amountIn, recipient, deadline);
        _pullExact(tokenIn, msg.sender, amountIn);
        amountOut = _swapHeld(b20, tokenIn, amountIn, minimumOut, recipient, msg.sender);
    }

    function _swapHeld(
        address b20,
        address tokenIn,
        uint256 amountIn,
        uint256 minimumOut,
        address recipient,
        address payer
    ) private returns (uint256 amountOut) {
        PoolKey memory key = poolKey(b20);
        bool zeroForOne = tokenIn == Currency.unwrap(key.currency0);
        bytes memory returned =
            poolManager.unlock(abi.encode(CallbackData(key, recipient, tokenIn, amountIn, minimumOut, zeroForOne)));
        uint256 paid;
        (amountOut, paid) = abi.decode(returned, (uint256, uint256));
        if (paid < amountIn) IERC20(tokenIn).safeTransfer(payer, amountIn - paid);
        emit SwapExecuted(payer, recipient, b20, tokenIn, tokenIn == VVV ? b20 : VVV, paid, amountOut);
    }

    function _aeroTokens(
        address tokenIn,
        uint256 amountIn,
        uint256 minimumOut,
        IAerodromeRouter.Route[] memory routes,
        uint256 deadline
    ) private returns (uint256 amountOut) {
        _approveExact(tokenIn, address(aerodromeRouter), amountIn);
        uint256[] memory amounts =
            aerodromeRouter.swapExactTokensForTokens(amountIn, minimumOut, routes, address(this), deadline);
        _approveExact(tokenIn, address(aerodromeRouter), 0);
        amountOut = amounts[amounts.length - 1];
    }

    function _routeWethVvv(bool reverse) private view returns (IAerodromeRouter.Route[] memory routes) {
        routes = new IAerodromeRouter.Route[](1);
        routes[0] = IAerodromeRouter.Route(reverse ? VVV : WETH, reverse ? WETH : VVV, false, aerodromeFactory);
    }

    function _routeUsdcVvv(bool reverse) private view returns (IAerodromeRouter.Route[] memory routes) {
        routes = new IAerodromeRouter.Route[](2);
        routes[0] = IAerodromeRouter.Route(reverse ? VVV : USDC, WETH, false, aerodromeFactory);
        routes[1] = IAerodromeRouter.Route(WETH, reverse ? USDC : VVV, false, aerodromeFactory);
    }

    function _pullExact(address token, address from, uint256 amount) private {
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(from, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert UnsupportedTokenBehavior(token, amount, received);
    }

    function _approveExact(address token, address spender, uint256 amount) private {
        IERC20(token).forceApprove(spender, amount);
    }

    function _validateCommon(uint256 amountIn, address recipient, uint256 deadline) private view {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline);
        if (amountIn == 0 || amountIn > uint256(uint128(type(int128).max))) revert InvalidAmount();
        if (recipient == address(0)) revert InvalidAddress();
    }

    function _validateB20(address b20) private view {
        if (b20 == address(0) || b20 == VVV || !factory.isLiqpadLaunch(b20)) revert InvalidLiqpadToken(b20);
    }
}
