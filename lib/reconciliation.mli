(** Booked balances against what the chain reports, per location and asset, and tracked
    positions against reported positions. Reconciliation never books anything: a break is
    reported for a person (or a later rule) to explain.

    Balance statuses:
    - [Matched]: equal, or within the tolerance (one minor unit per rounded amount is
      the usual choice when the venue reports more digits than the asset books);
    - [Difference]: both sides known and apart by more than the tolerance;
    - [Untracked]: reported (non-zero) at a location the books have never booked to,
      typically before its opening balance is derived;
    - [Not_reported]: booked (non-zero) but missing from the report. *)

open! Core

module Status : sig
  type t =
    | Matched
    | Difference of Money.Amount.t (** observed minus booked *)
    | Untracked
    | Not_reported
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

module Row : sig
  type t =
    { location : Location.t
    ; asset : Money.Currency.t
    ; booked : Money.Amount.t option (** [None] when the location was never booked *)
    ; observed : Money.Amount.t option (** [None] when the report does not list it *)
    ; status : Status.t
    }
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

module Position_row : sig
  type t =
    { address : Address.t
    ; instrument : Instrument.t
    ; tracked : Exact.t
    ; observed : Exact.t
    ; matched : bool
    }
  [@@deriving sexp, compare, equal]
end

(** Rows for every location and asset that is booked in [balances] or listed in the
    report, sorted by location and asset. [tolerance asset] is the largest difference
    still counted as matched (default zero). Zero on both sides is left out. *)
val balances
  :  Chart.t
  -> ?tolerance:(Money.Currency.t -> Money.Amount.t)
  -> Ledger.Balances.t
  -> Observed.t
  -> Row.t list

(** Rows for every position open in [positions] or listed in the report; a position
    missing on one side counts as size zero there. Sorted by address and instrument. *)
val positions : Positions.t -> Observed.t -> Position_row.t list

(** The rows that are not [Matched]. *)
val breaks : Row.t list -> Row.t list
