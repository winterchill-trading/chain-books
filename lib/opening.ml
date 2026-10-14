open! Core

module Derived = struct
  type t =
    { location : Location.t
    ; observed : Money.Amount.t
    ; booked : Money.Amount.t
    ; difference : Money.Amount.t
    ; entry : Ledger.Entry.t option
    }
  [@@deriving sexp_of, compare, equal]
end

let idempotency_key chart (location : Location.t) asset =
  Ledger.Idempotency_key.of_string_or_error
    (sprintf
       "chain:%s:opening:%s:%s:%s"
       (Binding_id.to_string (Chart.binding chart))
       (Address.to_string location.address)
       (Venue.to_string location.venue)
       (Money.Currency.to_string asset))
;;

let derive chart balances (observed : Observed.Balance.t) ~effective_at ~at =
  let asset = Money.Amount.currency observed.amount in
  let custody = Chart.custody chart observed.location in
  let booked = Ledger.Balances.posted balances custody asset in
  let difference = Money.Amount.sub_exn observed.amount booked in
  let%bind.Or_error key = idempotency_key chart observed.location asset in
  let%map.Or_error entry =
    if Money.Amount.is_zero difference
    then Ok None
    else (
      let opening = Chart.counterparty chart Opening_balance in
      let amount = Money.Amount.abs difference in
      let postings =
        if Money.Amount.is_positive difference
        then [ Ledger.Posting.debit custody amount; Ledger.Posting.credit opening amount ]
        else [ Ledger.Posting.debit opening amount; Ledger.Posting.credit custody amount ]
      in
      Ledger.Entry.create
        ~idempotency_key:key
        ~kind:(Transfer "chain_opening")
        ~code:Transfer_intraledger
        ~reference:(Location.to_string observed.location)
        ~effective_at
        ~recorded_at:at
        postings
      |> Or_error.map ~f:Option.some)
  in
  { Derived.location = observed.location; observed = observed.amount; booked; difference; entry }
;;
