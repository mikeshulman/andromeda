(** Manipulation of assumptions. *)
open Nucleus_types

(** Collect the assumptions of a type. Caveat: alpha-equal types may have
    different assumptions. *)
let rec is_type ?(lvl=0) = function
  | TypeMeta (mv, args) ->
     let args = term_arguments ~lvl args
     and mv = is_type_meta ~lvl mv in
     Assumption.union mv args

  | TypeConstructor (_, args) -> arguments ~lvl args

and is_term ?(lvl=0) = function

  | TermBound k ->
     if k < lvl then
       Assumption.empty
     else
       Assumption.singleton_bound (k - lvl)

  | TermAtom {atom_name=x; atom_type=t} ->
     Assumption.add_free x t (is_type ~lvl t)

  | TermMeta (mv, args) ->
     let mv = is_term_meta ~lvl mv
     and args = term_arguments ~lvl args in
     Assumption.union mv args

  | TermConstructor (_, args) ->
     arguments ~lvl args

  | TermConvert (e, asmp', t) ->
     Assumption.union
       asmp'
       (Assumption.union (is_term ~lvl e) (is_type ~lvl t))

and eq_type ?(lvl=0) (EqType (asmp, t1, t2)) =
  Assumption.union
    (assumptions ~lvl asmp)
    (Assumption.union (is_type ~lvl t1) (is_type ~lvl t2))

and eq_term ?(lvl=0) (EqTerm (asmp, e1, e2, t)) =
  Assumption.union
    (Assumption.union (assumptions ~lvl asmp) (is_type ~lvl t))
    (Assumption.union (is_term ~lvl e1) (is_term ~lvl e2))

and is_type_meta ~lvl {meta_name; meta_type} =
  let asmp = abstraction (fun ?lvl () -> Assumption.empty) ~lvl meta_type in
  Assumption.add_is_type_meta meta_name meta_type asmp

and is_term_meta ~lvl {meta_name; meta_type} =
  let asmp = abstraction is_type ~lvl meta_type in
  Assumption.add_is_term_meta meta_name meta_type asmp

and abstraction
  : 'a . (?lvl:bound -> 'a -> assumption) ->
    ?lvl:bound -> 'a abstraction -> assumption
  = fun asmp_v ?(lvl=0) -> function
    | NotAbstract v -> asmp_v ~lvl v
    | Abstract (x, u, abstr) ->
       Assumption.union
         (is_type ~lvl u)
         (abstraction asmp_v ~lvl:(lvl+1) abstr)

and term_arguments ~lvl ts =
  List.fold_left
    (fun acc arg -> Assumption.union acc (is_term ~lvl arg))
    Assumption.empty
    ts

and arguments ~lvl args =
  let rec fold asmp = function
    | [] -> asmp
    | arg :: args -> Assumption.union (argument ~lvl arg) (fold asmp args)
  in
  fold Assumption.empty args

and argument ?(lvl=0) = function
  | ArgumentIsType abstr -> abstraction is_type ~lvl abstr
  | ArgumentIsTerm abstr -> abstraction is_term ~lvl abstr
  | ArgumentEqType abstr -> abstraction eq_type ~lvl abstr
  | ArgumentEqTerm abstr -> abstraction eq_term ~lvl abstr

and assumptions ?(lvl=0) asmp = Assumption.at_level ~lvl asmp

let arguments = arguments ~lvl:0


let context_u assumptions_u t =
  let asmp = assumptions_u t in
  let {free; bound; _} = asmp in
  assert (Bound_set.is_empty bound) ;
  let free = Name.AtomMap.bindings free in
  List.map (fun (atom_name, atom_type) -> {atom_name; atom_type}) free

(** Compute the list of atoms occurring in an abstraction. Similar to
    assumptions_XYZ functions, but allows use of the assumptions as atoms.
    May only be called on closed terms. *)
let context_of_abstraction assumptions_u =
  context_u (abstraction ?lvl:None assumptions_u)