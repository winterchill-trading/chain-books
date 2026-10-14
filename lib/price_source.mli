(** The price hook for mark-to-market: exchange rates between assets and mark prices of
    instruments, with the time each was quoted. The library never fetches a price;
    services plug in their feed (a venue's mid prices, a reference rate table) through
    {!create}, and tests use {!of_table}. *)

open! Core

(** A mark price and when it was quoted. *)
module Mark : sig
  type t =
    { price : Exact.t (** in the instrument's quote currency per unit *)
    ; at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]
end

(** A source of rates and marks. *)
type t

(** [rate ~base ~quote] is the price of one [base] in [quote], if known. [mark] is an
    instrument's mark price, if known. *)
val create
  :  rate:(base:Money.Currency.t -> quote:Money.Currency.t -> Money.Rate.t option)
  -> mark:(Instrument.t -> Mark.t option)
  -> t

(** A fixed table. A rate is found as given or through its inverse; when several rates or
    marks are given for the same pair or instrument the latest wins. *)
val of_table
  :  ?rates:Money.Rate.t list
  -> ?marks:(Instrument.t * Mark.t) list
  -> unit
  -> t

(** The rate of [base] in [quote]; [None] when they are the same currency (a
    [Money.Rate.t] needs two), which callers value at one. *)
val rate : t -> base:Money.Currency.t -> quote:Money.Currency.t -> Money.Rate.t option

(** The mark price of an instrument. *)
val mark : t -> Instrument.t -> Mark.t option
