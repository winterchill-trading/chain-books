(** What a trade is in: a spot pair (both legs are currencies, both are booked) or a
    perpetual contract (only the settlement currency is booked: realised profit and loss,
    fees and funding; the position itself is tracked by {!Positions}). *)

open! Core

type t =
  | Spot of
      { base : Money.Currency.t
      ; quote : Money.Currency.t
      }
  | Perp of
      { coin : string
      (** the contract's name, e.g. [BTC] or [xyz:GOLD] for a contract on another
          perpetuals exchange: 1 to 32 characters from [A-Z a-z 0-9 : _ - .] *)
      ; settle : Money.Currency.t (** the margin and settlement currency *)
      }
[@@deriving sexp, compare, equal, hash]

include Comparable.S with type t := t

(** A spot pair; fails when [base] equals [quote]. *)
val spot : base:Money.Currency.t -> quote:Money.Currency.t -> t Or_error.t

(** A perpetual contract with its name checked. *)
val perp : coin:string -> settle:Money.Currency.t -> t Or_error.t

(** [spot:HYPE/USDC], [perp:BTC]. *)
val to_string : t -> string

(** The currency prices and profits are in: [quote] or [settle]. *)
val quote_currency : t -> Money.Currency.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
