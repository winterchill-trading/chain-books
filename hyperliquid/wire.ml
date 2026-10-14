open! Core

let fail name what = failwithf "field %s: %s" name what ()

let field_opt json name =
  match json with
  | `Assoc fields ->
    (match List.Assoc.find fields ~equal:String.equal name with
     | None | Some `Null -> None
     | Some v -> Some v)
  | _ -> fail name "not inside an object"
;;

let field json name =
  match field_opt json name with
  | Some v -> v
  | None -> fail name "missing"
;;

let string json name =
  match field json name with
  | `String s -> s
  | _ -> fail name "not a string"
;;

let int json name =
  match field json name with
  | `Int i -> i
  | `Intlit s -> Int.of_string s
  | _ -> fail name "not an integer"
;;

let bool json name =
  match field json name with
  | `Bool b -> b
  | _ -> fail name "not a boolean"
;;

let decimal_of name = function
  | `String s | `Intlit s ->
    (match Chain_books.Exact.of_string_or_error s with
     | Ok q -> q
     | Error _ -> fail name ("not a decimal: " ^ s))
  | `Int i -> Q.of_int i
  | `Float f ->
    (* Floats only reach here from hand-written input; the venue writes decimals as
       strings. [Q.of_float] is exact for the binary value. *)
    Q.of_float f
  | _ -> fail name "not a decimal"
;;

let decimal json name = decimal_of name (field json name)

let decimal_or_zero json name =
  match field_opt json name with
  | None -> Q.zero
  | Some v -> decimal_of name v
;;

let address json name = Hl_protocol.Address.of_string (String.lowercase (string json name))

let decode ~what f json =
  Or_error.try_with (fun () -> f json) |> Or_error.tag ~tag:("decoding " ^ what)
;;

let q_of_fixed ~units ~units_per_one = Q.of_ints units units_per_one
