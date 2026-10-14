open! Core
open Chain_books
open Helpers

let show positions =
  List.iter (Positions.positions positions) ~f:(fun p ->
    print_s
      [%message
        (Instrument.to_string p.instrument)
          ~size:(Positions.Position.size p : Exact.t)
          ~avg:(Positions.Position.average_price p : Exact.t option)
          ~realised:(p.realised : Exact.t)])
;;

let run method_ fills =
  List.fold fills ~init:(Positions.empty method_) ~f:(fun ps f ->
    let ps, applied = Positions.apply ps f in
    (match applied with
     | Duplicate -> print_endline "duplicate"
     | Applied r ->
       if Q.sign r.closed > 0
       then
         print_s
           [%message
             "closed"
               ~size:(r.closed : Exact.t)
               ~realised:(Money.Amount.to_string (Positions.Realisation.amount r))
               ~vs_reported:
                 (Option.map
                    (Positions.Realisation.difference_from_reported r)
                    ~f:Money.Amount.to_string
                  : string option)]);
    ps)
;;

let fills =
  [ fill "f1" Buy "1" "100"
  ; fill "f2" Buy "1" "120"
  ; fill "f3" Sell "1.5" "130" ~reported_pnl:(usd "35")
  ; fill "f3" Sell "1.5" "130"
  ; fill "f4" Sell "1" "90"
  ]
;;

let%expect_test "fifo closes the oldest lot first and flips through zero" =
  show (run Fifo fills);
  [%expect
    {|
    (closed (size 1.5) (realised "35.000000 USDC")
     (vs_reported ("0.000000 USDC")))
    duplicate
    (closed (size 0.5) (realised "-15.000000 USDC") (vs_reported ()))
    (perp:BTC (size -0.5) (avg (90)) (realised 20))
    |}]
;;

let%expect_test "average cost realises against the average price" =
  show (run Average_cost fills);
  [%expect
    {|
    (closed (size 1.5) (realised "30.000000 USDC")
     (vs_reported ("5.000000 USDC")))
    duplicate
    (closed (size 0.5) (realised "-10.000000 USDC") (vs_reported ()))
    (perp:BTC (size -0.5) (avg (90)) (realised 20))
    |}]
;;

let%expect_test "shorts realise when bought back lower; unrealised against a mark" =
  let ps = run Fifo [ fill "s1" Sell "2" "50"; fill "s2" Buy "0.5" "40" ] in
  show ps;
  let p = Option.value_exn (Positions.find ps ~address ~instrument:btc_perp) in
  print_s [%sexp (Positions.Position.unrealised p ~mark:(Exact.of_string "45") : Exact.t)];
  [%expect
    {|
    (closed (size 0.5) (realised "5.000000 USDC") (vs_reported ()))
    (perp:BTC (size -1.5) (avg (50)) (realised 5))
    7.5
    |}]
;;

let%expect_test "add_lot opens at a known cost and refuses the other direction" =
  let lot size price : Positions.Lot.t =
    { size = Exact.of_string size; price = Exact.of_string price; opened_at = t0; opened_by = eid "open" }
  in
  let ps = Positions.empty Fifo in
  let ps = Positions.add_lot ps ~address ~instrument:hype_spot (lot "10" "40") |> Or_error.ok_exn in
  print_s
    [%sexp
      (Positions.add_lot ps ~address ~instrument:hype_spot (lot "-1" "40") |> Or_error.map ~f:ignore
       : unit Or_error.t)];
  show ps;
  [%expect
    {|
    (Error ("lot against the position's direction" (instrument spot:HYPE/USDC)))
    (spot:HYPE/USDC (size 10) (avg (40)) (realised 0))
    |}]
;;

(* Random fills on one instrument, then one fill that flattens the position. *)
let gen_fills =
  let open Quickcheck.Generator.Let_syntax in
  let%bind n = Int.gen_incl 1 20 in
  let%map steps =
    List.gen_with_length
      n
      (Quickcheck.Generator.tuple3
         Bool.quickcheck_generator
         (Int.gen_incl 1 50)
         (Int.gen_incl 1 200))
  in
  let fills =
    List.mapi steps ~f:(fun i (buy, size, price) ->
      fill (sprintf "q%d" i) (if buy then Buy else Sell) (Int.to_string size) (Int.to_string price))
  in
  let net = List.fold fills ~init:Q.zero ~f:(fun acc f -> Q.add acc (Fill.signed_size f)) in
  if Q.equal net Q.zero
  then fills
  else
    fills
    @ [ fill
          "close"
          (if Q.sign net > 0 then Sell else Buy)
          (Exact.to_string (Q.abs net))
          "77"
      ]
;;

let total_realised method_ fills =
  let ps = List.fold fills ~init:(Positions.empty method_) ~f:(fun ps f -> fst (Positions.apply ps f)) in
  List.fold (Positions.positions ps) ~init:Q.zero ~f:(fun acc p -> Q.add acc p.realised), ps
;;

let%test_unit "a position that ends flat realises sells minus buys, with either method" =
  Quickcheck.test gen_fills ~trials:500 ~f:(fun fills ->
    let cash =
      List.fold fills ~init:Q.zero ~f:(fun acc f ->
        Q.sub acc (Q.mul (Fill.signed_size f) f.price))
    in
    List.iter Positions.Method.all ~f:(fun m ->
      let realised, ps = total_realised m fills in
      [%test_result: Exact.t] realised ~expect:cash;
      [%test_result: int] (List.length (Positions.open_positions ps)) ~expect:0))
;;

let%test_unit "size is the sum of signed fills; reapplying every fill changes nothing" =
  Quickcheck.test gen_fills ~trials:300 ~f:(fun fills ->
    let fills = List.drop_last_exn fills in
    List.iter Positions.Method.all ~f:(fun m ->
      let _, ps = total_realised m fills in
      let net = List.fold fills ~init:Q.zero ~f:(fun acc f -> Q.add acc (Fill.signed_size f)) in
      let size =
        Option.value_map (Positions.find ps ~address ~instrument:btc_perp) ~default:Q.zero
          ~f:Positions.Position.size
      in
      [%test_result: Exact.t] size ~expect:net;
      let again = List.fold fills ~init:ps ~f:(fun ps f -> fst (Positions.apply ps f)) in
      [%test_result: Positions.Position.t list]
        (Positions.positions again)
        ~expect:(Positions.positions ps)))
;;
