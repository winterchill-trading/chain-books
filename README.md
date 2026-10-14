# chain-books

Double-entry books for an organisation's on-chain treasury, in OCaml. Venue records
(fills, funding payments, deposits, withdrawals and transfers, staking rewards,
builder-fee income) are normalised into activities, booked as balanced
[ledger](https://github.com/winterchill-trading/ledger) entries over a chart of accounts,
tracked as positions with a cost basis, valued at market through a price hook, and
reconciled against the balances the chain reports. Pure: no storage, no network, no
clock. Built for the [OxCaml](https://oxcaml.org) compiler and the Jane Street stack.

A sub-library, `chain-books.hyperliquid`, normalises Hyperliquid records: the fills and
account state from [hl-protocol](https://github.com/winterchill-trading/hl-protocol), and
its own decoders for the info answers hl-protocol does not cover.

## Why separate

A treasury that holds assets on a chain needs the same books as one that holds them at a
bank: every movement booked once, an audit trail that balances, positions with a cost
basis, and a daily check that what the books say is what the chain says. The chain side
has its own problems: histories are read in windows (so opening balances must be
derived), the same transfer shows up in two accounts' histories, venues report more
digits than the asset books, a write may or may not have landed when the network fails.
None of that is specific to one venue or one service, so it lives here, venue adapters
plug in through one module type, and services keep only their storage and scheduling.

## Install

Not on opam yet. With an OxCaml switch (`5.2.0+ox`), pin the organisation's libraries in
dependency order:

```sh
opam pin add fixed-decimal https://github.com/winterchill-trading/fixed-decimal.git
opam pin add exchange-core https://github.com/winterchill-trading/exchange-core.git
opam pin add hl-protocol https://github.com/winterchill-trading/hl-protocol.git
opam pin add money https://github.com/winterchill-trading/money.git
opam pin add ledger https://github.com/winterchill-trading/ledger.git
opam pin add chain-books https://github.com/winterchill-trading/chain-books.git
```

Then add `chain-books` (and `chain-books.hyperliquid`) to a dune stanza's `libraries`.
Build with `dune build`, test with `dune test`. No environment variables.

## Quick start

```ocaml
let books = Books.create (Chart.create (Binding_id.of_string "treasury")) in
let books, report = Books.ingest books history ~at |> Or_error.ok_exn in
(* the first balance report: whatever the window did not book is the opening balance *)
let books, openings =
  Books.open_balances books observed ~history_start ~at |> Or_error.ok_exn
in
let breaks = Reconciliation.breaks (Books.reconcile books observed) in
let valuation = Books.value books prices ~currency:Money.Currency.usdc ~now in
...
```

The complete program, with its output checked by `dune test`, is
[examples/quickstart.ml](examples/quickstart.ml):

```text
booked 5 entries
fill-2 realised 20.000000 USDC
0x00000000000000000000000000000000000000a1:perp 768.910000 USDC
0x00000000000000000000000000000000000000a1:spot 250.000000 USDC
opening 0x00000000000000000000000000000000000000a1:perp 0.000000 USDC
opening 0x00000000000000000000000000000000000000a1:spot 120.000000 USDC
breaks: 0
value 1138.910000 USDC
```

## Model

A **binding** is the set of on-chain addresses one organisation's books follow. A
**location** is one venue of one address: `perp` (or `perp:<dex>` for a separately
margined perpetuals exchange), `spot`, `rewards`, `vault`, `staking`. Each location has
one custody account holding every asset found there; assets are `money` currencies
(`USDC` at 6 digits, `HYPE` at 8, more registered with `Assets.register_token`).

An **activity** is one movement of one asset at one location, signed from the location's
side, with a deterministic event id and a counter: another location of the binding, or a
counterparty category.

| Category | Kind | Meaning |
| --- | --- | --- |
| `bridge` | Equity | deposits from and withdrawals to other chains |
| `external` | Equity | transfers with addresses outside the binding |
| `spot_clearing` | Asset (clearing) | the other leg of spot trades, per asset |
| `perp_pnl` | Income | realised profit and loss of perpetual positions |
| `trading_fees` | Expense | trading, transfer and gas fees |
| `funding` | Income | funding received (negative when paid) |
| `builder_fees` | Income | builder-fee income (negative for builder fees paid) |
| `referral_rewards`, `vault_commission`, `staking_rewards` | Income | rewards |
| `vaults` | Asset | equity placed in vaults run by others |
| `opening_balance` | Equity | balances found when the books start |
| `other` | Asset | suspense |
| custom | any | a service's own category, chosen through the `classify` hook |

Account ids: `chain:<binding>:custody:<address>:<venue>` and `chain:<binding>:cp:<category>`.

## Rules

- One activity, one single-currency entry, keyed `chain:<binding>:<event id>`. Reading
  the same history twice books it once; an event id reused for another movement is an
  error.
- A movement between two locations of the binding is one activity with both locations in
  one entry. Adapters build event ids that do not depend on which address read the
  record, so a transfer both histories contain books once.
- Amounts are rounded to the asset's minor unit once, half-even, in the adapter.
- Custody accounts may go negative: one side of a transfer can be read before the other.
- Zero amounts and assets outside an optional followed set book nothing and are reported.
- The opening balance of a location and asset is derived once, at its first observation,
  as observed minus booked, dated at the start of the history window. Later differences
  are breaks.
- Reconciliation never books. Statuses: matched (within a tolerance), difference,
  untracked (reported, never booked), not reported (booked, missing from the report).
  Perpetual positions are reconciled by size.
- Positions: FIFO or average cost, per address and instrument; fees are not capitalised,
  matching how venues report closed profit. Each fill applies once. A fill's realised
  profit is compared with the venue's figure.
- Valuation: balances at rates, open positions at marks, both through `Price_source`;
  stale or missing prices leave a line unvalued and are listed; the total is summed
  exactly and rounded once.
- Chain writes: prepare with a nonce (`max(now ms, last + 1)` per signer), store the exact
  body, resend the same body after an unknown outcome with doubling delays (15 s to
  30 min, 10 attempts), confirm when a sync sees the movement. A refusal needs a
  reversal; a reused nonce or exhausted attempts end `unconfirmed`, never reversed
  automatically.

## Hyperliquid adapter

`Chain_books_hyperliquid.Adapter` implements `Chain_books.Normalizer.S`.

| Record | Source | Activities |
| --- | --- | --- |
| Fill (perp) | `userFills`, `userFillsByTime`, websocket `userEvents` (hl-protocol `User_fill.Detailed`) | `fill:<tid>:pnl`, `:fee` (exchange part), `:builder` (builder fee paid) and a fill for positions |
| Fill (spot) | same; coin `@<index>` or `BASE/QUOTE` mapped in the config | `:base`, `:quote`, `:fee` (in the fee token) |
| Funding | `userFunding`, websocket funding | `funding:<ms>:<coin>` |
| Ledger update | `userNonFundingLedgerUpdates` | `lu:<ms>:<32 hex of hash>:<type>` (and `:fee`) |
| Staking reward | `delegatorRewards` | `stakingReward:<ms>:<source>` |
| Builder income | daily builder fills file (rows given by the caller) | `bf:<tid>` |
| Balances | `clearinghouseState` (per dex), `spotClearinghouseState`, `delegatorSummary` | observed balances and perpetual positions |

Ledger update types handled: `deposit`, `withdraw`, `internalTransfer`,
`subAccountTransfer`, `accountClassTransfer`, `spotTransfer`, `send` (between dexes and
spot), `vaultCreate`, `vaultDeposit`, `vaultWithdraw`, `vaultDistribution`,
`rewardsClaim`, `cStakingTransfer`, `spotGenesis`, `gossipPriorityGasAuction`. Others are
decoded as `Other` and book nothing. Field names were checked against mainnet answers in
October 2026; the tests run on synthetic fixtures with the same shapes. More in
[docs/hyperliquid.md](docs/hyperliquid.md).

## Stable types

Every persisted value has a `Stable.V1` with a pinned `bin_digest` (`test/test_stable.ml`);
decoding validates again. A change needs a `V2` next to `V1`.

## Known gaps

- `rewardsClaim` is decoded from its documented `amount` field; no mainnet sample was at
  hand. Where claims are credited is configurable (`Config.claim_venue`, default `perp`).
- `liquidation`, `borrowLend` and `activateDexAbstraction` updates book nothing
  (liquidation losses arrive as fills; lending is not modelled), so lending balances show
  as reconciliation breaks.
- Ledger update ids use time, a 128-bit hash prefix and the type; two updates of the same
  type in one transaction in the same millisecond would collide (not seen).
- A vault withdrawal books the net amount withdrawn; the vault's gain or loss stays in the
  `vaults` account until valued by the caller.
- Spot USDC is reported with 8 digits and booked with 6: reconcile with a tolerance of one
  minor unit.
- Reconciliation has no "sync in progress" status; the caller decides when a report is
  current enough to compare.
- Opening balances and transfers in create no cost-basis lots; add them with
  `Positions.add_lot` at a known price.
- The Hyperliquid info decoders here could move into hl-protocol.

## Docs

- API: `dune build @doc`, entry points `Chain_books` and `Chain_books_hyperliquid`.
- [docs/hyperliquid.md](docs/hyperliquid.md): what the info endpoints return and how the
  adapter reads it.
- [AGENTS.md](AGENTS.md): layout, commands and conventions for working on this
  repository.
- [CHANGES.md](CHANGES.md).
