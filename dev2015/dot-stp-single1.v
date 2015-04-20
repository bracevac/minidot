Require Export SfLib.

Require Export Arith.EqNat.

Require Export Arith.Le.

(* 
subtyping: 
  - looking at single-environment case again.
  - new pushback proof structure: transitivity axiom only 
    needed in contravariant positions

 TODO:
  - add bindx and/or bind2/bind1 rules
  - transitivity will only hold in realizable context

 QUESTIONS: 
  - exact statement of transitivity? 
  - what's the right notion of realizable types/contexts?
  - how can we do induction across realizability evidence?
*)


(* ############################################################ *)
(* Syntax *)
(* ############################################################ *)

Module DOT.

Definition id := nat.

Inductive ty : Type :=
  | TNoF   : ty (* marker for empty method list *)

  | TBot   : ty
  | TTop   : ty
  | TBool  : ty
  | TAnd   : ty -> ty -> ty
  | TFun   : id -> ty -> ty -> ty
  | TMem   : ty -> ty -> ty
  | TSel   : id -> ty

  | TSelB  : id -> ty
  | TBind  : ty -> ty
.
  
Inductive tm : Type :=
  | ttrue : tm
  | tfalse : tm
  | tvar : id -> tm
  | tapp : id -> id -> tm -> tm (* a.f(x) *)
  | tabs : id -> ty -> list (id * dc) -> tm -> tm (* let f:T = x => y in z *)
  | tlet : id -> ty -> tm -> tm -> tm (* let x:T = y *)                                         
with dc: Type :=
  | dfun : ty -> ty -> id -> tm -> dc (* def m:T = x => y *)
.

Fixpoint dc_type_and (dcs: list(nat*dc)) :=
  match dcs with
    | nil => TNoF
    | (n, dfun T1 T2 _ _)::dcs =>
      TAnd (TFun (length dcs) T1 T2)  (dc_type_and dcs)
  end.


Definition TObj p dcs := TAnd (TMem p p) (dc_type_and dcs).
Definition TArrow p x y := TAnd (TMem p p) (TAnd (TFun 0 x y) TNoF).


Inductive vl : Type :=
| vbool : bool -> vl
| vabs  : list (id*vl) -> id -> ty -> list (id * dc) -> vl (* clos env f:T = x => y *)
| vmock : list (id*vl) -> ty -> id -> id -> vl
.

Definition env := list (nat*vl).
Definition tenv := list (nat*ty).

Fixpoint index {X : Type} (n : nat)
               (l : list (nat * X)) : option X :=
  match l with
    | [] => None
    (* for now, ignore binding value n' !!! *)
    | (n',a) :: l'  => if beq_nat n (length l') then Some a else index n l'
  end.

Fixpoint update {X : Type} (n : nat) (x: X)
               (l : list (nat * X)) { struct l }: list (nat * X) :=
  match l with
    | [] => []
    (* for now, ignore binding value n' !!! *)
    | (n',a) :: l'  => if beq_nat n (length l') then (n',x)::l' else (n',a) :: update n x l'
  end.



(* LOCALLY NAMELESS *)

Inductive closed_rec: nat -> ty -> Prop :=
| cl_nof: forall k,
    closed_rec k TNoF
| cl_top: forall k,
    closed_rec k TTop
| cl_bot: forall k,
    closed_rec k TBot
| cl_bool: forall k,
    closed_rec k TBool
| cl_fun: forall k m T1 T2,
    closed_rec k T1 ->
    closed_rec k T2 ->
    closed_rec k (TFun m T1 T2)
| cl_mem: forall k T1 T2,
    closed_rec k T1 ->
    closed_rec k T2 ->
    closed_rec k (TMem T1 T2)
| cl_and: forall k T1 T2,
    closed_rec k T1 ->
    closed_rec k T2 ->
    closed_rec k (TAnd T1 T2)
| cl_bind: forall k T1,
    closed_rec (S k) T1 ->
    closed_rec k (TBind T1)
| cl_sel: forall k x,
    closed_rec k (TSel x)
| cl_selb: forall k i,
    k > i ->
    closed_rec k (TSelB i)
.

Hint Constructors closed_rec.

Definition closed j T := closed_rec j T.


Fixpoint open_rec (k: nat) (u: id) (T: ty) { struct T }: ty :=
  match T with
    | TSel x      => TSel x (* free var remains free. functional, so we can't check for conflict *)
    | TSelB i     => if beq_nat k i then TSel u else TSelB i
    | TBind T1    => TBind (open_rec (S k) u T1)
    | TNoF        => TNoF
    | TBot => TBot
    | TTop => TTop
    | TBool       => TBool
    | TAnd T1 T2  => TAnd (open_rec k u T1) (open_rec k u T2)
    | TMem T1 T2  => TMem (open_rec k u T1) (open_rec k u T2)
    | TFun m T1 T2  => TFun m (open_rec k u T1) (open_rec k u T2)
  end.

Definition open u T := open_rec 0 u T.

(* sanity check *)
Example open_ex1: open 9 (TBind (TAnd (TMem TBot TTop) (TFun 0 (TSelB 1) (TSelB 0)))) =
                      (TBind (TAnd (TMem TBot TTop) (TFun 0 (TSel  9) (TSelB 0)))).
Proof. compute. eauto. Qed.


Lemma closed_no_open: forall T x j,
  closed_rec j T ->
  T = open_rec j x T.
Proof.
  intros. induction H; intros; eauto;
  try solve [compute; compute in IHclosed_rec; rewrite <-IHclosed_rec; auto];
  try solve [compute; compute in IHclosed_rec1; compute in IHclosed_rec2; rewrite <-IHclosed_rec1; rewrite <-IHclosed_rec2; auto].

  Case "TSelB".
    unfold open_rec. assert (k <> i). omega. 
    apply beq_nat_false_iff in H0.
    rewrite H0. auto.
Qed.

Lemma closed_upgrade: forall i j T,
 closed_rec i T ->
 j >= i ->
 closed_rec j T.
Proof.
 intros. generalize dependent j. induction H; intros; eauto.
 Case "TBind". econstructor. eapply IHclosed_rec. omega.
 Case "TSelB". econstructor. omega.
Qed.


Hint Unfold open.
Hint Unfold closed.


(* ############################################################ *)
(* Static properties: type assignment, subtyping, ... *)
(* ############################################################ *)

(* static type expansion.
   needs to imply dynamic subtyping / value typing. *)
Inductive tresolve: id -> ty -> ty -> Prop :=
  | tr_self: forall x T,
             tresolve x T T
  | tr_and1: forall x T1 T2 T,
             tresolve x T1 T ->
             tresolve x (TAnd T1 T2) T
  | tr_and2: forall x T1 T2 T,
             tresolve x T2 T ->
             tresolve x (TAnd T1 T2) T
  | tr_unpack: forall x T2 T3 T,
             open x T2 = T3 ->
             tresolve x T3 T ->
             tresolve x (TBind T2) T
.

Tactic Notation "tresolve_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "Self" |
    Case_aux c "And1" |
    Case_aux c "And2" |
    Case_aux c "Bind" ].


(* static type well-formedness.
   needs to imply dynamic subtyping. *)
Inductive wf_type : tenv -> ty -> Prop :=
| wf_top: forall env,
    wf_type env TNoF
| wf_bool: forall env,
    wf_type env TBool
| wf_and: forall env T1 T2,
             wf_type env T1 ->
             wf_type env T2 ->
             wf_type env (TAnd T1 T2)
| wf_mem: forall env TL TU,
             wf_type env TL ->
             wf_type env TU ->
             wf_type env (TMem TL TU)
| wf_fun: forall env f T1 T2,
             wf_type env T1 ->
             wf_type env T2 ->
             wf_type env (TFun f T1 T2)
                     
| wf_sel: forall envz x TE TL TU,
            index x envz = Some (TE) ->
            tresolve x TE (TMem TL TU) ->
            wf_type envz (TSel x)

| wf_selb: forall envz x, (* note: disregarding bind-scope *)
             wf_type envz (TSelB x)
| wf_bind: forall envz T,
             wf_type envz T ->
             wf_type envz (TBind T)

.

Tactic Notation "wf_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "Top" |
    Case_aux c "Bool" |
    Case_aux c "And" |
    Case_aux c "MemA" |
    Case_aux c "Mem" |
    Case_aux c "Fun" |
    Case_aux c "Sel" |
    Case_aux x "SelB" |
    Case_aux c "Bind" ].



(* TODO: need to see what to do for expansion / 'has' *)
(*
  x: { z => Tz }
  x: Tx

  x: y.A(L..U)
  x: U
 *)


Inductive stp : bool -> tenv -> ty -> ty -> nat -> Prop := 
  
| stp_bool: forall G1 n1,
    stp true G1 TBool TBool n1

| stp_fun: forall m G1 T11 T12 T21 T22 n1 n2,
    stp false G1 T21 T11 n1 ->
    stp true G1 T12 T22 n2 ->
    stp true G1 (TFun m T11 T12) (TFun m T21 T22) (S (n1+n2))

| stp_mem: forall G1 T11 T12 T21 T22 n1 n2,
    stp false G1 T21 T11 n1 ->
    stp true G1 T12 T22 n2 ->
    stp true G1 (TMem T11 T12) (TMem T21 T22) (S (n1+n2))
        
| stp_sel2: forall x T1 TX G1 n1,
    index x G1 = Some TX ->
    stp true G1 TX (TMem T1 TTop) n1 ->
    stp true G1 T1 (TSel x) (S n1)
| stp_sel1: forall x T2 TX G1 n1,
    index x G1 = Some TX ->
    stp true G1 TX (TMem TBot T2) n1->
    stp true G1 (TSel x) T2 (S n1)
| stp_selx: forall x G1 n1,
    stp true G1 (TSel x) (TSel x) n1
(* TODO!
| stp_bind2: forall f G1 T1 T2 TA2 n1,
    stp true ((f,T1)::G1) T1 T2 n1 ->
    open (length G1) TA2 = T2 ->                
    stp true G1 T1 (TBind TA2) (S n1)
| stp_bind1: forall f G1 T1 T2 TA1 n1,
    stp true ((f,T1)::G1) T1 T2 n1 ->
    open (length G1) TA1 = T1 ->                
    stp true G1 (TBind TA1) T2 (S n1)
... or at least...
| stp_bindx: forall f G1 T1 T2 TA1 TA2 n1,
    stp true ((f,T1)::G1) T1 T2 n1 ->
    open (length G1) TA1 = T1 ->                
    open (length G1) TA2 = T2 ->
    stp true G1 (TBind TA1) (TBind TA2) (S n1)
*)
| stp_transf: forall G1 T1 T2 T3 n1 n2,
    stp true G1 T1 T2 n1 ->
    stp false G1 T2 T3 n2 ->           
    stp false G1 T1 T3 (S (n1+n2))

| stp_wrapf: forall G1 T1 T2 n1,
    stp true G1 T1 T2 n1 ->
    stp false G1 T1 T2 (S n1)       
.


Tactic Notation "stp_cases" tactic(first) ident(c) :=
  first;
  [ 
    Case_aux c "Bool < Bool" |
    Case_aux c "Fun < Fun" |
    Case_aux c "Mem < Mem" |
(*
    Case_aux c "Bind < Bind" |
    Case_aux c "T & ? < T" |
    Case_aux c "? & T < T" |
    Case_aux c "? < ? & ?" |
*)
    Case_aux c "? < Sel" |
    Case_aux c "Sel < ?" |
    Case_aux c "Sel < Sel" |
    Case_aux c "Trans" |
    Case_aux c "Wrap"
  ].


Hint Resolve ex_intro.

Hint Constructors stp.

Definition stpd b G1 T1 T2 := exists n, stp b G1 T1 T2 n.

Hint Unfold stpd.

Ltac ep := match goal with
             | [ |- stp ?M ?G1 ?T1 ?T2 ?N ] => assert (exists (x:nat), stp M G1 T1 T2 x) as EEX
           end.

Ltac eu := match goal with
             | H: stpd _ _ _ _ |- _ => destruct H
(*             | H: exists n: nat ,  _ |- _  =>
               destruct H as [e P] *)
           end.

Lemma stpd_bool: forall G1,
    stpd true G1 TBool TBool.
Proof. intros. exists 0. eauto. Qed.
Lemma stpd_fun: forall m G1 T11 T12 T21 T22,
    stpd false G1 T21 T11 ->
    stpd true G1 T12 T22 ->
    stpd true G1 (TFun m T11 T12) (TFun m T21 T22).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_mem: forall G1 T11 T12 T21 T22,
    stpd false G1 T21 T11 ->
    stpd true G1 T12 T22 ->
    stpd true G1 (TMem T11 T12) (TMem T21 T22).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_sel2: forall x T1 TX G1,
    index x G1 = Some TX ->
    stpd true G1 TX (TMem T1 TTop) ->
    stpd true G1 T1 (TSel x).
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_sel1:  forall x T2 TX G1,
    index x G1 = Some TX ->
    stpd true G1 TX (TMem TBot T2) ->
    stpd true G1 (TSel x) T2.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_selx: forall x G1,
    stpd true G1 (TSel x) (TSel x).
Proof. intros. repeat eu. exists 0. eauto. Qed.
Lemma stpd_transf: forall G1 T1 T2 T3,
    stpd true G1 T1 T2 ->
    stpd false G1 T2 T3 ->           
    stpd false G1 T1 T3.
Proof. intros. repeat eu. eauto. Qed.
Lemma stpd_wrapf: forall G1 T1 T2,
    stpd true G1 T1 T2 ->
    stpd false G1 T1 T2. 
Proof. intros. repeat eu. eauto. Qed.





Ltac index_subst := match goal with
                 | H1: index ?x ?G = ?V1 , H2: index ?x ?G = ?V2 |- _ => rewrite H1 in H2; inversion H2; subst
                 | _ => idtac
               end.

Lemma stp0f_trans: forall n n1 n2 G1 T1 T2 T3,
    stp false G1 T1 T2 n1 ->
    stp false G1 T2 T3 n2 ->
    n1 <= n ->
    stpd false G1 T1 T3.
Proof.
  intros n. induction n.
  - Case "z".
    intros. assert (n1 = 0). omega. subst. inversion H.
  - Case "S n".
    intros. inversion H.
    + eapply stpd_transf. eexists. eapply H2. eapply IHn. eapply H3. eapply H0. omega.
    + eapply stpd_transf. eexists. eapply H2. eexists. eapply H0.
Qed.  

Definition trans_on n1 := 
                      forall  m T1 T2 T3 G1, 
                      stp m G1 T1 T2 n1 ->
                      stpd true G1 T2 T3 ->
                      stpd true G1 T1 T3.
Hint Unfold trans_on.

Definition trans_up n := forall n1, n1 <= n ->
                      trans_on n1.
Hint Unfold trans_up.

Lemma trans_le: forall n n1,
                      trans_up n ->
                      n1 <= n ->
                      trans_on n1
.
Proof. intros. unfold trans_up in H. eapply H. eauto. Qed.


Lemma upd_hit: forall {X} G G' x x' (T:X) T',
              index x G = Some T ->
              update x' T' G = G' ->
              beq_nat x x' = true ->
              index x G' = Some T'.
Proof. admit. Qed.
Lemma upd_miss: forall {X} G G' x x' (T:X) T',
              index x G = Some T ->
              update x' T' G = G' ->
              beq_nat x x' = false ->
              index x G' = Some T.
Proof. admit. Qed.


Lemma stp_narrow: forall m G1 T1 T2 n1,
  stpd m G1 T1 T2 ->
                    
  forall x TX1 TX2 G1',

    index x G1 = Some TX2 ->
    update x TX1 G1 = G1' ->
    stp true G1' TX1 TX2 n1 ->
    trans_on n1 ->

    stpd m G1' T1 T2.  
Proof.
  intros m G1 T1 T2 n1 H. destruct H as [n2 H].
  induction H; intros.
  - Case "Bool". 
    intros. eapply stpd_bool.
  - Case "Fun". 
    intros. eapply stpd_fun. eapply IHstp1; eauto. eapply IHstp2; eauto.
  - Case "Mem". 
    intros. eapply stpd_mem. eapply IHstp1; eauto. eapply IHstp2; eauto.
  - Case "Sel2". intros.
    { case_eq (beq_nat x x0); intros E.
      (* hit updated binding *)
      + assert (x = x0) as EX. eapply beq_nat_true_iff; eauto. subst. index_subst. index_subst. 
        eapply stpd_sel2. eapply upd_hit; eauto. eapply H4. eapply H3. eapply IHstp; eauto.
      (* other binding *)
      + assert (x <> x0) as EX. eapply beq_nat_false_iff; eauto.
        eapply stpd_sel2. eapply upd_miss; eauto. eapply IHstp. eapply H1. eauto. eauto. eauto.
    }
  - Case "Sel1". intros.
    { case_eq (beq_nat x x0); intros E.
      (* hit updated binding *)
      + assert (x = x0) as EX. eapply beq_nat_true_iff; eauto. subst. index_subst. index_subst. 
        eapply stpd_sel1. eapply upd_hit; eauto. eapply H4. eapply H3. eapply IHstp; eauto.
      (* other binding *)
      + assert (x <> x0) as EX. eapply beq_nat_false_iff; eauto.
        eapply stpd_sel1. eapply upd_miss; eauto. eapply IHstp. eapply H1. eauto. eauto. eauto.
    }
  - Case "Selx". eapply stpd_selx.
  - Case "Trans". eapply stpd_transf. eapply IHstp1; eauto. eapply IHstp2; eauto.
  - Case "Wrap". eapply stpd_wrapf. eapply IHstp; eauto.
Qed.


Inductive simple_type: ty -> Prop :=
| simple_mem: forall T1,
  simple_type (TMem T1 T1)  (* otherwise, would need trans_on T1 T2 *)
.                           

(* no induction, no trans (?) *)
(* proper realizability evidence? *)
Lemma stpd_trans_lo: forall G1 T1 T2 TX,
  stpd true G1 T1 T2 ->                     
  stpd true G1 TX (TMem T2 TTop) ->
  simple_type TX ->
  stpd true G1 TX (TMem T1 TTop).
Proof.
  intros. repeat eu. inversion H0; inversion H1.
  - eapply stpd_mem. eapply stpd_transf. eexists. eapply H. eexists. subst. eauto. eauto. 
  - subst. inversion H4. (* NEED TO HANDLE THIS CASE? PROBABLY YES .... *)
Qed.


(* proper realizability evidence? *)
Lemma stpd_trans_hi: forall G1 T1 T2 TX n1,
                       (* trans_on *)
  stpd true G1 T1 T2 ->                     
  stp true G1 TX (TMem TBot T1) n1 ->
  simple_type TX ->
  trans_up n1 ->
  stpd true G1 TX (TMem TBot T2).
Proof.
  intros.
  inversion H1. subst TX.
  inversion H0. subst.
  assert (trans_on n2) as IH. { eapply trans_le; eauto. omega. }
  eapply stpd_mem. eauto. eapply IH; eauto.
Qed.

(* need to invert mem. will require proper realizability
   evidence *)
Lemma stpd_trans_cross: forall G1 TX T1 T2 n1,
                          (* trans_on *)
  stp true G1 TX (TMem T1 TTop) n1 ->
  stpd true G1 TX (TMem TBot T2) ->
  simple_type TX ->
  trans_up n1 ->
  stpd true G1 T1 T2.
Proof.
  intros.
  inversion H1. subst TX.
  inversion H. destruct H0. inversion H0. subst.
  assert (trans_on n0) as IH. { eapply trans_le. eauto. omega. }
  eapply IH. eauto. eexists. eauto.
Qed.


Lemma stp1_trans: forall n, trans_up n.
Proof.
  intros n. induction n.
  Case "z". admit.
  Case "S n".
  unfold trans_up. intros n1 NE  b T1 T2 T3 G1 S12 S23.
  destruct S23 as [n2 S23].

  (* SHOTGUN: construct `simple` evidence out of thin air.
     This needs to become a parameter, but need to figure out
     how to integrate it exactly. *)
  assert (forall x T, index x G1 = Some T -> simple_type T) as IMP. admit.
  
  stp_cases(inversion S12) SCase.  (* stp_cases(inversion S23) SSCase;  subst; *)
  
  - SCase "Bool < Bool". inversion S23; subst; try solve by inversion.
    + SSCase "Bool". eapply stpd_bool; eauto.
    + SSCase "Sel2". eapply stpd_sel2. eauto. eapply stpd_trans_lo; eauto.
  - SCase "Fun < Fun". inversion S23; subst; try solve by inversion.
    + SSCase "Fun". inversion H10. subst.
      eapply stpd_fun.
      * eapply stp0f_trans; eauto.
      * assert (trans_on n3) as IH.
        { eapply trans_le; eauto. omega. }
        eapply IH; eauto.
    + SSCase "Sel2". eapply stpd_sel2. eauto. eapply stpd_trans_lo; eauto.
  - SCase "Mem < Mem". inversion S23; subst; try solve by inversion.
    + SSCase "Mem". inversion H10. subst.
      eapply stpd_mem.
      * eapply stp0f_trans; eauto.
      * assert (trans_on n3) as IH.
        { eapply trans_le; eauto. omega. }
        eapply IH; eauto.
    + SSCase "Sel2". eapply stpd_sel2. eauto. eapply stpd_trans_lo; eauto.
  - SCase "? < Sel". inversion S23; subst; try solve by inversion.
    + SSCase "Sel2". eapply stpd_sel2. eauto. eapply stpd_trans_lo; eauto.
    + SSCase "Sel1". (* interesting case *)
      index_subst.
      assert (trans_up n0) as IH.
      { unfold trans_up. intros. apply IHn. omega. }
      inversion H10. subst. index_subst. eapply stpd_trans_cross; eauto.
    + SSCase "Selx". inversion H8. index_subst. subst. index_subst. subst.
      eapply stpd_sel2. eauto. eauto.
  - SCase "Sel < ?".
      (* TODO: use stpd_trans_hi? *)
      assert (trans_up n0) as IH.
      { unfold trans_up. intros. eapply IHn. omega. }
      eapply stpd_sel1. eauto. eapply stpd_trans_hi; eauto.
  - SCase "Sel < Sel". inversion S23; subst; try solve by inversion.
     + SSCase "Sel2". eapply stpd_sel2. eauto. eapply stpd_trans_lo; eauto.
     + SSCase "Sel1". inversion H8. index_subst. subst. index_subst. subst.
       eapply stpd_sel1. eauto. eauto.
     + SSCase "Selx". inversion H6. subst. repeat index_subst.
       eapply stpd_selx; eauto.
  - SCase "Trans". subst.
    assert (trans_on n3) as IH2.
    { eapply trans_le; eauto. omega. }
    assert (trans_on n0) as IH1.
    { eapply trans_le; eauto. omega. }
    assert (stpd true G1 T4 T3) as S123.
    { eapply IH2; eauto. }
    destruct S123.
    eapply IH1; eauto.
  - SCase "Wrap". subst.
    assert (trans_on n0) as IH.
    { eapply trans_le; eauto. omega. }
    eapply IH; eauto.
Qed.


End DOT.
