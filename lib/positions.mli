(** Positions and cost basis per account and instrument, from fills.

    A position is a list of lots (size and price), oldest first. A fill in the direction
    of the position (or on a flat one) opens a lot; a fill against it closes size from
    the lots and realises [closed * (fill price - lot price)] for a long, the opposite
    for a short, in the instrument's quote currency; a fill larger than the position
    closes it and opens the rest the other way. [Fifo] closes the oldest lots first;
    [Average_cost] keeps one lot at the average price. Perpetuals and spot pairs follow
    the same rules (for a spot pair the lots are the base asset bought, priced in the
    quote currency).

    Fees are not part of the cost basis: they are booked as fees ({!Activity.Kind.Trade_fee}),
    which is also how venues report closed profit and loss. Each fill's event id is
    applied once; a fill seen again changes nothing. The realised figures are exact
    rationals; {!Realisation.amount} rounds them to the currency once. *)

open! Core

(** Which lots a closing fill consumes. *)
module Method : sig
  type t =
    | Average_cost
    | Fifo
  [@@deriving sexp, compare, equal, enumerate]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** Size bought (or sold short) at one price. *)
module Lot : sig
  type t =
    { size : Exact.t (** signed, never zero *)
    ; price : Exact.t
    ; opened_at : Time_ns.Alternate_sexp.t
    ; opened_by : Event_id.t
    }
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** The lots and realised profit of one account in one instrument. *)
module Position : sig
  type t =
    { address : Address.t
    ; instrument : Instrument.t
    ; lots : Lot.t list (** oldest first; all of one sign *)
    ; realised : Exact.t (** cumulative realised profit, in the quote currency *)
    }
  [@@deriving sexp, compare, equal]

  (** Signed size: the sum of the lots. *)
  val size : t -> Exact.t

  (** Signed cost basis: the sum of [size * price] over the lots. *)
  val cost : t -> Exact.t

  (** [cost / size], or [None] when flat. *)
  val average_price : t -> Exact.t option

  (** [size * mark - cost]: profit if the position closed at [mark]. *)
  val unrealised : t -> mark:Exact.t -> Exact.t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** What one fill realised. *)
module Realisation : sig
  type t =
    { event_id : Event_id.t
    ; address : Address.t
    ; instrument : Instrument.t
    ; closed : Exact.t (** size closed, positive; zero when the fill only opened *)
    ; realised : Exact.t
    ; reported : Money.Amount.t option (** what the venue reported, from the fill *)
    }
  [@@deriving sexp, compare, equal]

  (** [realised] rounded half-even to the quote currency. *)
  val amount : t -> Money.Amount.t

  (** [reported - amount], when the venue reported a figure. *)
  val difference_from_reported : t -> Money.Amount.t option
end

(** What {!apply} did with a fill. *)
module Applied : sig
  type t =
    | Applied of Realisation.t
    | Duplicate (** a fill with this event id was applied before *)
  [@@deriving sexp, compare, equal]
end

(** Every position, and the fills already applied. *)
type t [@@deriving sexp_of]

(** No positions, with the given cost-basis method. *)
val empty : Method.t -> t
(** The cost-basis method. *)
val method_ : t -> Method.t

(** Applies one fill. *)
val apply : t -> Fill.t -> t * Applied.t

(** Adds a lot without a fill: an asset received at a known cost (a transfer in, an
    opening balance priced at market). A lot against the position's direction is
    refused. *)
val add_lot
  :  t
  -> address:Address.t
  -> instrument:Instrument.t
  -> Lot.t
  -> t Or_error.t

(** The position of an account in an instrument, flat ones included once traded. *)
val find : t -> address:Address.t -> instrument:Instrument.t -> Position.t option

(** Every position, sorted by address and instrument. *)
val positions : t -> Position.t list

(** Positions with a non-zero size. *)
val open_positions : t -> Position.t list

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp]
  end
end
