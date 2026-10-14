# Hyperliquid info answers, as the adapter reads them

Notes from reading mainnet answers of `POST https://api.hyperliquid.xyz/info` (no key
needed) in October 2026. Addresses and hashes in the test fixtures are synthetic; the
shapes are the venue's.

## Requests

| Request body | Answer | Decoder |
| --- | --- | --- |
| `{"type":"userNonFundingLedgerUpdates","user":A,"startTime":ms}` | array of `{time, hash, delta}` | `Ledger_update.list_of_yojson` |
| `{"type":"userFunding","user":A,"startTime":ms}` | array of `{time, hash, delta: {type: "funding", coin, usdc, szi, fundingRate, nSamples}}` | `Funding.list_of_yojson` |
| `{"type":"delegatorRewards","user":A}` | array of `{time, source, totalAmount}` | `Staking_reward.list_of_yojson` |
| `{"type":"delegatorSummary","user":A}` | `{delegated, undelegated, totalPendingWithdrawal, nPendingWithdrawals}` | `Delegator_summary.of_yojson` |
| `{"type":"spotClearinghouseState","user":A}` | `{balances: [{coin, token, total, hold, entryNtl}]}` | `Spot_state.of_yojson` |
| `{"type":"clearinghouseState","user":A}` (and `"dex"`) | perpetuals account summary | `Hl_protocol.Clearinghouse_state` |
| `{"type":"userFillsByTime",...}` | fills | `Hl_protocol.User_fill.Detailed` |

Time-ranged requests answer at most 500 (fills, funding) or 2000 (ledger updates)
items; page by asking again from the last item's time. Event ids are deterministic, so
overlapping pages book once.

## Observations

- Amounts are decimal strings. Some carry more digits than the asset books:
  `requestedUsd: "5472272.8957780004"`, spot USDC `total: "0.00524174"` (8 digits),
  funding `szi: "3.7120833333"` (an hourly average, more digits than
  `Hl_protocol.Size` holds). The adapter reads them as exact rationals and rounds once.
- Funding items carry an all-zero hash; they are identified by time and coin.
- A `send` moves a token between dexes and spot (`sourceDex`, `destinationDex`: `""` is
  the default perpetuals dex, `"spot"` the spot account), possibly to the same address.
- `spotTransfer` and `send` carry `fee` (USDC unless `feeToken` says otherwise) and
  `nativeTokenFee`.
- `withdraw` reports the amount sent and a separate `fee` (1 USDC in the samples).
- `vaultWithdraw` appears in the vault's history for every depositor; the adapter books
  it only when `user` is the configured address.
- `gossipPriorityGasAuction` spends HYPE from spot (a fee).
- Types seen and not booked: `liquidation`, `borrowLend`, `activateDexAbstraction`.
