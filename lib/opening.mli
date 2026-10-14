(** Opening balances derived from the first observed balance.

    Books start from a history window, not from the genesis of an account, so the first
    time a location and asset is observed the difference between what the chain reports
    and what the window booked up to that moment is the balance the location already had
    before the window. It is booked once, against the [opening_balance] category, under
    the key [chain:<binding>:opening:<address>:<venue>:<asset>] and dated at the start of
    the history window ([effective_at]), so that statements over the window start from it.

    Once derived, an opening is never derived again: later differences are breaks for
    {!Reconciliation}, not openings. The key makes a second booking a duplicate in the
    journal; a zero difference books nothing, so the caller (or {!Books}) also records
    that the location was opened. *)

open! Core

(** One derived opening and the figures behind it. *)
module Derived : sig
  type t =
    { location : Location.t
    ; observed : Money.Amount.t
    ; booked : Money.Amount.t (** posted at the location before the opening *)
    ; difference : Money.Amount.t (** [observed - booked]: the opening balance *)
    ; entry : Ledger.Entry.t option (** [None] when [difference] is zero *)
    }
  [@@deriving sexp_of, compare, equal]
end

(** [chain:<binding>:opening:<address>:<venue>:<asset>]. *)
val idempotency_key
  :  Chart.t
  -> Location.t
  -> Money.Currency.t
  -> Ledger.Idempotency_key.t Or_error.t

(** The opening for one observed balance, against the booked balance in [balances].
    [effective_at] is the start of the history window; [at] the ledger time. *)
val derive
  :  Chart.t
  -> Ledger.Balances.t
  -> Observed.Balance.t
  -> effective_at:Time_ns.t
  -> at:Time_ns.t
  -> Derived.t Or_error.t
