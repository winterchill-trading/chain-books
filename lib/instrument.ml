open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Spot of
          { base : Money.Currency.Stable.V1.t
          ; quote : Money.Currency.Stable.V1.t
          }
      | Perp of
          { coin : string
          ; settle : Money.Currency.Stable.V1.t
          }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

module T = struct
  type t = Stable.V1.t =
    | Spot of
        { base : Money.Currency.t
        ; quote : Money.Currency.t
        }
    | Perp of
        { coin : string
        ; settle : Money.Currency.t
        }
  [@@deriving sexp, compare, equal, hash]
end

include T

let spot ~base ~quote =
  if Money.Currency.equal base quote
  then Or_error.error_s [%message "spot pair with the same currency on both sides"]
  else Ok (Spot { base; quote })
;;

let perp ~coin ~settle =
  let ok c = Char.is_alphanum c || String.mem ":_-." c in
  if String.length coin >= 1 && String.length coin <= 32 && String.for_all coin ~f:ok
  then Ok (Perp { coin; settle })
  else Or_error.error_s [%message "invalid perpetual contract name" coin]
;;

let to_string = function
  | Spot { base; quote } ->
    sprintf "spot:%s/%s" (Money.Currency.to_string base) (Money.Currency.to_string quote)
  | Perp { coin; settle = _ } -> "perp:" ^ coin
;;

let quote_currency = function
  | Spot { quote; _ } -> quote
  | Perp { settle; _ } -> settle
;;

include Comparable.Make (T)
