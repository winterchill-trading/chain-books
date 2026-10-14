(** The books of one binding as one immutable value: ledger balances, positions, and the
    locations whose opening balance is derived. A convenience over {!Booking},
    {!Opening}, {!Positions}, {!Reconciliation} and {!Valuation} for callers that keep
    the state in memory or snapshot it; a service with its own journal can call those
    modules directly and append the entries itself.

    Every function returns a new value; the ledger records it appended are kept in order
    ({!records}) so a caller can write them to a journal. Ingesting the same history
    again is safe: an entry already booked under its key is reported as a duplicate, a
    fill already applied is skipped. An event id reused for a different movement is an
    error, and nothing from that call is kept. *)

open! Core

type t

(** Empty books. [method_] (default [Fifo]) is the cost-basis method; [follow], when
    given, restricts booking to those assets; [classify] is passed to {!Booking.entry}. *)
val create
  :  ?method_:Positions.Method.t
  -> ?follow:Money.Currency.t list
  -> ?classify:(Activity.t -> Category.t option)
  -> Chart.t
  -> t

val chart : t -> Chart.t
val balances : t -> Ledger.Balances.t
val positions : t -> Positions.t

(** Every ledger record appended since {!create}, oldest first. *)
val records : t -> Ledger.Record.t list

(** The custody balance of one asset at one location. *)
val balance : t -> Location.t -> Money.Currency.t -> Money.Amount.t

(** What one {!ingest} did. *)
module Report : sig
  type t =
    { booked : Event_id.t list
    ; duplicates : Event_id.t list (** activities booked before, under the same key *)
    ; skipped : (Event_id.t * Booking.Skip_reason.t) list
    ; realised : Positions.Realisation.t list (** one per fill applied *)
    ; repeated_fills : Event_id.t list
    }
  [@@deriving sexp_of]
end

(** Books the activities and applies the fills, in order, opening any account they need.
    [at] is the ledger time (moved forward to the last record's time if it is earlier). *)
val ingest : t -> Normalized.t list -> at:Time_ns.t -> (t * Report.t) Or_error.t

(** Derives and books the opening balance of every location and asset in the report not
    opened before (see {!Opening}), dated [history_start]. Returns only the openings
    derived by this call. *)
val open_balances
  :  t
  -> Observed.t
  -> history_start:Time_ns.t
  -> at:Time_ns.t
  -> (t * Opening.Derived.t list) Or_error.t

(** Whether the opening of a location and asset has been derived. *)
val is_opened : t -> Location.t -> Money.Currency.t -> bool

(** {!Reconciliation.balances} over these books. *)
val reconcile
  :  ?tolerance:(Money.Currency.t -> Money.Amount.t)
  -> t
  -> Observed.t
  -> Reconciliation.Row.t list

(** {!Reconciliation.positions} over these books. *)
val reconcile_positions : t -> Observed.t -> Reconciliation.Position_row.t list

(** {!Valuation.value} over these books. *)
val value
  :  ?max_age:Time_ns.Span.t
  -> t
  -> Price_source.t
  -> currency:Money.Currency.t
  -> now:Time_ns.t
  -> Valuation.t
