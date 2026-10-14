(** One execution of an order: the input to position and cost-basis tracking
    ({!Positions}). The cash it moves (spot legs, realised profit or loss, fees) arrives
    separately as {!Activity} values, so a fill never books anything by itself. *)

open! Core

(** Bought or sold. *)
module Side : sig
  type t =
    | Buy
    | Sell
  [@@deriving sexp, compare, equal, hash, enumerate]

  (** [1] for [Buy], [-1] for [Sell]. *)
  val sign : t -> int

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** A fill; build one with {!create}, which checks it. *)
type t = private
  { event_id : Event_id.t
  ; address : Address.t
  ; instrument : Instrument.t
  ; side : Side.t
  ; size : Exact.t (** positive, in units of the base asset or contract *)
  ; price : Exact.t (** positive, in the instrument's quote currency per unit *)
  ; occurred_at : Time_ns.Alternate_sexp.t
  ; reported_pnl : Money.Amount.t option
  (** the realised profit or loss the venue reports for this fill, kept to cross-check
      {!Positions} *)
  }
[@@deriving sexp, compare, equal]

(** Fails unless [size] and [price] are positive and a [reported_pnl] is in the
    instrument's quote currency. *)
val create
  :  event_id:Event_id.t
  -> address:Address.t
  -> instrument:Instrument.t
  -> side:Side.t
  -> size:Exact.t
  -> price:Exact.t
  -> occurred_at:Time_ns.t
  -> ?reported_pnl:Money.Amount.t
  -> unit
  -> t Or_error.t

(** [size] signed by [side]: positive for a buy. *)
val signed_size : t -> Exact.t

(** [size * price], exact. *)
val notional : t -> Q.t

module Stable : sig
  module V1 : sig
    (** Decoding validates again, like {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
