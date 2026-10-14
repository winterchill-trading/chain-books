(** Counterparty categories: the accounts on the other side of a custody movement that
    leaves or enters the binding, and how each is classified in the chart of accounts.

    {v
    category           kind     meaning
    bridge             Equity   deposits from and withdrawals to other chains
    external           Equity   transfers with addresses outside the binding
    spot_clearing      Asset    the other leg of spot trades, per asset (a trading account)
    perp_pnl           Income   realised profit and loss of perpetual positions
    trading_fees       Expense  exchange fees paid (negative when rebated)
    funding            Income   perpetual funding received (negative when paid)
    builder_fees       Income   builder-fee income (negative for builder fees paid)
    referral_rewards   Income   referral rewards accrued
    vault_commission   Income   commission earned as a vault leader
    vaults             Asset    equity placed in vaults run by others
    staking_rewards    Income   staking rewards
    opening_balance    Equity   balances found when the books start (see Opening)
    other              Asset    suspense: anything not classified
    v}

    Equity and the two external categories are credit-normal, so net deposits read as a
    positive contributed balance. Every counterparty account may go negative. [Custom]
    adds a service-specific category (a hedge book, say) with its own kind. *)

open! Core

type t =
  | Bridge
  | External
  | Spot_clearing
  | Perp_pnl
  | Trading_fees
  | Funding
  | Builder_fees
  | Referral_rewards
  | Vault_commission
  | Vaults
  | Staking_rewards
  | Opening_balance
  | Other
  | Custom of
      { name : string (** 1 to 24 characters from [a-z 0-9 _] *)
      ; kind : Ledger.Account_kind.t
      }
[@@deriving sexp, compare, equal, hash]

include Comparable.S with type t := t

(** Every category except [Custom]. *)
val all_builtin : t list

(** A checked [Custom] category. *)
val custom : name:string -> kind:Ledger.Account_kind.t -> t Or_error.t

(** The snake-case name, e.g. [trading_fees]; a custom category's own name. *)
val to_string : t -> string

(** The account kind in the chart (see the table above). *)
val account_kind : t -> Ledger.Account_kind.t

(** [Clearing] for [spot_clearing], [Fee_income] for builder fees, [General] otherwise. *)
val purpose : t -> Ledger.Account.Purpose.t

(** Every built-in category and one custom category. *)
val quickcheck_generator : t Quickcheck.Generator.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
