(** What the chain reports: balances per location and asset, and open positions, as read
    at [observed_at]. The input to {!Opening} and {!Reconciliation}. *)

open! Core

module Balance : sig
  type t =
    { location : Location.t
    ; amount : Money.Amount.t
    (** the asset's balance at the location. For a perpetuals margin account this is the
        account value minus unrealised profit and loss, which is what the books hold
        (open positions are not booked until they realise). *)
    ; observed_at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

module Position : sig
  type t =
    { address : Address.t
    ; instrument : Instrument.t
    ; size : Exact.t (** signed: negative for a short *)
    ; entry_price : Exact.t option
    ; observed_at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** One report: every balance and position the venue returned. A location missing from
    [balances] is reported as zero by the venue only if it lists it; {!Reconciliation}
    tells "not reported" apart from zero. *)
type t =
  { balances : Balance.t list
  ; positions : Position.t list
  }
[@@deriving sexp, compare, equal]

val empty : t

(** Both lists concatenated, e.g. the perpetuals and the spot report of one account. *)
val merge : t list -> t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
