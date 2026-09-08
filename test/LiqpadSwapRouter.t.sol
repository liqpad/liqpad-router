// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LiqpadSwapRouter} from "../src/LiqpadSwapRouter.sol";
import {IAerodromeRouter} from "../src/interfaces/IAerodromeRouter.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockFactory {
    mapping(address => bool) public isLiqpadLaunch;

    function setLaunch(address token, bool valid) external {
        isLiqpadLaunch[token] = valid;
    }
}

contract MockPoolManager {
    uint256 public paidBps = 10_000;
    uint256 public outputBps = 20_000;
    address private input;
    address private output;
    uint256 private debt;

    function setPaidBps(uint256 value) external {
        paidBps = value;
    }

    function unlock(bytes calldata data) external returns (bytes memory) {
        return IUnlockCallback(msg.sender).unlockCallback(data);
    }

    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        returns (BalanceDelta delta)
    {
        uint256 requested = uint256(-params.amountSpecified);
        uint256 paid = requested * paidBps / 10_000;
        uint256 amountOut = paid * outputBps / 10_000;
        input = Currency.unwrap(params.zeroForOne ? key.currency0 : key.currency1);
        output = Currency.unwrap(params.zeroForOne ? key.currency1 : key.currency0);
        debt = paid;
        delta = params.zeroForOne
            ? toBalanceDelta(-int128(int256(paid)), int128(int256(amountOut)))
            : toBalanceDelta(int128(int256(amountOut)), -int128(int256(paid)));
    }

    function sync(Currency currency) external view {
        require(Currency.unwrap(currency) == input);
    }

    function settle() external payable returns (uint256) {
        require(MockToken(input).balanceOf(address(this)) >= debt);
        return debt;
    }

    function take(Currency currency, address to, uint256 amount) external {
        require(Currency.unwrap(currency) == output);
        uint256 balance = MockToken(output).balanceOf(address(this));
        if (balance < amount) MockToken(output).mint(address(this), amount - balance);
        MockToken(output).transfer(to, amount);
    }
}

contract MockAerodromeRouter {
    receive() external payable {}

    function swapExactETHForTokens(uint256 minimum, IAerodromeRouter.Route[] calldata routes, address to, uint256)
        external
        payable
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](routes.length + 1);
        amounts[0] = msg.value;
        amounts[routes.length] = msg.value * 2;
        require(amounts[routes.length] >= minimum);
        MockToken(routes[routes.length - 1].to).mint(to, amounts[routes.length]);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 minimum,
        IAerodromeRouter.Route[] calldata routes,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        MockToken(routes[0].from).transferFrom(msg.sender, address(this), amountIn);
        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;
        amounts[routes.length] = amountIn * 2;
        require(amounts[routes.length] >= minimum);
        MockToken(routes[routes.length - 1].to).mint(to, amounts[routes.length]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 minimum,
        IAerodromeRouter.Route[] calldata routes,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        MockToken(routes[0].from).transferFrom(msg.sender, address(this), amountIn);
        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;
        amounts[routes.length] = amountIn * 2;
        require(amounts[routes.length] >= minimum);
        (bool ok,) = to.call{value: amounts[routes.length]}("");
        require(ok);
    }
}

contract LiqpadSwapRouterTest is Test {
    MockFactory factory;
    MockPoolManager manager;
    MockToken vvv;
    MockToken b20;
    MockToken weth;
    MockToken usdc;
    MockAerodromeRouter aero;
    LiqpadSwapRouter router;
    address user = address(0xA11CE);
    address recipient = address(0xB0B);
    address hook = address(0xC5a8);

    function setUp() public {
        factory = new MockFactory();
        manager = new MockPoolManager();
        vvv = new MockToken();
        b20 = new MockToken();
        weth = new MockToken();
        usdc = new MockToken();
        aero = new MockAerodromeRouter();
        vm.deal(address(aero), 1_000 ether);
        factory.setLaunch(address(b20), true);
        router = new LiqpadSwapRouter(
            address(factory),
            address(manager),
            hook,
            address(vvv),
            address(0x22D4),
            address(aero),
            address(0xFACA),
            address(weth),
            address(usdc)
        );
        vvv.mint(user, 100 ether);
        b20.mint(user, 100 ether);
        usdc.mint(user, 100 ether);
        vvv.mint(address(manager), 1_000 ether);
        b20.mint(address(manager), 1_000 ether);
        vm.startPrank(user);
        vvv.approve(address(router), type(uint256).max);
        b20.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function testVVVForB20() public {
        vm.prank(user);
        uint256 out = router.swapExactVVVForB20(address(b20), 1 ether, 2 ether, recipient, block.timestamp);
        assertEq(out, 2 ether);
        assertEq(b20.balanceOf(recipient), 2 ether);
        assertEq(vvv.balanceOf(address(router)), 0);
    }

    function testB20ForVVV() public {
        vm.prank(user);
        router.swapExactB20ForVVV(address(b20), 1 ether, 2 ether, recipient, block.timestamp);
        assertEq(vvv.balanceOf(recipient), 2 ether);
        assertEq(b20.balanceOf(address(router)), 0);
    }

    function testETHForB20() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        uint256 out =
            router.swapExactETHForB20{value: 1 ether}(address(b20), 2 ether, 4 ether, recipient, block.timestamp);
        assertEq(out, 4 ether);
        assertEq(b20.balanceOf(recipient), 4 ether);
        assertEq(address(router).balance, 0);
    }

    function testUSDCForB20() public {
        vm.prank(user);
        uint256 out = router.swapExactUSDCForB20(address(b20), 1 ether, 2 ether, 4 ether, recipient, block.timestamp);
        assertEq(out, 4 ether);
        assertEq(usdc.allowance(address(router), address(aero)), 0);
    }

    function testB20ForETH() public {
        uint256 beforeBalance = recipient.balance;
        vm.prank(user);
        uint256 out = router.swapExactB20ForETH(address(b20), 1 ether, 2 ether, 4 ether, recipient, block.timestamp);
        assertEq(out, 4 ether);
        assertEq(recipient.balance - beforeBalance, 4 ether);
        assertEq(vvv.allowance(address(router), address(aero)), 0);
    }

    function testB20ForUSDC() public {
        vm.prank(user);
        uint256 out = router.swapExactB20ForUSDC(address(b20), 1 ether, 2 ether, 4 ether, recipient, block.timestamp);
        assertEq(out, 4 ether);
        assertEq(usdc.balanceOf(recipient), 4 ether);
        assertEq(vvv.allowance(address(router), address(aero)), 0);
    }

    function testPoolKeyOrdering() public view {
        PoolKey memory key = router.poolKey(address(b20));
        assertLt(uint160(Currency.unwrap(key.currency0)), uint160(Currency.unwrap(key.currency1)));
        assertEq(key.fee, 0);
        assertEq(key.tickSpacing, 200);
        assertEq(address(key.hooks), hook);
    }

    function testRefundOnPartialFill() public {
        manager.setPaidBps(5_000);
        uint256 beforeBalance = vvv.balanceOf(user);
        vm.prank(user);
        router.swapExactVVVForB20(address(b20), 2 ether, 2 ether, recipient, block.timestamp);
        assertEq(beforeBalance - vvv.balanceOf(user), 1 ether);
        assertEq(vvv.balanceOf(address(router)), 0);
    }

    function testRevertInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(LiqpadSwapRouter.InvalidLiqpadToken.selector, address(0xBAD)));
        router.poolKey(address(0xBAD));
    }

    function testRevertExpired() public {
        vm.warp(10);
        vm.expectRevert(abi.encodeWithSelector(LiqpadSwapRouter.DeadlineExpired.selector, 9));
        vm.prank(user);
        router.swapExactVVVForB20(address(b20), 1, 0, recipient, 9);
    }

    function testRevertSlippage() public {
        vm.expectRevert(abi.encodeWithSelector(LiqpadSwapRouter.SlippageExceeded.selector, 2 ether, 3 ether));
        vm.prank(user);
        router.swapExactVVVForB20(address(b20), 1 ether, 3 ether, recipient, block.timestamp);
    }

    function testRevertZeroInput() public {
        vm.expectRevert(LiqpadSwapRouter.InvalidAmount.selector);
        vm.prank(user);
        router.swapExactVVVForB20(address(b20), 0, 0, recipient, block.timestamp);
    }

    function testRevertZeroRecipient() public {
        vm.expectRevert(LiqpadSwapRouter.InvalidAddress.selector);
        vm.prank(user);
        router.swapExactVVVForB20(address(b20), 1, 0, address(0), block.timestamp);
    }

    function testOnlyManagerCallback() public {
        vm.expectRevert(LiqpadSwapRouter.OnlyPoolManager.selector);
        router.unlockCallback("");
    }

    function testFuzzExactInput(uint96 amount, address fuzzRecipient, uint96 minOut) public {
        vm.assume(amount > 0 && fuzzRecipient != address(0));
        minOut = uint96(bound(minOut, 0, uint256(amount) * 2));
        vvv.mint(user, amount);
        vm.prank(user);
        uint256 out = router.swapExactVVVForB20(address(b20), amount, minOut, fuzzRecipient, block.timestamp);
        assertEq(out, uint256(amount) * 2);
    }
}
