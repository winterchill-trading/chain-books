(** The module type every venue adapter implements: from the venue's own records to
    {!Normalized} values and {!Observed} reports. Adapters are pure; fetching the records
    is the caller's job.

    Rules an adapter follows, so that the books stay idempotent and balanced:
    - event ids are deterministic functions of the venue's ids (a trade id, a
      transaction hash and the update's type, a timestamp and a market), never of the
      time of reading or of a position in a page;
    - every movement between two locations of the binding is one activity with a
      [Location] counter, not one per side;
    - decimal amounts are rounded to the asset's minor unit once, half-even, here and
      nowhere else (see {!round});
    - records for assets the books do not follow are dropped, not guessed. *)

open! Core

module type S = sig
  (** A short name for the venue, e.g. [hyperliquid]. *)
  val source : string

  (** What the adapter needs besides the record: the account being read, asset tables. *)
  type config

  (** One venue record (a fill, a funding payment, a ledger update, ...). *)
  type event

  (** One balance report (an account summary). *)
  type report

  (** The normalised values for one record, possibly none. *)
  val normalize : config -> event -> Normalized.t list Or_error.t

  (** The balances and positions in one report. *)
  val observe : config -> report -> Observed.t Or_error.t
end

(** [round currency q] is [q] major units of [currency], rounded half-even to a minor
    unit: the one rounding an adapter applies to a venue decimal. *)
val round : Money.Currency.t -> Q.t -> Money.Amount.t

(** [normalize_all (module N) config events] concatenates {!S.normalize} over [events],
    when some records fail, the error lists every failure, tagged with the source. *)
val normalize_all
  :  (module S with type config = 'c and type event = 'e)
  -> 'c
  -> 'e list
  -> Normalized.t list Or_error.t
