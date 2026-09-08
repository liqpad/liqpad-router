# Liqpad Swap Router

Foundry deployment package for an exact-input-only router restricted to official Liqpad B20/VVV pools on Base (chain ID 8453).

## Supported in this revision

- `swapExactVVVForB20`
- `swapExactB20ForVVV`
- `swapExactETHForB20`: Aerodrome WETH/VVV volatile, then Liqpad v4 VVV/B20.
- `swapExactUSDCForB20`: Aerodrome USDC/WETH/VVV volatile, then Liqpad v4 VVV/B20.
- `swapExactB20ForETH`: Liqpad v4 B20/VVV, then Aerodrome VVV/WETH and native ETH output.
- `swapExactB20ForUSDC`: Liqpad v4 B20/VVV, then Aerodrome VVV/WETH/USDC.
- Currency ordering is derived from the B20 and VVV addresses.
- Pool key is fixed to fee `0`, tick spacing `200`, and the immutable Liqpad launch hook.
- Factory validation uses `isLiqpadLaunch(token)`.
- Final-output slippage, deadline, recipient, partial-fill refund, SafeERC20, and reentrancy checks are enforced.

Aerodrome routes are immutable Basic Volatile routes (`stable=false`) through its canonical Base Router and PoolFactory. Users cannot provide arbitrary routes, factories, pools, targets, or calldata.

## Token movement and approvals

The direct router uses ordinary ERC-20 `transferFrom`, not Permit2. A user approves only the router for the exact amount (or a wallet-selected allowance). The router does not grant PoolManager or Permit2 an allowance: inside the unlock callback it calls `sync`, transfers the exact debt to PoolManager, then calls `settle`. Any unspent exact-input amount caused by a price-bound partial fill is returned to the payer. Output is taken directly from PoolManager to the requested recipient.

For Aerodrome legs, the router grants only the exact input allowance immediately before the call and resets it to zero afterward. Permit2 remains unused and receives no approval.

Fee-on-transfer inputs are rejected by an exact pre/post balance check. Rebasing assets are unsupported. Liqpad B20 and VVV are expected to have standard amount-preserving transfers.

## Slippage

Direct routes use one `minimumOut`. Convenience routes require both `minimumVVV` and the minimum final B20/ETH/USDC output. Both legs are atomic; failure of either minimum rolls back the complete transaction, including hook fee accounting.

## Native ETH

Aerodrome wraps incoming ETH and unwraps WETH on sell. The Liqpad router accepts raw ETH only from the immutable Aerodrome Router; unsolicited ETH reverts. Aerodrome sends sell output directly to the requested recipient.

## Commands

```bash
cp .env.example .env
# Fill PRIVATE_KEY and ETHERSCAN_API_KEY. Replace BASE_RPC_URL if desired.
set -a
source .env
set +a

forge fmt --check
forge build
forge test --no-match-path test/LiqpadSwapRouterFork.t.sol
forge test --match-path test/LiqpadSwapRouterFork.t.sol -vv
forge test --gas-report
```

Dry-run deployment (no broadcast):

```bash
forge script script/DeployLiqpadSwapRouter.s.sol:DeployLiqpadSwapRouter \
  --rpc-url "$BASE_RPC_URL" -vvvv
```

The deployment script checks chain ID, bytecode at every dependency, all Liqpad Factory bindings, Aerodrome Router bindings, and both Aerodrome pools before deployment.

Broadcast after a successful dry-run:

```bash
forge script script/DeployLiqpadSwapRouter.s.sol:DeployLiqpadSwapRouter \
  --rpc-url "$BASE_RPC_URL" \
  --broadcast \
  -vvvv
```

The key is loaded inside the script from `PRIVATE_KEY`; it is not placed in the command line. Save the deployed router address printed by Forge before verification.

## Mainnet buy/sell smoke test

The deployed router is `0xf05ce37534a00C6815EE062FF6A10603C49c28A9`, and the reference B20 is
`0xB200000000000000000000defA12971e32B3BB07`. Buy and sell are intentionally separate so each
sell uses the actual post-buy B20 balance after the buy has been mined.

Available scripts:

| Operation | Script | Default input |
|---|---|---|
| ETH -> B20 | `SmokeBuyWithETH.s.sol` | `0.000001 ETH` |
| B20 -> ETH | `SmokeSellForETH.s.sol` | explicit `SMOKE_SELL_B20_IN` |
| USDC -> B20 | `SmokeBuyWithUSDC.s.sol` | `0.01 USDC` |
| B20 -> USDC | `SmokeSellForUSDC.s.sol` | explicit `SMOKE_SELL_B20_IN` |

Use the same command pattern for each script. Simulate first:

```bash
base-forge script script/SmokeBuyWithETH.s.sol:SmokeBuyWithETH --rpc-url "$BASE_RPC_URL" -vvvv
base-forge script script/SmokeBuyWithUSDC.s.sol:SmokeBuyWithUSDC --rpc-url "$BASE_RPC_URL" -vvvv
```

Then broadcast only the selected buy, with `--broadcast --slow`. After it is mined, obtain the
actual B20 balance:

```bash
export SMOKE_SELL_B20_IN="$(base-cast call \
  0xB200000000000000000000defA12971e32B3BB07 \
  'balanceOf(address)(uint256)' \
  "$(base-cast wallet address --private-key "$PRIVATE_KEY")" \
  --rpc-url "$BASE_RPC_URL" | awk '{print $1}')"

echo "$SMOKE_SELL_B20_IN"
```

Simulate the selected sell:

```bash
base-forge script script/SmokeSellForETH.s.sol:SmokeSellForETH --rpc-url "$BASE_RPC_URL" -vvvv
base-forge script script/SmokeSellForUSDC.s.sol:SmokeSellForUSDC --rpc-url "$BASE_RPC_URL" -vvvv
```

After a simulation succeeds, append `--broadcast --slow` to that exact command. `--slow` waits for
approval, swap, and approval reset sequentially. Each token script approves only its exact input
and resets any remaining allowance to zero.

This smoke test must use Base's Foundry build (`base-forge`), not upstream `forge`. B20 tokens are
native Base precompiles, and upstream Foundry currently fails while locally simulating their calls
with `OpcodeNotFound`. The `base = true` setting in `foundry.toml` activates Base precompile support.
Confirm the correct binary before running:

```bash
base-forge --version
```

The `SMOKE_MIN_*` defaults are `1`, intentionally suitable only for a minimum-value connectivity
test. They guarantee nonzero intermediate/final output but provide effectively no economic
slippage protection. For a larger amount, replace them with fresh per-leg quoted minima before
broadcasting. Gas is additional to the configured input.

Verification after deployment:

```bash
forge verify-contract \
  --chain-id 8453 \
  --verifier etherscan \
  --etherscan-api-key "$ETHERSCAN_API_KEY" \
  --constructor-args "$(cast abi-encode 'constructor(address,address,address,address,address,address,address,address,address)' \
    0x38472ca56a93caa68459fd11fdd2eeb130d06b29 \
    0x498581fF718922c3f8e6A244956aF099B2652b2b \
    0xC5a862dD09Df3585e0A5d3BC32AC4Fe7efE0A0cc \
    0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf \
    0x000000000022D473030F116dDEE9F6B43aC78BA3 \
    0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43 \
    0x420DD381b31aEf6683db6B902084cB0FFECe40Da \
    0x4200000000000000000000000000000000000006 \
    0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)" \
  <DEPLOYED_ROUTER> src/LiqpadSwapRouter.sol:LiqpadSwapRouter
```

## Verified addresses

| Component | Base mainnet address | Verification used |
|---|---|---|
| LiqpadFactory | `0x38472ca56a93caa68459fd11fdd2eeb130d06b29` | verified source + live getters |
| FeeRouter | `0x08a8cafefd4816451a18097372bb85153085270f` | verified source |
| LockedPositionVault | `0x4ac4efaeda765e6350817caaf4000138b730ae31` | verified source |
| LiqpadLaunchHook | `0xC5a862dD09Df3585e0A5d3BC32AC4Fe7efE0A0cc` | verified source + registered live pool |
| PoolManager | `0x498581fF718922c3f8e6A244956aF099B2652b2b` | factory getter + live calls |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | supplied canonical address; unused by v1 |
| VVV | `0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf` | factory/hook immutable getter |
| Reference B20 | `0xb200000000000000000000defa12971e32b3bb07` | launch tx + factory mapping + hook pool record |
| Aerodrome Router | `0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43` | official deployment source + live quote calls |
| Aerodrome PoolFactory | `0x420DD381b31aEf6683db6B902084cB0FFECe40Da` | official deployment source + router getter |
| WETH | `0x4200000000000000000000000000000000000006` | Aerodrome router getter |
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | Base native USDC |
| WETH/VVV pool | `0x01784ef301D79e4B2DF3a21ad9a536d4cF09A5Ce` | PoolFactory `getPool(..., false)` |
| USDC/WETH pool | `0xcDAC0d6c6C59727a65F871236188350531885C43` | PoolFactory `getPool(..., false)` |

HookDeployer is not a router constructor dependency.

## Open risks and assumptions

- Upstream Foundry cannot execute Base-native B20 precompiles in its local EVM and reports
  `OpcodeNotFound`. B20 smoke tests therefore require Base Foundry with `base = true`.
- Aerodrome liquidity, reserves, and quoted output can change; the web client must calculate fresh per-leg minima immediately before signing.
- The router assumes VVV and B20 transfers preserve amounts; fee-on-transfer and rebasing behavior is unsupported.
- Deployment uses ordinary CREATE, not CREATE2. The resulting address depends on the selected deployer and its nonce.
