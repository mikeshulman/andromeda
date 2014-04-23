(** Context with hints. *)

type declaration =
  | Parameter of Syntax.ty
  | Definition of Syntax.ty * Syntax.term

type hint =
  | Equation of Syntax.term * Syntax.term
  | Rewrite of Syntax.term * Syntax.term

type t = {
  decls : declaration list ;
  names : Syntax.name list ;
  hints : hint list
}

let empty = { decls = [] ; names = [] ; hints = [] }

let names {names=lst} = lst

let shift_declaration delta declaration =
  match declaration with
  | Parameter ty1 ->
      Parameter( Syntax.shift_ty delta ty1 )
  | Definition(ty1, term1) ->
      Definition( Syntax.shift_ty delta ty1,
                  Syntax.shift delta term1 )

let shift_hint delta hint =
  match hint with
  | Equation(term1, term2) ->
      Equation( Syntax.shift delta term1,
                Syntax.shift delta term2 )
  | Rewrite(term1, term2) ->
      Rewrite( Syntax.shift delta term1,
               Syntax.shift delta term2 )

let add_var x t ctx =
  {
    decls = Parameter t :: ctx.decls ;
    hints = List.map (shift_hint 1) ctx.hints;
    names = x :: ctx.names;
  }

let add_vars bnds ctx =
  let rec loop vars_added accum_ctx = function
    | []          -> accum_ctx
    | (x,t)::rest ->
        loop (vars_added+1)
             (add_var x (Syntax.shift_ty vars_added t) accum_ctx)
             rest
  in
     loop 0 ctx bnds

let add_def x t ((_,loc) as e) ctx =
  {
    decls = Definition (t, e) :: ctx.decls ;
    hints = List.map (shift_hint 1) (Rewrite((Syntax.Var (-1), loc), e) :: ctx.hints);
    names = x :: ctx.names;
  }

let add_equation e1 e2 ctx =
  { ctx with
    hints = Equation (e1, e2) :: ctx.hints }

let add_rewrite e1 e2 ctx =
  { ctx with
    hints = Rewrite (e1, e2) :: ctx.hints }

let lookup_var index {decls=lst} =
  try begin
    let inserted_ty =
      match List.nth lst index with
      | Parameter t       -> t
      | Definition (t, _) -> t  in
    (* Return the classifier relative to *this* context, not
       the context where we inserted the type.  (Unlike hints,
       we don't shift these inserted types each time a new
       variable is added to the context.)
     *)
    Syntax.shift_ty (index+1) inserted_ty
  end
  with
    | Failure _ -> Error.impossible "invalid de Bruijn index"

let lookup_equation e1 e2 ctx =
  let predicate = function
    | Equation(term1, term2)
    | Rewrite(term1, term2) ->
       (Syntax.equal e1 term1 && Syntax.equal e2 term2) ||
       (Syntax.equal e2 term1 && Syntax.equal e1 term2)
  in
    List.exists predicate ctx.hints

let lookup_rewrite e1 ctx =
  begin
    let predicate = function
      | Rewrite(term1, _) -> Syntax.equal e1 term1
      | _ -> false  in
    match List.filter predicate ctx.hints with
    | [] -> None
    | [Rewrite(_,term2)] -> Some term2
    | Rewrite(_,term2) :: _ ->
        begin
          Print.warning "Choosing first of multiple rewrites for term";
          Some term2
        end
    | Equation _ :: _ ->
        Error.impossible "lookup_rewrite found an Equation after filtering"
  end

let print {decls=ds; names=xs} =
  let rec loop ds xs =
    match ds, xs with
      | [], [] -> ()
      | d::ds, x::xs ->
        loop ds xs ;
        begin match d with
          | Parameter t ->
              Format.printf "@[<hov 4>assume %s@;<1 -2>: %t@]@\n" x (Print.ty xs t)
          | Definition (t, e) ->
              Format.printf "@[<hov 4>define %s@;<1 -2>: %t@;<1 -2>:= %t@]@\n"
                x (Print.ty xs t) (Print.term xs e)
        end
      | [], _::_ -> Error.impossible "fewer declarations than names in context"
      | _::_, [] -> Error.impossible "fewer names than declarations in context"
  in
    loop ds xs ;
    Format.printf "@."
