(* Books for one on-chain account: a deposit, a perpetual round trip with its fee and
   profit, a move to spot, then the first balance report, its opening balance, the
   reconciliation and a valuation. *)

open! Core
open Chain_books

let usdc = Money.Currency.usdc
let at minute = Time_ns.add (Time_ns.of_string_with_utc_offset "2026-07-01 00:00:00Z") (Time_ns.Span.of_int_min minute)
let amount currency s = Money.Amount.of_decimal_string currency s |> Or_error.ok_exn
let address = Address.of_string "0x00000000000000000000000000000000000000a1"
let perp = { Location.address; venue = Perp }
let spot = { Location.address; venue = Spot }

let activity id kind location value ?counter minute =
  Activity.create
    ~event_id:(Event_id.of_string id)
    ~kind
    ~location
    ~amount:value
    ~occurred_at:(at minute)
    ?counter
    ()
  |> Or_error.ok_exn
;;

let fill id side size price ?reported_pnl minute =
  Fill.create
    ~event_id:(Event_id.of_string id)
    ~address
    ~instrument:(Instrument.perp ~coin:"BTC" ~settle:usdc |> Or_error.ok_exn)
    ~side
    ~size:(Exact.of_string size)
    ~price:(Exact.of_string price)
    ~occurred_at:(at minute)
    ?reported_pnl
    ()
  |> Or_error.ok_exn
;;

let history =
  [ Normalized.Activity (activity "dep-1" Deposit perp (amount usdc "1000") 1)
  ; Fill (fill "fill-1" Buy "0.02" "60000" 2)
  ; Activity (activity "fill-1:fee" Trade_fee perp (amount usdc "-0.54") 2)
  ; Fill (fill "fill-2" Sell "0.02" "61000" ~reported_pnl:(amount usdc "20") 3)
  ; Activity (activity "fill-2:pnl" Trade perp (amount usdc "20") 3)
  ; Activity (activity "fill-2:fee" Trade_fee perp (amount usdc "-0.55") 3)
  ; Activity (activity "move-1" Internal perp (amount usdc "-250") ~counter:(Location spot) 4)
  ]
;;

let () =
  let books = Books.create (Chart.create (Binding_id.of_string "treasury")) in
  let books, report = Books.ingest books history ~at:(at 10) |> Or_error.ok_exn in
  printf "booked %d entries\n" (List.length report.booked);
  List.iter report.realised ~f:(fun r ->
    if Q.sign r.closed > 0
    then
      printf
        "%s realised %s\n"
        (Event_id.to_string r.event_id)
        (Money.Amount.to_string (Positions.Realisation.amount r)));
  List.iter [ perp; spot ] ~f:(fun l ->
    printf "%s %s\n" (Location.to_string l) (Money.Amount.to_string (Books.balance books l usdc)));
  (* The first report shows 120 USDC more on spot than the window booked: it was there
     before the window started. *)
  let report_at = at 30 in
  let observed : Observed.t =
    { balances =
        [ { location = perp; amount = amount usdc "768.91"; observed_at = report_at }
        ; { location = spot; amount = amount usdc "370"; observed_at = report_at }
        ]
    ; positions = []
    }
  in
  let books, openings =
    Books.open_balances books observed ~history_start:(at 0) ~at:report_at |> Or_error.ok_exn
  in
  List.iter openings ~f:(fun o ->
    printf
      "opening %s %s\n"
      (Location.to_string o.location)
      (Money.Amount.to_string o.difference));
  printf "breaks: %d\n" (List.length (Reconciliation.breaks (Books.reconcile books observed)));
  let valuation =
    Books.value books (Price_source.of_table ()) ~currency:usdc ~now:report_at
  in
  printf "value %s\n" (Money.Amount.to_string valuation.total)
;;
