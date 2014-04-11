(********************)
(* Helper Functions *)
(********************)


let print_ty ctx ty =
  Print.ty (Context.names ctx) ty

let print_term ctx term =
  Print.term (Context.names ctx) term


(*************************)
(* Weak-Head Normalizing *)
(*************************)

(* Single step for a type *)

let rec whnf_ty ctx1 (ty',loc) =
  match ty' with

  | Syntax.El(alpha, ((e', _) as e)) ->
      begin
        (* tynorm-el *)
        match whnf ctx1 e with
      | Some (ctx2, e2) ->
          (* Non-backtracking, for now *)
          Some (ctx2, (Syntax.El(alpha, e2), loc))
      | None ->
          begin
            match e' with

            (* tynorm-pi *)
            | Syntax.NameProd(beta, gamma, x, e1, e2) ->
                Some (ctx1,
                      (Syntax.Prod(
                        x,
                        (Syntax.El(beta, e1), loc),
                        (Syntax.El(gamma, e2), loc)), loc))

            (* tynorm-unit *)
            | Syntax.NameUnit ->
                Some (ctx1, (Syntax.Unit, loc))

            (* tynorm-coerce *)
            | Syntax.Coerce(_beta,_gamma, e) ->
                Some (ctx1, (Syntax.El(alpha, e), loc))

            (* tynorm-paths *)
            | Syntax.NamePaths(_beta, e1, e2, e3) ->
                Some (ctx1, (Syntax.Paths((Syntax.El(alpha, e1), loc), e2, e3), loc))

            (* tynorm-id *)
            | Syntax.NameId(_beta, e1, e2, e3) ->
                Some (ctx1, (Syntax.Id((Syntax.El(alpha, e1), loc), e2, e3), loc))

            | _ -> None
          end
      end

  | (Syntax.Universe _ | Syntax.Unit | Syntax.Prod _ | Syntax.Paths _ | Syntax.Id _) -> None

and whnf ctx1 ((term',loc) as term) =
  match Context.lookup_rewrite term ctx1 with
  | Some reduct -> Some (ctx1, reduct)
  | None ->
      begin
        match term' with
        (* norm-equation *)
        | Syntax.Equation(_e1, (e2,e3), e4) ->
            Some (Context.add_equation e2 e3 ctx1, e4)

        (* norm-rewrite *)
        | Syntax.Rewrite(_e1, (e2,e3), e4)  ->
            Some (Context.add_rewrite e2 e3 ctx1, e4)

        (* norm-ascribe *)
        | Syntax.Ascribe(e, _t) -> Some (ctx1, e)

        (* norm-app-beta *)
        | Syntax.App((x,u1,u2),
                     (Syntax.Lambda(_x',t1,t2,e1), _),
                     e2)
            when equiv_ty ctx1 t1 u1
                 && equiv_ty (Context.add_var x t1 ctx1) t2 u2 ->
            Some (ctx1, Syntax.beta e1 e2)

        (* norm-idpath *)
        | Syntax.J(t, (_x,_y,_p,u), (_z,e1),
                   (Syntax.Idpath(t',e2), _), _e3, _e4)
            when equiv_ty ctx1 t t' ->
            Some (ctx1, Syntax.beta e1 e2)

        (* norm-coerce-trivial *)
        | Syntax.Coerce(alpha1, alpha2, e)
            when alpha1 = alpha2 ->
            Some (ctx1, e)

        (* norm-coerce-trans *)
        | Syntax.Coerce(beta1, gamma,
                        (Syntax.Coerce(alpha, beta2, e), _))
            when beta1 = beta2 ->
            Some (ctx1, e)

        (* norm-app *)
        | Syntax.App((x,t,u), e1, e2) ->
            begin
              match whnf ctx1 e1 with
              | Some (ctx2, e1') -> Some (ctx2, (Syntax.App((x,t,u), e1', e2), loc))
              | None -> None
            end

        (* norm-J *)
        | Syntax.J(t, (x,y,p,u), (z,e1), e2, e3, e4) ->
            begin
              match whnf ctx1 e2 with
              | Some (ctx2, e2') ->
                  Some (ctx2, (Syntax.J(t, (x,y,p,u), (z,e1), e2', e3, e4), loc))
              | None -> None
            end

        | _ -> None
      end

(* Repeatedly apply whnf until nothing changes *)
and whnfs ctx1 term1 =
  match whnf ctx1 term1 with
  | Some (ctx2, term2) -> whnfs ctx2 term2
  | None               -> term1

(* Repeatedly apply whnf_ty until nothing changes *)
and whnfs_ty ctx1 ty1 =
  match whnf_ty ctx1 ty1 with
  | Some (ctx2, ty2) -> whnfs_ty ctx2 ty2
  | None             -> ty1

(***************)
(* Equivalence *)
(***************)

(* equivalence of types *)

and equiv_ty ctx t u =
  (* chk-tyeq-refl *)
  if (Syntax.equal_ty t u) then
    true
  else
    let t' = whnfs_ty ctx t  in
    let u' = whnfs_ty ctx u  in
    equiv_whnf_ty ctx t' u'

(* equivalence of weak-head-normal types *)

and equiv_whnf_ty ctx ((t', tloc) as t) ((u', uloc) as u) =
  begin
    match t', u' with

    (* chk-tyeq-path-refl *)
    | _, _ when Syntax.equal_ty t u -> true

    (* chk-tyeq-el *)
    | Syntax.El(alpha, e1), Syntax.El(beta, e2) ->
        alpha = beta && equiv ctx e1 e2 (Syntax.Universe alpha, uloc)

    (* chk-tyeq-prod *)
    | Syntax.Prod(x, t1, t2), Syntax.Prod(_, u1, u2) ->
        equiv_ty ctx t1 u1 &&
        equiv_ty (Context.add_var x t1 ctx) t2 u2

    (* chk-tyeq-paths *)
    | Syntax.Paths(t,e1,e2), Syntax.Paths(u,e1',e2') ->
        equiv_ty ctx t u &&
        equiv ctx e1 e1' t &&
        equiv ctx e2 e2' t

    (* chk-tyeq-id *)
    | Syntax.Id(t,e1,e2), Syntax.Id(u,e1',e2') ->
        equiv_ty ctx t u &&
        equiv ctx e1 e1' t &&
        equiv ctx e2 e2' t

    | (Syntax.Universe _ | Syntax.El _ | Syntax.Unit
       | Syntax.Prod _ | Syntax.Paths _ | Syntax.Id _), _ ->
        false
  end

(* equivalence of terms.

   Precondition: t is well-formed
                 term1 : t
                 term2 : t
 *)
and equiv ctx term1 term2 t =

  (* chk-eq-refl *)
  if (Syntax.equal term1 term2) then
    true

  (* chk-eq-hint *)
  else if (Context.lookup_equation term1 term2 ctx) then
    true

  else
    let t' = whnfs_ty ctx t in
    equiv_ext ctx term1 term2 t'

(* Equivalence of terms at a weak-head-normal type.

   Precondition: ty is well-formed *and weak-head-normal*
                 e1 : ty
                 e2 : ty
 *)
and equiv_ext ctx ((_, loc1) as e1) ((_, loc2) as e2) (ty', _) =
  begin
    match ty' with

    (* chk-eq-ext-prod *)
    | Syntax.Prod(x, t, u) ->
        (* To keep the two x binders straight, we'll call the one in
           the context z. *)
        let ctx' = Context.add_var x t ctx  in   (* ctx' === ctx, z *)
                                           (* ctx       |- e1  : ... *)
        let e1' = Syntax.weaken 0 e1 in    (* ctx, z    |- e1' : ... *)
                                           (* ctx       |- e2  : ... *)
        let e2' = Syntax.weaken 0 e2 in    (* ctx, z    |- e2' : ... *)
                                           (* ctx       |- t  type *)
        let t'  = Syntax.weaken_ty 0 t in  (* ctx, z    |- t' type *)
                                           (* ctx,    x |- u type *)
        let u' = Syntax.weaken_ty 1 u  in  (* ctx, z, x |- u type *)
        let z = (Syntax.Var 0,
                 Position.nowhere) in      (* ctx, z    |- z : ... *)
        equiv ctx'
              (Syntax.App((x, t', u'), e1', z), loc1)
              (Syntax.App((x, t', u'), e2', z), loc2)
              u'

    (* chk-eq-ext-unit *)
    | Syntax.Unit ->
        true

    (* chk-eq-ext-K *)
    | Syntax.Id (_T, _e3, _e4) ->
        true

    (* chk-eq-ext-whnf *)
    | _ ->
        let e1' = whnfs ctx e1  in
        let e2' = whnfs ctx e2  in
        equiv_whnf ctx e1' e2'
  end

(* equivalence of two weak-head-normal terms.

   Precondition: term1 : ty
                 term2 : ty
                    for some (unspecified) common type ty.
 *)
and equiv_whnf ctx ((term1', loc1) as term1) ((term2', loc2) as term2) =
  begin
    match term1', term2' with

    (* chk-eq-whnf-reflexivity *)
    | _, _ when Syntax.equal term1 term2 ->
        true

    (* chk-eq-whnf-equation *)
    | _, _ when Context.lookup_equation term1 term2 ctx ->
        true

    (* chk-eq-whnf-var *)
    | Syntax.Var index1, Syntax.Var index2 -> index1 = index2

    (* chk-eq-whnf-app *)
    | Syntax.App((x, t1, t2), e1, e2), Syntax.App((_, u1, u2), e1', e2') ->
        equiv_ty ctx t1 u1
        && equiv_ty (Context.add_var x t1 ctx) t2 u2
        && equiv_whnf ctx e1 e2
        && equiv ctx e2 e2' t1

    (* chk-eq-whnf-idpath *)
    | Syntax.Idpath(t, e1), Syntax.Idpath(u, e2) ->
        equiv_ty ctx t u && equiv ctx e1 e2 t

    (* chk-eq-whnf-j *)
    | Syntax.J(t1,(x,y,p,u2),(z,e3),e4, e5, e6), Syntax.J(t7, (_,_,_,u8), (_,e9), e10, e11, e12) ->
        let ctx_xyp = Context.add_vars
                       [  (x, t1);
                          (y, t1);
                          (p, (Syntax.Paths
                                (t1,
                                (Syntax.Var (-1) (* x *), Position.nowhere),
                                (Syntax.Var (-2) (* y *), Position.nowhere)),
                                Position.nowhere)) ] ctx  in
        let ctx_z = Context.add_var z t1 ctx  in

        let e3_ty_expected =
                                                         (* ctx,    x, y, p |- u2 type *)
          let u2' = Syntax.weaken_ty 3 u2  in            (* ctx, z, x, y, p |- u2' type *)
                                                         (* ctx    |- t1 type *)
          let t1' = Syntax.weaken_ty 0 t1  in            (* ctx, z |- t1' type *)
          let zvar = (Syntax.Var 0, Position.nowhere) in (* ctx, z |- z *)
          Syntax.strengthen_ty u2'
             [zvar; zvar; (Syntax.Idpath(t1', zvar), Position.nowhere)]
                                              (* ctx, z |- u2'[x,y,p->z,z,idpath z]  type *)  in

        (*
        let j_ty_expected =
          Syntax.strengthen_ty u2 [e5; e6; e4]  in       (* ctx |- u2[x,y,p->e5,e6,e4] *)
        *)

        equiv_ty ctx t1 t7
        && equiv_ty ctx_xyp u2 u8
        && equiv ctx_z e3 e9 e3_ty_expected
        && equiv ctx e5 e11 t1
        && equiv ctx e6 e12 t1
        && equiv_whnf ctx e4 e10

    (* chk-eq-whnf-refl *)
    | Syntax.Refl(t, e1), Syntax.Refl(u, e2) ->
        equiv_ty ctx t u && equiv ctx e1 e2 t

    (* chk-eq-whnf-prod *)
    | Syntax.NameProd(alpha, beta, x, e1, e2), Syntax.NameProd(alpha', beta', _, e1', e2') ->
        alpha = alpha' && beta = beta'
        && equiv ctx e1 e1' (Syntax.Universe alpha, Position.nowhere)
        && equiv (Context.add_var x (Syntax.El(alpha,e1), Position.nowhere) ctx)
                 e2 e2' (Syntax.Universe beta, Position.nowhere)

    (* chk-eq-whnf-universe *)
    | Syntax.NameUniverse alpha, Syntax.NameUniverse beta ->
        alpha = beta

    (* chk-eq-whnf-unit *)              (** Subsumed by reflexivity check! *)
    (*| Syntax.NameUnit, Syntax.NameUnit -> true *)

    (* chk-eq-whnf-paths *)
    | Syntax.NamePaths(alpha, e1, e2, e3), Syntax.NamePaths(alpha', e1', e2', e3') ->
        alpha = alpha'
        && equiv ctx e1 e1' (Syntax.Universe alpha, Position.nowhere)
        && equiv ctx e2 e2' (Syntax.El (alpha, e1), Position.nowhere)
        && equiv ctx e3 e3' (Syntax.El (alpha, e1), Position.nowhere)

    (* chk-eq-whnf-id *)
    | Syntax.NameId(alpha, e1, e2, e3), Syntax.NameId(alpha', e1', e2', e3') ->
        alpha = alpha'
        && equiv ctx e1 e1' (Syntax.Universe alpha, Position.nowhere)
        && equiv ctx e2 e2' (Syntax.El (alpha, e1), Position.nowhere)
        && equiv ctx e3 e3' (Syntax.El (alpha, e1), Position.nowhere)

    (* chk-eq-whnf-coerce *)
    | Syntax.Coerce(alpha, _beta, e1), Syntax.Coerce(alpha', _beta', e1') ->
        alpha = alpha'
        && equiv ctx e1 e1' (Syntax.Universe alpha, Position.nowhere)

    (* chk-eq-whnf-abs *)
    | Syntax.Lambda(x,t1,t2,e1), Syntax.Lambda(_,u1,u2,e2) ->
        equiv_ty ctx t1 u1
        && let ctx' = Context.add_var x t1 ctx  in
           equiv_ty ctx' t2 u2 && equiv ctx' e1 e2 t2

    (* chk-eq-whnf-unit-right *)
    | _, Syntax.UnitTerm ->
        true

    (* chk-eq-whnf-unit-left *)
    | Syntax.UnitTerm, _ ->
        true

    (* chk-eq-whnf-refl-left *)
    | Syntax.Refl _, _ ->
        true

    (* chk-eq-whnf-refl-right *)
    | _, Syntax.Refl _ ->
        true

    | (Syntax.Var _ | Syntax.Equation _ | Syntax.Rewrite _ | Syntax.Ascribe _
      | Syntax.Lambda _ | Syntax.App _ | Syntax.Idpath _
      | Syntax.J _ | Syntax.Coerce _ | Syntax.NameUnit
      | Syntax.NameProd _ | Syntax.NameUniverse _ | Syntax.NamePaths _
      | Syntax.NameId _), _ -> false
  end

(***********************************)
(* Synthesis and Checking of Terms *)
(***********************************)


let rec syn_term ctx e = failwith "not implemented"

and chk_term ctx ((term', loc) as term) t =

  match term' with

  (* chk-eq-hint *)
  | Input.Equation (e1, e4) ->
      begin
        let e1_annot, u' = syn_term ctx e1  in
        match whnfs_ty ctx u' with
        | Syntax.Id(u,e2,e3),_ ->
            let ctx' = Context.add_equation e2 e3 ctx  in
            let (e4_annot : Syntax.term) = chk_term ctx' e4 t in
            (Syntax.Equation(e1_annot, (e2, e3), e4_annot), loc)
        | _ ->
            Error.typing ~loc "hint@ %t@ has type@ %t@ but an equality type was expected."
               (print_term ctx e1_annot)
               (print_ty   ctx u')
      end

  (* chk-rw-hint *)
  | Input.Rewrite (e1, e4) ->
      begin
        let e1_annot, u' = syn_term ctx e1  in
        match whnfs_ty ctx u' with
        | Syntax.Id(u,e2,e3),_ ->
            let ctx' = Context.add_equation e2 e3 ctx  in
            let (e4_annot : Syntax.term) = chk_term ctx' e4 t in
            (Syntax.Rewrite(e1_annot, (e2, e3), e4_annot), loc)
        | _ ->
            Error.typing ~loc "hint@ %t@ has type@ %t@ but an equality type was expected."
               (print_term ctx e1_annot)
               (print_ty   ctx u')
      end


  (* chk-syn *)
  | _ -> let e_annot, u = syn_term ctx term  in
         if (equiv_ty ctx u t) then
            e_annot
         else
            Error.typing ~loc "expression %t@ has type %t@\nbut should have type %t"
              (print_term ctx e_annot)
              (print_ty ctx u)
              (print_ty ctx t)

(***********************************)
(* Synthesis and Checking of Types *)
(***********************************)


(* Can the given unannotated type be verified and translated into an annotated type?
 *)
and is_type ctx (ty, loc) =
  let t =
    begin match ty with

      (* tychk-universe *)
      | Input.Universe u -> Syntax.Universe u
        
      (* tychk-el *)
      | Input.El e ->
        begin
          let (e, t) = syn_term ctx e in
          let t = whnfs_ty ctx t in
            match fst t with
              | Syntax.Universe u -> Syntax.El (u, e)
              | _ -> Error.typing ~loc "this expression should be a type but it has type@ %t"
                (print_ty ctx t)
        end

    (* tychk-unit *)
      | Input.Unit -> Syntax.Unit

    (* tychk-prod *)
      | Input.Prod (x, t, u) ->
        let t = is_type ctx t in
        let u = is_type (Context.add_var x t ctx) u in
          Syntax.Prod (x, t, u)

    (* tychk-paths *)
      | Input.Paths (e1, e2) ->
        begin
          let (e1, t) = syn_term ctx e1 in
            match wf_type_is_fibered t with
              | true ->
                let e2 = chk_term ctx e2 t in
                  Syntax.Paths (t, e1, e2)
              | false ->
                Error.typing ~loc "invalid pahts because %t is not fibered"
                  (print_ty ctx t)
        end

    (* tychk-id *)
      | Input.Id (e1, e2) ->
        let (e1, t) = syn_term ctx e1 in
        let e2 = chk_term ctx e2 t in
          Syntax.Paths (t, e1, e2)
    end
  in
    (t, loc)

(* Can the given unannotated type be verified and translated into an annotated fibered type?
 *)
and is_fibered ctx ((_, loc) as ty) =
  let annotated_ty = is_type ctx ty   in
  if wf_type_is_fibered annotated_ty then
    annotated_ty
  else
    Error.typing ~loc "expected a fibered type but found@ %t"
         (print_ty ctx annotated_ty)

(* wf_type_is_fibered: Syntax.ty -> bool
    Is the given well-formed type also a fibered type?
*)
and wf_type_is_fibered (ty', _) =
  match ty' with
  | Syntax.Universe alpha -> Universe.is_fibered (fst alpha)
  | Syntax.Prod(_, t, u) ->
      wf_type_is_fibered t && wf_type_is_fibered u
  | Syntax.El(alpha, _) -> Universe.is_fibered (fst alpha)
  | Syntax.Unit -> true
  | Syntax.Paths _ -> true
  | Syntax.Id _ -> false

