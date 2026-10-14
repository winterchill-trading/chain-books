open! Core

include Short_id.Make (struct
    let module_name = "Chain_books.Binding_id"
    let max_length = 16

    let allowed_char c =
      Char.is_alphanum c || Char.equal c '_' || Char.equal c '-' || Char.equal c '.'
    ;;

    let sample_chars = "abcdefxyz0189-_"
  end)
