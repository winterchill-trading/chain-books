(** Hyperliquid records to normalised activities, fills and observed balances: an
    implementation of [Chain_books.Normalizer.S].

    {2 Event ids}

    {v
    fill:<tid>:pnl | :fee | :builder | :base | :quote    a fill's cash legs (the fill itself is fill:<tid>)
    funding:<ms>:<coin>                                  a funding payment
    lu:<ms>:<first 32 hex digits of the hash>:<type>     a ledger update (:fee for its fee)
    stakingReward:<ms>:<source>                          a staking reward
    bf:<tid>                                             builder-fee income
    v}

    Ids do not depend on which address of the binding reads the record, so a transfer
    between two bound addresses, which both histories contain, books once.

    {2 Venues}

    Perpetual coins with a [dex:] prefix ([xyz:GOLD]) are on the perpetuals dex of that
    name; spot coins ([@107], [PURR/USDC]) need an entry in {!Config.t.spot_pairs}.
    Records in tokens the configuration does not name are dropped.

    {2 Balances}

    The observed perpetuals balance is the account value minus unrealised profit (what
    the books hold); the staking balance is delegated plus undelegated plus pending
    withdrawals. *)

open! Core

(** The venue records the adapter normalises. *)
type event =
  | Fill of Hl_protocol.User_fill.Detailed.t
  | Funding of Funding.t
  | Ledger_update of Ledger_update.t
  | Staking_reward of Staking_reward.t
  | Builder_fill of Builder_fill.t

(** One read of an account's balances. *)
type report =
  { perp : (string option * Hl_protocol.Clearinghouse_state.t) list
  (** [None] for the default perpetuals dex, [Some dex] for another *)
  ; spot : Spot_state.t option
  ; staking : Delegator_summary.t option
  ; observed_at : Time_ns.t
  }

include
  Chain_books.Normalizer.S
  with type config = Config.t
   and type event := event
   and type report := report

(** The location of one of the configured account's venues. *)
val location : Config.t -> Chain_books.Venue.t -> Chain_books.Location.t

(** The venue of a perpetual coin: [Perp], or [Perp_dex] for [dex:COIN]. *)
val perp_venue : string -> Chain_books.Venue.t Or_error.t

(** The venue named by a [send]'s [sourceDex] or [destinationDex]: [""] is the default
    perpetuals dex, [spot] the spot account. *)
val venue_of_dex : string -> Chain_books.Venue.t Or_error.t

(** Milliseconds since the epoch. *)
val time_of_ms : int -> Time_ns.t
