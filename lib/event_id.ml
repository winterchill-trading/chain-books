open! Core

include Short_id.Make (struct
    let module_name = "Chain_books.Event_id"
    let max_length = 90
    let allowed_char c = String.mem "_-.:/@+" c || Char.is_alphanum c
    let sample_chars = "abcfil0179:-"
  end)
