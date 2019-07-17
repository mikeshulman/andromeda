(** Formation of judgements from rules *)

open Nucleus_types

let error = Error.raise

let form_alpha_equal_type t1 t2 =
  match Alpha_equal.is_type t1 t2 with
  | false -> None
  | true -> Some (Mk.eq_type Assumption.empty t1 t2)

(** Compare two terms for alpha equality. *)
let form_alpha_equal_term sgn e1 e2 =
  let t1 = Sanity.type_of_term sgn e1
  and t2 = Sanity.type_of_term sgn e2
  in
  (* XXX if e1 and e2 are α-equal, we may apply uniqueness of typing to
     conclude that their types are equal, so we don't have to compute t1, t2,
     and t1 =α= t2. *)
  match Alpha_equal.is_type t1 t2 with
  | false -> error (AlphaEqualTypeMismatch (t1, t2))
  | true ->
     begin match Alpha_equal.is_term e1 e2 with
     | false -> None
     | true ->
        (* We may keep the assumptions empty here. One might worry
           that the assumptions needed for [e2 : t2] have to be included,
           but this does not seem to be the case: we have [e2 : t2] and
           [t1 == t2] (without assumptions as they are alpha-equal!),
           hence by conversion [e2 : t1], and whatever assumptions are
           required for [e2 : t2], they're already present in [e2]. *)
        Some (Mk.eq_term Assumption.empty e1 e2 t1)
     end

let rec form_alpha_equal_abstraction equal_u abstr1 abstr2 =
  match abstr1, abstr2 with
  | NotAbstract u1, NotAbstract u2 ->
     begin match equal_u u1 u2 with
     | None -> None
     | Some eq -> Some (Mk.not_abstract eq)
     end
  | Abstract (atm1, abstr1), Abstract (atm2, abstr2) ->
     begin match Alpha_equal.is_type atm1.atom_type atm2.atom_type with
     | false -> None
     | true ->
        begin match form_alpha_equal_abstraction equal_u abstr1 abstr2 with
        | None -> None
        | Some eq -> Some (Mk.abstract atm1 eq)
        end
     end
  | (NotAbstract _, Abstract _)
  | (Abstract _, NotAbstract _) -> None


(** Partial rule applications *)
let form_rap sgn constr prems =
  match prems with
  | [] -> RapDone (constr [])
  | p :: ps ->
     RapMore
       { rap_arguments = []
       ; rap_boundary = Form_rule.instantiate_premise [] p
       ; rap_premises = ps
       ; rap_constructor = constr
       }

let rap_boundary {rap_boundary;_} = rap_boundary

let form_rap_is_type sgn c =
  let prems, () = Signature.lookup_rule_is_type c sgn in
  form_rap sgn
    (fun args -> Mk.type_constructor c (Indices.to_list args)) prems

let form_rap_is_term sgn c =
  let prems, _t_schema = Signature.lookup_rule_is_term c sgn in
  form_rap sgn
    (fun args -> Mk.term_constructor c (Indices.to_list args))
    prems

let form_rap_eq_type sgn c =
  let prems, (lhs_schema, rhs_schema) = Signature.lookup_rule_eq_type c sgn in
  form_rap sgn
    (fun args ->
      (* order of arguments not important in [Collect_assumptions.arguments],
         we could try avoiding a list reversal caused by [Indices.to_list]. *)
      let asmp = Collect_assumptions.arguments (Indices.to_list args)
      and lhs = Instantiate_meta.is_type ~lvl:0 args lhs_schema
      and rhs = Instantiate_meta.is_type ~lvl:0 args rhs_schema
      in Mk.eq_type asmp lhs rhs)
    prems

let form_rap_eq_term sgn c =
  let prems, (e1_schema, e2_schema, t_schema) = Signature.lookup_rule_eq_term c sgn in
  form_rap sgn
    (fun args ->
      (* order of arguments not important in [Collect_assumptions.arguments],
         we could try avoiding a list reversal caused by [Indices.to_list]. *)
      let asmp = Collect_assumptions.arguments (Indices.to_list args)
      and e1 = Instantiate_meta.is_term ~lvl:0 args e1_schema
      and e2 = Instantiate_meta.is_term ~lvl:0 args e2_schema
      and t = Instantiate_meta.is_type ~lvl:0 args t_schema
      in Mk.eq_term asmp e1 e2 t)
    prems

let rap_apply sgn {rap_arguments; rap_boundary; rap_premises; rap_constructor} arg =
  if not (match rap_boundary, arg with
          | BoundaryIsType bdry, ArgumentIsType arg -> Alpha_equal.check_is_type_boundary arg bdry
          | BoundaryIsTerm bdry, ArgumentIsTerm arg -> Alpha_equal.check_is_term_boundary sgn arg bdry
          | BoundaryEqType bdry, ArgumentEqType arg -> Alpha_equal.check_eq_type_boundary arg bdry
          | BoundaryEqTerm bdry, ArgumentEqTerm arg -> Alpha_equal.check_eq_term_boundary arg bdry
          | _, _ -> false)
  then Error.raise InvalidArgument ;
  let rap_arguments = arg :: rap_arguments in
  match rap_premises with
  | [] -> RapDone (rap_constructor rap_arguments)
  | p :: rap_premises ->
     (** XXX Should we not use the available arguments instead of [] in the line below? *)
     let rap_boundary = (Form_rule.instantiate_premise [] p) in
     RapMore { rap_arguments
             ; rap_boundary
             ; rap_premises
             ; rap_constructor }

let form_is_term_atom = Mk.atom

(** Conversion *)

let form_is_term_convert sgn e (EqType (asmp, t1, t2)) =
  match e with
  | TermConvert (e, asmp0, t0) ->
     if Alpha_equal.is_type t0 t1 then
       (* here we rely on transitivity of equality *)
       let asmp = Assumption.union asmp0 (Assumption.union asmp (Collect_assumptions.is_type t1))
       (* we could have used the assumptions of [t0] instead, because [t0] and [t1] are
            alpha equal, and so either can derive the type. Possible optimizations:
              (i) pick the smaller of the assumptions of [t0] or of [t1],
             (ii) pick the asumptions that are included in [t2]
            (iii) remove assumptions already present in [t2] from the assumption set
       *)
       in
       (* [e] itself is not a [TermConvert] by the maintained invariant. *)
       Mk.term_convert e asmp t2
     else
       error (InvalidConvert (t0, t1))

  | (TermAtom _ | TermBound _ | TermConstructor _ | TermMeta _) as e ->
     let t0 = Sanity.natural_type sgn e in
     if Alpha_equal.is_type t0 t1 then
       (* We need not include assumptions of [t1] because [t0] is alpha-equal
            to [t1] so we can use [t0] in place of [t1] if so desired. *)
       (* [e] is not a [TermConvert] by the above pattern-check *)
       Mk.term_convert e asmp t2
     else
       error (InvalidConvert (t0, t1))

let form_eq_term_convert (EqTerm (asmp1, e1, e2, t0)) (EqType (asmp2, t1, t2)) =
  if Alpha_equal.is_type t0 t1 then
    (* We could have used the assumptions of [t0] instead of [t1], see comments in [form_is_term]
       about possible optimizations. *)
    let asmp = Assumption.union asmp1 (Assumption.union asmp2 (Collect_assumptions.is_type t1)) in
    Mk.eq_term asmp e1 e2 t2
  else
    error (InvalidConvert (t0, t1))



let symmetry_term (EqTerm (asmp, e1, e2, t)) = Mk.eq_term asmp e2 e1 t

let symmetry_type (EqType (asmp, t1, t2)) = Mk.eq_type asmp t2 t1

let transitivity_term (EqTerm (asmp, e1, e2, t)) (EqTerm (asmp', e1', e2', t')) =
  match Alpha_equal.is_type t t' with
  | false -> error (AlphaEqualTypeMismatch (t, t'))
  | true ->
     begin match Alpha_equal.is_term e2 e1' with
     | false -> error (AlphaEqualTermMismatch (e2, e1'))
     | true ->
        (* XXX could use assumptions of [e1'] instead, or whichever is better. *)
        let asmp = Assumption.union asmp (Assumption.union asmp' (Collect_assumptions.is_term e2))
        in Mk.eq_term asmp e1 e2' t
     end

let transitivity_type (EqType (asmp1, t1, t2)) (EqType (asmp2, u1, u2)) =
  begin match Alpha_equal.is_type t2 u1 with
  | false -> error (AlphaEqualTypeMismatch (t2, u1))
  | true ->
     (* XXX could use assumptions of [u1] instead, or whichever is better. *)
     let asmp = Assumption.union asmp1 (Assumption.union asmp2 (Collect_assumptions.is_type t2))
     in Mk.eq_type asmp t1 u2
  end
