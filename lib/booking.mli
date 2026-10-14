(** Activities to ledger entries.

    One activity is one single-currency {!Ledger.Entry.t} under the idempotency key
    [chain:<binding>:<event id>], so reading the same history twice books it once (the
    journal answers the second append as a duplicate). An asset arriving at a location
    debits its custody account and credits the counter account; an asset leaving does the
    opposite. Between two locations of the binding the counter account is the other
    location's custody account, so an internal transfer moves the balance in one entry.

    The entry's value date ([effective_at]) is when the activity happened; [recorded_at]
    is the ledger time the caller passes. The code follows the kind ([Deposit],
    [Withdrawal], [Fee] for fees, [Interest] for funding and staking rewards,
    [Transfer_intraledger] otherwise); the kind is [Transfer "chain_<kind>"]; the
    reference is the transaction hash, or the event id when there is none; the
    remittance information is the market, if any. *)

open! Core

(** Why an activity books nothing. *)
module Skip_reason : sig
  type t =
    | Zero_amount (** a ledger entry cannot move nothing *)
    | Asset_not_followed of Money.Currency.t
    (** the books follow a fixed set of assets and this is not one of them *)
  [@@deriving sexp, compare, equal]
end

module Outcome : sig
  type t =
    | Entry of Ledger.Entry.t
    | Skipped of
        { event_id : Event_id.t
        ; reason : Skip_reason.t
        }
  [@@deriving sexp_of, compare, equal]
end

(** [chain:<binding>:<event id>]. *)
val idempotency_key : Chart.t -> Event_id.t -> Ledger.Idempotency_key.t

(** The entry for one activity.

    [classify] may move an activity booked against a counterparty to another category (a
    service that keeps a hedge book can send that book's fees and profit to its own
    categories); it is not consulted for movements between two locations. [follow], when
    given, is the set of assets the books follow; anything else is skipped. *)
val entry
  :  Chart.t
  -> ?classify:(Activity.t -> Category.t option)
  -> ?follow:Money.Currency.Set.t
  -> at:Time_ns.t
  -> Activity.t
  -> Outcome.t Or_error.t
