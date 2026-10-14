open! Core
open Chain_books

type event =
  | Fill of Hl_protocol.User_fill.Detailed.t
  | Funding of Funding.t
  | Ledger_update of Ledger_update.t
  | Staking_reward of Staking_reward.t
  | Builder_fill of Builder_fill.t

type report =
  { perp : (string option * Hl_protocol.Clearinghouse_state.t) list
  ; spot : Spot_state.t option
  ; staking : Delegator_summary.t option
  ; observed_at : Time_ns.t
  }

type config = Config.t

let source = "hyperliquid"
let time_of_ms ms = Time_ns.of_int_ns_since_epoch (ms * 1_000_000)
let address_of a = Address.of_string_or_error (Hl_protocol.Address.to_string a)

let location (config : Config.t) venue =
  { Location.address = Address.of_string (Hl_protocol.Address.to_string config.address)
  ; venue
  }
;;

let location_of a venue =
  let%map.Or_error address = address_of a in
  { Location.address; venue }
;;

let perp_venue coin =
  match String.lsplit2 coin ~on:':' with
  | None -> Ok Venue.Perp
  | Some (dex, _) -> Venue.perp_dex dex
;;

let venue_of_dex = function
  | "" -> Ok Venue.Perp
  | "spot" -> Ok Venue.Spot
  | dex -> Venue.perp_dex dex
;;

let is_spot_coin coin = String.is_prefix coin ~prefix:"@" || String.mem coin '/'
let usd_q u = Wire.q_of_fixed ~units:(Hl_protocol.Usd.to_units u) ~units_per_one:Hl_protocol.Usd.units_per_one

let size_q s =
  Wire.q_of_fixed ~units:(Hl_protocol.Size.to_units s) ~units_per_one:Hl_protocol.Size.units_per_one
;;

let price_q p =
  Wire.q_of_fixed
    ~units:(Hl_protocol.Price.to_units p)
    ~units_per_one:Hl_protocol.Price.units_per_one
;;

let zero_hash hash = String.for_all (String.chop_prefix_if_exists hash ~prefix:"0x") ~f:(Char.equal '0')
let reference_of_hash hash = if zero_hash hash then None else Some hash

(* One activity with its amount rounded once, here. *)
let activity ~id ~kind ~location ~currency ~amount ~at ?counter ?market ?reference ?client_key () =
  let%bind.Or_error event_id = Event_id.of_string_or_error id in
  let%map.Or_error a =
    Activity.create
      ~event_id
      ~kind
      ~location
      ~amount:(Normalizer.round currency amount)
      ~occurred_at:at
      ?counter
      ?market
      ?reference
      ?client_key
      ()
  in
  Normalized.Activity a
;;

let all results = Or_error.combine_errors results
let nonzero q = not (Q.equal q Q.zero)

(* {1 Fills} *)

let fill_activities (config : Config.t) (d : Hl_protocol.User_fill.Detailed.t) =
  let f = d.fill in
  let coin = Hl_protocol.Coin.to_string f.coin in
  let at = time_of_ms f.time in
  let reference = reference_of_hash f.hash in
  let client_key = Option.map f.cloid ~f:Hl_protocol.Cloid.to_string in
  let id leg = sprintf "fill:%d%s" f.tid leg in
  let size = size_q f.sz in
  let price = price_q f.px in
  let fee = usd_q f.fee in
  let builder = Option.value_map d.builder_fee ~default:Q.zero ~f:usd_q in
  let%bind.Or_error fill_address = address_of config.address in
  let fee_legs ~location ~fee_currency =
    [ (if nonzero (Q.sub fee builder)
       then
         Some
           (activity
              ~id:(id ":fee")
              ~kind:Trade_fee
              ~location
              ~currency:fee_currency
              ~amount:(Q.neg (Q.sub fee builder))
              ~at
              ~market:coin
              ?reference
              ?client_key
              ())
       else None)
    ; (if nonzero builder
       then
         Some
           (activity
              ~id:(id ":builder")
              ~kind:Builder_fee
              ~location
              ~currency:fee_currency
              ~amount:(Q.neg builder)
              ~at
              ~market:coin
              ?reference
              ?client_key
              ())
       else None)
    ]
    |> List.filter_opt
  in
  let%bind.Or_error event_id = Event_id.of_string_or_error (id "") in
  if is_spot_coin coin
  then (
    let pair =
      let%bind.Option base, quote = Map.find config.spot_pairs coin in
      let%bind.Option base = Config.token config base in
      let%map.Option quote = Config.token config quote in
      base, quote
    in
    match pair with
    | None -> Ok []
    | Some (base, quote) ->
      let location = location config Spot in
      let sign = Q.of_int (Fill.Side.sign (if Hl_protocol.Side.is_buy f.side then Buy else Sell)) in
      let fee_currency =
        Option.bind f.fee_token ~f:(Config.token config) |> Option.value ~default:quote
      in
      let%bind.Or_error instrument = Instrument.spot ~base ~quote in
      let%bind.Or_error fill =
        Fill.create
          ~event_id
          ~address:fill_address
          ~instrument
          ~side:(if Hl_protocol.Side.is_buy f.side then Buy else Sell)
          ~size
          ~price
          ~occurred_at:at
          ()
      in
      all
        ([ activity
             ~id:(id ":base")
             ~kind:Trade
             ~location
             ~currency:base
             ~amount:(Q.mul sign size)
             ~at
             ~market:coin
             ?reference
             ?client_key
             ()
         ; activity
             ~id:(id ":quote")
             ~kind:Trade
             ~location
             ~currency:quote
             ~amount:(Q.neg (Q.mul sign (Q.mul size price)))
             ~at
             ~market:coin
             ?reference
             ?client_key
             ()
         ]
         @ fee_legs ~location ~fee_currency)
      |> Or_error.map ~f:(fun legs -> Normalized.Fill fill :: legs))
  else (
    let%bind.Or_error venue = perp_venue coin in
    let settle = Config.collateral config venue in
    let location = location config venue in
    let pnl = usd_q f.closed_pnl in
    let fee_currency =
      Option.bind f.fee_token ~f:(Config.token config) |> Option.value ~default:settle
    in
    let%bind.Or_error instrument = Instrument.perp ~coin ~settle in
    let%bind.Or_error fill =
      Fill.create
        ~event_id
        ~address:fill_address
        ~instrument
        ~side:(if Hl_protocol.Side.is_buy f.side then Buy else Sell)
        ~size
        ~price
        ~occurred_at:at
        ~reported_pnl:(Normalizer.round settle pnl)
        ()
    in
    all
      ((if nonzero pnl
        then
          [ activity
              ~id:(id ":pnl")
              ~kind:Trade
              ~location
              ~currency:settle
              ~amount:pnl
              ~at
              ~market:coin
              ?reference
              ?client_key
              ()
          ]
        else [])
       @ fee_legs ~location ~fee_currency)
    |> Or_error.map ~f:(fun legs -> Normalized.Fill fill :: legs))
;;

(* {1 Ledger updates} *)

(* A movement of [amount] of [currency] from [user] at [src] to [destination] at [dst],
   seen from the binding: internal when both ends are bound, a transfer in or out when
   one is, nothing when neither is. *)
let movement
  (config : Config.t)
  ~id
  ~at
  ?reference
  ?(internal_kind = Activity.Kind.Internal)
  ~user
  ~destination
  ~src
  ~dst
  ~currency
  amount
  =
  let%bind.Or_error from = location_of user src in
  let%bind.Or_error to_ = location_of destination dst in
  let make ~kind ~location ~amount ?counter () =
    activity ~id ~kind ~location ~currency ~amount ~at ?counter ?reference ()
    |> Or_error.map ~f:List.return
  in
  match Config.is_bound config user, Config.is_bound config destination with
  | true, true when Location.equal from to_ -> Ok []
  | true, true ->
    make ~kind:internal_kind ~location:from ~amount:(Q.neg amount) ~counter:(Location to_) ()
  | true, false -> make ~kind:Transfer_out ~location:from ~amount:(Q.neg amount) ()
  | false, true -> make ~kind:Transfer_in ~location:to_ ~amount ()
  | false, false -> Ok []
;;

let ledger_activities (config : Config.t) (u : Ledger_update.t) =
  let at = time_of_ms u.time in
  let reference = reference_of_hash u.hash in
  let hash = String.chop_prefix_if_exists u.hash ~prefix:"0x" in
  let base_id =
    sprintf
      "lu:%d:%s:%s"
      u.time
      (String.prefix hash 32)
      (Ledger_update.Delta.type_name u.delta)
  in
  let usdc = Money.Currency.usdc in
  let here venue = location config venue in
  let one ?(suffix = "") ~kind ~venue ~currency ?counter amount =
    if nonzero amount
    then
      activity
        ~id:(base_id ^ suffix)
        ~kind
        ~location:(here venue)
        ~currency
        ~amount
        ~at
        ?counter
        ?reference
        ()
      |> Or_error.map ~f:List.return
    else Ok []
  in
  let fee_from ~user ~venue ~currency fee =
    if Config.is_bound config user && nonzero fee
    then (
      let%bind.Or_error location = location_of user venue in
      activity
        ~id:(base_id ^ ":fee")
        ~kind:Trade_fee
        ~location
        ~currency
        ~amount:(Q.neg fee)
        ~at
        ?reference
        ()
      |> Or_error.map ~f:List.return)
    else Ok []
  in
  let concat parts = all parts |> Or_error.map ~f:List.concat in
  let with_token token f =
    match Config.token config token with
    | None -> Ok []
    | Some currency -> f currency
  in
  let mv = movement config ~id:base_id ~at ?reference in
  match u.delta with
  | Deposit { usdc = x } -> one ~kind:Deposit ~venue:Perp ~currency:usdc x
  | Withdraw { usdc = x; fee } ->
    concat
      [ one ~kind:Withdrawal ~venue:Perp ~currency:usdc (Q.neg x)
      ; one ~suffix:":fee" ~kind:Trade_fee ~venue:Perp ~currency:usdc (Q.neg fee)
      ]
  | Internal_transfer { usdc = x; user; destination; fee } ->
    concat
      [ mv ~user ~destination ~src:Perp ~dst:Perp ~currency:usdc x
      ; fee_from ~user ~venue:Perp ~currency:usdc fee
      ]
  | Sub_account_transfer { usdc = x; user; destination } ->
    mv ~user ~destination ~src:Perp ~dst:Perp ~currency:usdc x
  | Account_class_transfer { usdc = x; to_perp } ->
    let from, to_ = if to_perp then Venue.Spot, Venue.Perp else Perp, Spot in
    one ~kind:Internal ~venue:from ~currency:usdc ~counter:(Location (here to_)) (Q.neg x)
  | Spot_transfer { token; amount; user; destination; fee } ->
    with_token token (fun currency ->
      concat
        [ mv ~user ~destination ~src:Spot ~dst:Spot ~currency amount
        ; fee_from ~user ~venue:Spot ~currency:usdc fee
        ])
  | Send { token; amount; user; destination; source_dex; destination_dex; fee; fee_token } ->
    with_token token (fun currency ->
      let%bind.Or_error src = venue_of_dex source_dex in
      let%bind.Or_error dst = venue_of_dex destination_dex in
      let fee_part =
        with_token
          (if String.is_empty fee_token then "USDC" else fee_token)
          (fun fee_currency -> fee_from ~user ~venue:src ~currency:fee_currency fee)
      in
      concat [ mv ~user ~destination ~src ~dst ~currency amount; fee_part ])
  | Vault_create { usdc = x; fee; vault = _ } ->
    concat
      [ one ~kind:Vault_deposit ~venue:Perp ~currency:usdc (Q.neg x)
      ; one ~suffix:":fee" ~kind:Trade_fee ~venue:Perp ~currency:usdc (Q.neg fee)
      ]
  | Vault_deposit { usdc = x; vault = _ } ->
    one ~kind:Vault_deposit ~venue:Perp ~currency:usdc (Q.neg x)
  | Vault_withdraw { user; net_withdrawn_usd; vault = _ } ->
    if Hl_protocol.Address.equal user config.address
    then one ~kind:Vault_withdrawal ~venue:Perp ~currency:usdc net_withdrawn_usd
    else Ok []
  | Vault_distribution { usdc = x; vault = _ } ->
    one ~kind:Vault_commission ~venue:Perp ~currency:usdc x
  | Rewards_claim { amount } ->
    (match config.rewards with
     | On_claim -> one ~kind:Referral_reward ~venue:config.claim_venue ~currency:usdc amount
     | Accrued ->
       one
         ~kind:Internal
         ~venue:Rewards
         ~currency:usdc
         ~counter:(Location (here config.claim_venue))
         (Q.neg amount))
  | C_staking_transfer { token; amount; is_deposit } ->
    with_token token (fun currency ->
      let from, to_ = if is_deposit then Venue.Spot, Venue.Staking else Staking, Spot in
      one ~kind:Staking ~venue:from ~currency ~counter:(Location (here to_)) (Q.neg amount))
  | Spot_genesis { token; amount } ->
    with_token token (fun currency -> one ~kind:Other ~venue:Spot ~currency amount)
  | Gas_auction { token; amount } ->
    with_token token (fun currency ->
      one ~kind:Trade_fee ~venue:Spot ~currency (Q.neg amount))
  | Other _ -> Ok []
;;

let normalize (config : Config.t) event =
  let result =
    match event with
    | Fill d -> fill_activities config d
    | Funding f ->
      let%bind.Or_error venue = perp_venue f.coin in
      if nonzero f.usdc
      then
        activity
          ~id:(sprintf "funding:%d:%s" f.time f.coin)
          ~kind:Funding
          ~location:(location config venue)
          ~currency:(Config.collateral config venue)
          ~amount:f.usdc
          ~at:(time_of_ms f.time)
          ~market:f.coin
          ()
        |> Or_error.map ~f:List.return
      else Ok []
    | Ledger_update u -> ledger_activities config u
    | Staking_reward r ->
      activity
        ~id:(sprintf "stakingReward:%d:%s" r.time r.source)
        ~kind:Staking_reward
        ~location:(location config Staking)
        ~currency:Assets.hype
        ~amount:r.total_amount
        ~at:(time_of_ms r.time)
        ()
      |> Or_error.map ~f:List.return
    | Builder_fill b ->
      activity
        ~id:(sprintf "bf:%d" b.tid)
        ~kind:Builder_fee
        ~location:(location config Rewards)
        ~currency:Money.Currency.usdc
        ~amount:b.fee
        ~at:(time_of_ms b.time)
        ~market:b.coin
        ()
      |> Or_error.map ~f:List.return
  in
  Or_error.tag result ~tag:source
;;

(* {1 Balances} *)

let observe (config : Config.t) report =
  let observed_at = report.observed_at in
  let balance ~venue ~currency q =
    { Observed.Balance.location = location config venue
    ; amount = Normalizer.round currency q
    ; observed_at
    }
  in
  let%bind.Or_error address = address_of config.address in
  let%bind.Or_error perp =
    List.map report.perp ~f:(fun (dex, (state : Hl_protocol.Clearinghouse_state.t)) ->
      let%bind.Or_error venue =
        match dex with
        | None -> Ok Venue.Perp
        | Some dex -> Venue.perp_dex dex
      in
      let settle = Config.collateral config venue in
      let unrealised =
        List.fold state.positions ~init:Q.zero ~f:(fun acc p ->
          Q.add acc (usd_q p.unrealized_pnl))
      in
      let%map.Or_error positions =
        List.map state.positions ~f:(fun p ->
          let%map.Or_error instrument =
            Instrument.perp ~coin:(Hl_protocol.Coin.to_string p.coin) ~settle
          in
          { Observed.Position.address
          ; instrument
          ; size = size_q p.szi
          ; entry_price = Option.map p.entry_px ~f:price_q
          ; observed_at
          })
        |> Or_error.combine_errors
      in
      ( balance
          ~venue
          ~currency:settle
          (Q.sub (usd_q state.margin_summary.account_value) unrealised)
      , positions ))
    |> Or_error.combine_errors
  in
  let spot =
    match report.spot with
    | None -> []
    | Some spot ->
      List.filter_map spot.balances ~f:(fun b ->
        Option.map (Config.token config b.coin) ~f:(fun currency ->
          balance ~venue:Spot ~currency b.total))
  in
  let staking =
    Option.map report.staking ~f:(fun s ->
      balance ~venue:Staking ~currency:Assets.hype (Delegator_summary.staking_balance s))
    |> Option.to_list
  in
  Ok
    { Observed.balances = List.map perp ~f:fst @ spot @ staking
    ; positions = List.concat_map perp ~f:snd
    }
  |> Or_error.tag ~tag:source
;;
