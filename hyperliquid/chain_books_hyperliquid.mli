(** The Hyperliquid adapter for [chain-books]: decoders for the info answers the wire
    types in [hl-protocol] do not cover (non-funding ledger updates, funding history,
    staking rewards and balances, spot balances) and {!Adapter}, an implementation of
    [Chain_books.Normalizer.S] over those and [hl-protocol]'s fills and account state.

    {[
      let config = Config.create address ~spot_pairs:[ "@107", ("HYPE", "USDC") ] in
      let items =
        Chain_books.Normalizer.normalize_all (module Adapter) config events
        |> Or_error.ok_exn
      in
      ...
    ]} *)

(** {1 Decoders} *)

module Wire = Wire
module Ledger_update = Ledger_update
module Funding = Funding
module Staking_reward = Staking_reward
module Builder_fill = Builder_fill
module Spot_state = Spot_state
module Delegator_summary = Delegator_summary

(** {1 Normalisation} *)

module Config = Config
module Adapter = Adapter
