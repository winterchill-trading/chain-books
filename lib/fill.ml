open! Core
module Time = Time_ns.Stable.Alternate_sexp.V1

module Side = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Buy
        | Sell
      [@@deriving bin_io, sexp, compare, equal, hash, enumerate]
    end
  end

  include Stable.V1

  let sign = function
    | Buy -> 1
    | Sell -> -1
  ;;
end

module Fields = struct
  type t =
    { event_id : Event_id.Stable.V1.t
    ; address : Address.Stable.V1.t
    ; instrument : Instrument.Stable.V1.t
    ; side : Side.Stable.V1.t
    ; size : Exact.Stable.V1.t
    ; price : Exact.Stable.V1.t
    ; occurred_at : Time.t
    ; reported_pnl : Money.Amount.Stable.V1.t option
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Fields.t =
  { event_id : Event_id.t
  ; address : Address.t
  ; instrument : Instrument.t
  ; side : Side.t
  ; size : Exact.t
  ; price : Exact.t
  ; occurred_at : Time_ns.Alternate_sexp.t
  ; reported_pnl : Money.Amount.t option
  }
[@@deriving compare, equal]

let validate (t : t) =
  let quote = Instrument.quote_currency t.instrument in
  if Q.sign t.size <= 0
  then Or_error.error_s [%message "fill size must be positive" ~event_id:(t.event_id : Event_id.t)]
  else if Q.sign t.price <= 0
  then
    Or_error.error_s [%message "fill price must be positive" ~event_id:(t.event_id : Event_id.t)]
  else (
    match t.reported_pnl with
    | Some pnl when not (Money.Currency.equal (Money.Amount.currency pnl) quote) ->
      Or_error.error_s
        [%message
          "reported pnl is not in the instrument's quote currency"
            ~event_id:(t.event_id : Event_id.t)
            ~pnl:(Money.Amount.to_string pnl)]
    | Some _ | None -> Ok t)
;;

let create ~event_id ~address ~instrument ~side ~size ~price ~occurred_at ?reported_pnl () =
  validate
    { event_id; address; instrument; side; size; price; occurred_at; reported_pnl }
;;

let signed_size t = if Side.sign t.side > 0 then t.size else Q.neg t.size
let notional t = Q.mul t.size t.price
let sexp_of_t = Fields.sexp_of_t
let t_of_sexp sexp = Or_error.ok_exn (validate (Fields.t_of_sexp sexp))

module Stable = struct
  module V1 = struct
    type nonrec t = t [@@deriving compare, equal]

    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Fields)
        (struct
          type nonrec t = t

          let to_binable = Fn.id
          let of_binable fields = Or_error.ok_exn (validate fields)
        end)
  end
end
