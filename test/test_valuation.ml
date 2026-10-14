open! Core
open Chain_books
open Helpers

let rate base quote price ~at =
  Money.Rate.create ~base ~quote ~price:(Exact.of_string price) ~at ~source:"test"
  |> Or_error.ok_exn
;;

let books () =
  let b =
    book
      Ledger.Balances.empty
      ~at:t0
      [ activity "d1" Deposit perp (usd "1000")
      ; activity "d2" Deposit spot (hy "10")
      ; activity "d3" Deposit (loc Staking) (hy "2.5")
      ]
  in
  let ps, _ = Positions.apply (Positions.empty Fifo) (fill "f1" Sell "0.1" "60000") in
  b, ps
;;

let%expect_test "balances at rates, positions at marks, one rounding for the total" =
  let b, ps = books () in
  let prices =
    Price_source.of_table
      ~rates:[ rate hype usdc "41.123456789" ~at:(at_min 5) ]
      ~marks:[ btc_perp, { Price_source.Mark.price = Exact.of_string "61000"; at = at_min 5 } ]
      ()
  in
  let v = Valuation.value chart b ps prices ~currency:usdc ~now:(at_min 10) in
  print_s [%sexp (v : Valuation.t)];
  [%expect
    {|
    ((currency USDC) (at "2026-07-01 00:10:00Z")
     (lines
      (((location ((address 0xa1) (venue Perp))) (balance "1000.000000 USDC")
        (value ("1000.000000 USDC")))
       ((location ((address 0xa1) (venue Spot))) (balance "10.00000000 HYPE")
        (value ("411.234568 USDC")))
       ((location ((address 0xa1) (venue Staking))) (balance "2.50000000 HYPE")
        (value ("102.808642 USDC")))))
     (positions
      (((address 0xa1) (instrument (Perp (coin BTC) (settle USDC))) (size -0.1)
        (average_price (60000)) (mark (61000)) (unrealised ("-100.000000 USDC")))))
     (total "1414.043210 USDC") (missing ()))
    |}]
;;

let%expect_test "missing and stale prices leave lines unvalued and are listed" =
  let b, ps = books () in
  let prices =
    Price_source.of_table
      ~rates:[ rate usdc hype "0.025" ~at:t0 ]
      ()
  in
  let v =
    Valuation.value
      chart
      ~max_age:(Time_ns.Span.of_int_min 30)
      b
      ps
      prices
      ~currency:usdc
      ~now:(at_min 60)
  in
  print_s [%sexp (v.total : Money.Amount.t), (v.missing : Valuation.Missing.t list)];
  [%expect
    {|
    ("1000.000000 USDC"
     (((what (Rate HYPE)) (stale_since ("2026-07-01 00:00:00Z")))
      ((what (Mark (Perp (coin BTC) (settle USDC)))) (stale_since ()))))
    |}];
  (* Within the age limit, the inverse of the USDC/HYPE rate values HYPE at 40. *)
  let v = Valuation.value chart b ps prices ~currency:usdc ~now:(at_min 10) in
  print_s [%sexp (v.total : Money.Amount.t)];
  [%expect {| "1500.000000 USDC" |}]
;;
