(** One normalised movement of one asset at one custody location: the unit the books are
    built from. Adapters turn venue records into activities (see {!Normalizer}); a
    venue record that moves two assets (a spot fill) or pays a fee becomes several
    activities with distinct {!Event_id}s.

    [amount] is signed from the location's side: positive when the asset arrives,
    negative when it leaves. [counter] says where it comes from or goes to: another
    location of the same binding (a transfer between venues or sub-accounts, booked on
    both locations by this one activity) or a counterparty {!Category}. An adapter must
    emit one activity per movement between two locations of the binding, not one per
    side. *)

open! Core

(** What happened. The text forms are the snake-case names ([transfer_in],
    [staking_reward], ...). *)
module Kind : sig
  type t =
    | Deposit (** arrived from another chain *)
    | Withdrawal (** left for another chain *)
    | Transfer_in (** received from an address outside the binding *)
    | Transfer_out (** sent to an address outside the binding *)
    | Internal (** between two locations of the binding *)
    | Trade (** a spot leg, or a perpetual's realised profit or loss *)
    | Trade_fee
    | Funding
    | Builder_fee (** builder-fee income earned, or a builder fee paid on a fill *)
    | Referral_reward
    | Vault_commission
    | Vault_deposit
    | Vault_withdrawal
    | Staking_reward
    | Staking (** delegation and undelegation: between spot and staking *)
    | Other
  [@@deriving sexp, compare, equal, hash, enumerate]

  val to_string : t -> string
  val of_string_or_error : string -> t Or_error.t
  val quickcheck_generator : t Quickcheck.Generator.t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** The other side of the movement. *)
module Counter : sig
  type t =
    | Location of Location.t
    | Counterparty of Category.t
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t = private
  { event_id : Event_id.t
  ; kind : Kind.t
  ; location : Location.t
  ; amount : Money.Amount.t (** signed from [location]'s side; its currency is the asset *)
  ; occurred_at : Time_ns.Alternate_sexp.t
  ; counter : Counter.t
  ; market : string option (** the market of a trade, fee or funding payment *)
  ; reference : string option (** the transaction hash, when the chain has one *)
  ; client_key : string option
  (** the writer's idempotency key, when the movement was submitted by this
      organisation's own write (see {!Chain_write}) *)
  }
[@@deriving sexp, compare, equal]

(** The counterparty category an activity of this kind books against when the adapter
    names none: [Deposit] and [Withdrawal] go to [Bridge], transfers to [External], a
    [Trade] to [Perp_pnl] on a perpetuals venue and [Spot_clearing] elsewhere, fees to
    [Trading_fees], and so on. [None] for [Internal] and [Staking], which need a
    location. *)
val default_counterparty : Kind.t -> venue:Venue.t -> Category.t option

(** Fails when [counter] is omitted for a kind without a default, or names [location]
    itself. *)
val create
  :  event_id:Event_id.t
  -> kind:Kind.t
  -> location:Location.t
  -> amount:Money.Amount.t
  -> occurred_at:Time_ns.t
  -> ?counter:Counter.t
  -> ?market:string
  -> ?reference:string
  -> ?client_key:string
  -> unit
  -> t Or_error.t

(** The asset moved: the currency of [amount]. *)
val asset : t -> Money.Currency.t

module Stable : sig
  module V1 : sig
    (** Decoding validates again, like {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
