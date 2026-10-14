open! Core
open Chain_books

let usdc = Money.Currency.usdc
let hype = Assets.hype
let amount currency s = Money.Amount.of_decimal_string currency s |> Or_error.ok_exn
let usd s = amount usdc s
let hy s = amount hype s
let t0 = Time_ns.of_string_with_utc_offset "2026-07-01 00:00:00Z"
let at_min n = Time_ns.add t0 (Time_ns.Span.of_int_min n)
let binding = Binding_id.of_string "org1"
let chart = Chart.create binding
let address = Address.of_string "0xa1"
let sub = Address.of_string "0xb2"
let loc ?(address = address) venue = { Location.address; venue }
let perp = loc Perp
let spot = loc Spot
let eid = Event_id.of_string

let activity ?counter ?market ?reference ?client_key ?(at = t0) id kind location amount =
  Activity.create
    ~event_id:(eid id)
    ~kind
    ~location
    ~amount
    ~occurred_at:at
    ?counter
    ?market
    ?reference
    ?client_key
    ()
  |> Or_error.ok_exn
;;

let print_amount a = print_endline (Money.Amount.to_string a)

(* Opens the accounts an activity list needs, then books every entry. *)
let book ?classify balances activities ~at =
  let opened =
    List.fold
      (Chart.missing_accounts chart ?classify balances activities)
      ~init:balances
      ~f:(fun b account ->
        Ledger.Balances.apply
          b
          { seq = Ledger.Balances.next_seq b; event = Account_opened account }
        |> Or_error.ok_exn)
  in
  List.fold activities ~init:opened ~f:(fun b a ->
    match Booking.entry chart ?classify ~at a |> Or_error.ok_exn with
    | Skipped _ -> b
    | Entry e ->
      Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event = Posted e }
      |> Or_error.ok_exn)
;;

let balance b location currency =
  Ledger.Balances.balance b (Chart.custody chart location) currency
;;

let cp_balance b category currency =
  Ledger.Balances.balance b (Chart.counterparty chart category) currency
;;

let btc_perp = Instrument.perp ~coin:"BTC" ~settle:usdc |> Or_error.ok_exn
let hype_spot = Instrument.spot ~base:hype ~quote:usdc |> Or_error.ok_exn

let fill
  ?(address = address)
  ?(instrument = btc_perp)
  ?reported_pnl
  ?(at = t0)
  id
  side
  size
  price
  =
  Fill.create
    ~event_id:(eid id)
    ~address
    ~instrument
    ~side
    ~size:(Exact.of_string size)
    ~price:(Exact.of_string price)
    ~occurred_at:at
    ?reported_pnl
    ()
  |> Or_error.ok_exn
;;

let observed ?(at = t0) balances : Observed.t =
  { balances =
      List.map balances ~f:(fun (location, amount) ->
        { Observed.Balance.location; amount; observed_at = at })
  ; positions = []
  }
;;

let post b entry =
  Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event = Posted entry }
  |> Or_error.ok_exn
;;

let open_account b account =
  match Ledger.Balances.find_account b account.Ledger.Account.id with
  | Some _ -> b
  | None ->
    Ledger.Balances.apply
      b
      { seq = Ledger.Balances.next_seq b; event = Account_opened account }
    |> Or_error.ok_exn
;;
