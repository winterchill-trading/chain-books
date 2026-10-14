(** Mark-to-market: every custody balance of a binding and every open position valued in
    one reporting currency through a {!Price_source}.

    A balance is worth [balance * rate]; an open position adds its unrealised profit,
    [size * mark - cost] in the instrument's quote currency, converted the same way.
    Lines are rounded half-even for display; the total is summed exactly and rounded
    once. A rate or mark older than [max_age] is stale: the line is left unvalued and
    named in [missing], like one with no price at all, so a report never mixes fresh and
    stale prices silently. Valuation books nothing. *)

open! Core

module Missing : sig
  type what =
    | Rate of Money.Currency.t (** no usable rate from this asset to the currency *)
    | Mark of Instrument.t
  [@@deriving sexp, compare, equal]

  type t =
    { what : what
    ; stale_since : Time_ns.Alternate_sexp.t option
    (** when the price found was quoted, if one was found but is too old *)
    }
  [@@deriving sexp, compare, equal]
end

module Line : sig
  type t =
    { location : Location.t
    ; balance : Money.Amount.t
    ; value : Money.Amount.t option (** [None] when no usable rate *)
    }
  [@@deriving sexp, compare, equal]
end

module Position_line : sig
  type t =
    { address : Address.t
    ; instrument : Instrument.t
    ; size : Exact.t
    ; average_price : Exact.t option
    ; mark : Exact.t option
    ; unrealised : Money.Amount.t option (** in the reporting currency *)
    }
  [@@deriving sexp, compare, equal]
end

type t =
  { currency : Money.Currency.t
  ; at : Time_ns.Alternate_sexp.t
  ; lines : Line.t list (** non-zero balances, sorted by location and asset *)
  ; positions : Position_line.t list
  ; total : Money.Amount.t (** valued lines and unrealised profit *)
  ; missing : Missing.t list (** without duplicates *)
  }
[@@deriving sexp, compare, equal]

(** Values the custody balances [chart] names in [balances], and the open [positions].
    [max_age] defaults to no limit. *)
val value
  :  Chart.t
  -> ?max_age:Time_ns.Span.t
  -> Ledger.Balances.t
  -> Positions.t
  -> Price_source.t
  -> currency:Money.Currency.t
  -> now:Time_ns.t
  -> t
