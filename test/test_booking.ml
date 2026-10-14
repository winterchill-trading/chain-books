open! Core
open Chain_books
open Helpers

let%expect_test "a deposit debits custody and credits the bridge" =
  let a = activity "lu:1:deposit" Deposit perp (usd "100.000000") ~reference:"0xabc" in
  (match Booking.entry chart ~at:t0 a |> Or_error.ok_exn with
   | Entry e -> print_s [%sexp (e : Ledger.Entry.t)]
   | Skipped _ -> print_endline "skipped");
  [%expect
    {|
    ((idempotency_key chain:org1:lu:1:deposit) (kind (Transfer chain_deposit))
     (code Deposit) (reference 0xabc) (remittance_info "")
     (effective_at "2026-07-01 00:00:00Z") (recorded_at "2026-07-01 00:00:00Z")
     (business_date 2026-07-01) (sca ())
     (postings
      (((account chain:org1:custody:0xa1:perp) (side Debit)
        (amount "100.000000 USDC"))
       ((account chain:org1:cp:bridge) (side Credit) (amount "100.000000 USDC")))))
    |}]
;;

let%expect_test "outflows credit custody; internal transfers move between locations" =
  let b =
    book
      Ledger.Balances.empty
      ~at:t0
      [ activity "d1" Deposit perp (usd "100")
      ; activity "fee1" Trade_fee perp (usd "-0.25") ~market:"BTC"
      ; activity "x1" Internal perp (usd "-40") ~counter:(Location spot)
      ; activity "w1" Withdrawal spot (usd "-10")
      ]
  in
  List.iter [ perp; spot ] ~f:(fun l -> print_amount (balance b l usdc));
  List.iter [ Category.Bridge; Trading_fees ] ~f:(fun c -> print_amount (cp_balance b c usdc));
  [%expect
    {|
    59.750000 USDC
    30.000000 USDC
    90.000000 USDC
    0.250000 USDC
    |}];
  print_s [%sexp (Ledger.Trial_balance.check (Ledger.Trial_balance.of_balances b) : unit Or_error.t)];
  [%expect {| (Ok ()) |}]
;;

let%expect_test "zero amounts and assets outside the followed set are skipped" =
  let follow = Money.Currency.Set.singleton usdc in
  List.iter
    [ activity "z" Funding perp (usd "0"); activity "h" Deposit spot (hy "1") ]
    ~f:(fun a ->
      match Booking.entry chart ~follow ~at:t0 a |> Or_error.ok_exn with
      | Entry _ -> print_endline "entry"
      | Skipped { event_id; reason } ->
        print_s [%message (event_id : Event_id.t) (reason : Booking.Skip_reason.t)]);
  [%expect
    {|
    ((event_id z) (reason Zero_amount))
    ((event_id h) (reason (Asset_not_followed HYPE)))
    |}]
;;

let%expect_test "classify moves a counterparty booking to another category" =
  let hedge = Category.custom ~name:"hedge_fee" ~kind:Expense |> Or_error.ok_exn in
  let classify (a : Activity.t) =
    if Option.equal String.equal a.client_key (Some "hedge:1") then Some hedge else None
  in
  let b =
    book
      Ledger.Balances.empty
      ~classify
      ~at:t0
      [ activity "f1" Trade_fee perp (usd "-1") ~client_key:"hedge:1"
      ; activity "f2" Trade_fee perp (usd "-2")
      ]
  in
  print_amount (cp_balance b hedge usdc);
  print_amount (cp_balance b Trading_fees usdc);
  [%expect
    {|
    1.000000 USDC
    2.000000 USDC
    |}]
;;
