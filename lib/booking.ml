open! Core

module Skip_reason = struct
  type t =
    | Zero_amount
    | Asset_not_followed of Money.Currency.t
  [@@deriving sexp, compare, equal]
end

module Outcome = struct
  type t =
    | Entry of Ledger.Entry.t
    | Skipped of
        { event_id : Event_id.t
        ; reason : Skip_reason.t
        }
  [@@deriving sexp_of, compare, equal]
end

let idempotency_key chart event_id =
  Ledger.Idempotency_key.of_string
    (sprintf
       "chain:%s:%s"
       (Binding_id.to_string (Chart.binding chart))
       (Event_id.to_string event_id))
;;

let code : Activity.Kind.t -> Ledger.Entry.Code.t = function
  | Deposit -> Deposit
  | Withdrawal -> Withdrawal
  | Trade_fee | Builder_fee -> Fee
  | Funding | Staking_reward -> Interest
  | Transfer_in
  | Transfer_out
  | Internal
  | Trade
  | Referral_reward
  | Vault_commission
  | Vault_deposit
  | Vault_withdrawal
  | Staking
  | Other -> Transfer_intraledger
;;

let entry chart ?(classify = fun _ -> None) ?follow ~at (activity : Activity.t) =
  let asset = Activity.asset activity in
  let skip reason = Ok (Outcome.Skipped { event_id = activity.event_id; reason }) in
  match follow with
  | Some follow when not (Set.mem follow asset) -> skip (Asset_not_followed asset)
  | _ when Money.Amount.is_zero activity.amount -> skip Zero_amount
  | _ ->
    let custody = Chart.custody chart activity.location in
    let counter = Chart.counter_account chart ?category:(classify activity) activity in
    let amount = Money.Amount.abs activity.amount in
    let postings =
      if Money.Amount.is_positive activity.amount
      then [ Ledger.Posting.debit custody amount; Ledger.Posting.credit counter amount ]
      else [ Ledger.Posting.debit counter amount; Ledger.Posting.credit custody amount ]
    in
    let%map.Or_error entry =
      Ledger.Entry.create
        ~idempotency_key:(idempotency_key chart activity.event_id)
        ~kind:(Transfer ("chain_" ^ Activity.Kind.to_string activity.kind))
        ~code:(code activity.kind)
        ~reference:
          (Option.value
             activity.reference
             ~default:(Event_id.to_string activity.event_id))
        ~remittance_info:(Option.value activity.market ~default:"")
        ~effective_at:activity.occurred_at
        ~recorded_at:at
        postings
    in
    Outcome.Entry entry
;;
