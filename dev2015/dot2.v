Require Export SfLib.

Require Export Arith.EqNat.
Require Export Arith.Le.

(* 
type safety for minidot-like calculus:
- branding / undbranding example
- static / dynamic stp relation
- no self types at the moment
*)


(* syntax *)

Module DOT.

Definition id := nat.


Inductive ty : Type :=
  | TTop   : ty
  | TBool  : ty
  | TAnd   : ty -> ty -> ty
  | TFun   : id -> ty -> ty -> ty
  | TMem   : (option ty) -> ty
  | TSel   : id -> ty
.
  

Definition TArrow p x y := TAnd (TMem p) (TAnd (TFun 0 x y) TTop).


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


Inductive vl : Type :=
| vbool : bool -> vl
| vabs  : list (id*vl) -> id -> ty -> list (id * dc) -> vl. (* clos env f:T = x => y *)


Fixpoint length {X: Type} (l : list X): nat :=
  match l with
    | [] => 0
    | _::l' => 1 + length l'
  end.

Fixpoint index {X : Type} (n : nat)
               (l : list (nat * X)) : option X :=
  match l with
    | [] => None
    (* for now, ignore binding value n' !!! *)
    | (n',a) :: l'  => if beq_nat n (length l') then Some a else index n l'
  end.


Definition env := list (nat*vl).
Definition tenv := list (nat*ty).



Fixpoint dc_type_and (dcs: list(nat*dc)) :=
  match dcs with
    | nil => TTop
    | (n, dfun T1 T2 _ _)::dcs =>
      TAnd (TFun (length dcs) T1 T2)  (dc_type_and dcs)
  end.


Definition TObj p dcs := TAnd (TMem p) (dc_type_and dcs).




(* get the canonical type and internal env from an
   object in a runtime environment *)
Definition resolve e n: option (env * ty) :=
  match (index n e) with
    | Some(v) =>
      match v with
        | vabs GC f TC dcs =>
            Some ((f,v)::GC,(TObj (Some TC) dcs))
        | vbool b => Some (nil,TBool)
      end
    | _ => None
  end.

(* static type expansion.
   needs to imply dynamic subtyping. *)
Inductive tresolve: ty -> ty -> Prop :=
  | tr_self: forall T,
             tresolve T T
  | tr_and1: forall T1 T2 T,
             tresolve T1 T ->
             tresolve (TAnd T1 T2) T
  | tr_and2: forall T1 T2 T,
             tresolve T2 T ->
             tresolve (TAnd T1 T2) T
.                      

Tactic Notation "tresolve_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "Self" |
    Case_aux c "And1" |
    Case_aux c "And2" ].


(* static type well-formedness.
   needs to imply dynamic subtyping. *)
Inductive wf_type : tenv -> ty -> Prop :=
| wf_top: forall env,
    wf_type env TTop
| wf_bool: forall env,
    wf_type env TBool
| wf_and: forall env T1 T2,
             wf_type env T1 ->
             wf_type env T2 ->
             wf_type env (TAnd T1 T2)
| wf_mema: forall env,
             wf_type env (TMem None) 
| wf_mem: forall env TA,
             wf_type env TA ->
             wf_type env (TMem (Some TA))
| wf_fun: forall env f T1 T2,
             wf_type env T1 ->
             wf_type env T2 ->
             wf_type env (TFun f T1 T2)
                     
| wf_sel: forall envz x TE TA,
            index x envz = Some (TE) ->
            tresolve TE (TMem TA) ->
            wf_type envz (TSel x)
.

Tactic Notation "wf_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "Top" |
    Case_aux c "Bool" |
    Case_aux c "And" |
    Case_aux c "MemA" |
    Case_aux c "Mem" |
    Case_aux c "Fun" |
    Case_aux c "Sel" ].



(* static subtyping: during type checking/assignment. 
   needs to imply dynamic subtyping *)
Inductive atp: tenv -> ty -> ty -> Prop :=
| atp_sel2: forall x env T TF,
    index x env = Some TF ->
    tresolve TF (TMem (Some T)) ->
    atp env T (TSel x)
| atp_sel1: forall x env T TF,
    index x env = Some TF ->
    tresolve TF (TMem (Some T)) ->
    atp env (TSel x) T
.

Tactic Notation "atp_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "? < Sel" | Case_aux c "Sel < ?" ].


(* impossible subtyping cases, uses for contradictions *)
Inductive nostp: ty -> ty -> Prop :=
| nostp_top_fun: forall m T1 T2,
   nostp TTop (TFun m T1 T2)
| nostp_top_mem: forall TA,
   nostp TTop (TMem TA)
| nostp_fun: forall T1 T2 T3 T4 n1 n2,
   not (n1 = n2) ->
   nostp (TFun n1 T1 T2) (TFun n2 T3 T4)
| nostp_fun_mem: forall m TA T1 T2,
   nostp (TMem TA) (TFun m T1 T2)
| nostp_mem_fun: forall m TA T1 T2,
   nostp (TFun m T1 T2) (TMem TA)
| nostp_and: forall T1 T2 T,
    nostp T1 T ->
    nostp T2 T ->
    nostp (TAnd T1 T2) T
.

Hint Constructors nostp.


(* dynamic subtyping: during execution *)
Inductive stp : nat -> env -> ty -> env -> ty -> Prop :=
| stp_top: forall n1 G1 G2,
    stp n1 G1 TTop G2 TTop (* don't want to deal with it now *)
  
| stp_bool: forall n1 G1 G2,
    stp n1 G1 TBool G2 TBool

| stp_fun: forall n1 n2 m G1 G2 T11 T12 T21 T22,
    stp n1 G2 T21 G1 T11 ->
    stp n2 G1 T12 G2 T22 ->
    stp (S (n1+n2)) G1 (TFun m T11 T12) G2 (TFun m T21 T22)
        
        
| stp_mem_ss: forall n1 n2 G1 G2 TA1 TA2,
    stp n1 G1 TA1 G2 TA2 ->
    stp n2 G2 TA2 G1 TA1 ->
    stp (S (n1+n2)) G1 (TMem (Some TA1)) G2 (TMem (Some TA2))
| stp_mema_sn: forall n1 G1 G2 TA,
    stp n1 G1 TA G1 TA -> (* regularity *)
    stp (S (n1+n1)) G1 (TMem (Some TA)) G2 (TMem None)
| stp_mema_nn: forall n1 G1 G2,
    stp n1 G1 (TMem None) G2 (TMem None)

        
| stp_and11: forall n1 n2 G1 G2 T1 T2 T,
    stp n1 G1 T1 G2 T ->
    stp n2 G1 T2 G1 T2 -> (* regularity *)
    stp (S (n1+n2)) G1 (TAnd T1 T2) G2 T
| stp_and12: forall n1 n2 G1 G2 T1 T2 T,
    stp n1 G1 T2 G2 T ->
    stp n2 G1 T1 G1 T1 -> (* regularity *)
    stp (S (n1+n2)) G1 (TAnd T1 T2) G2 T
| stp_and2: forall n1 n2 G1 G2 T1 T2 T,
    stp n1 G1 T G2 T1 ->
    stp n2 G1 T G2 T2 ->
    stp (S (n1+n2)) G1 T G2 (TAnd T1 T2)
        
| stp_sel2: forall n2 f x dcs T1 TA G1 G2 GC,
    index x G2 = Some (vabs GC f TA dcs) ->
    stp n2 G1 T1 ((f,vabs GC f TA dcs)::GC) TA ->
    stp (S n2) G1 T1 G2 (TSel x)
| stp_sel1: forall n2 f x dcs TA T2 G1 G2 GC,
    index x G1 = Some (vabs GC f TA dcs) ->
    stp n2 ((f,vabs GC f TA dcs)::GC) TA G2 T2 ->
    stp (S n2) G1 (TSel x) G2 T2
| stp_selx: forall n1 x1 x2 v G1 G2,
    (*    resolve G1 x = Some (GC,TC) -> *)
    (* don't need TC? but shouldn't we know it's a closure? *)
    index x1 G1 = Some v ->
    index x2 G2 = Some v ->
    stp n1 G1 (TSel x1) G2 (TSel x2)
.

Tactic Notation "stp_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "Top < Top" |
    Case_aux c "Bool < Bool" |
    Case_aux c "Fun < Fun" |
    Case_aux c "Mem Some < Mem Some" |
    Case_aux c "Mem Some < Mem None" |
    Case_aux c "Mem None < Mem None" |
    Case_aux c "T & ? < T" |
    Case_aux c "? & T < T" |
    Case_aux c "? < ? & ?" |
    Case_aux c "? < Sel" |
    Case_aux c "Sel < ?" |
    Case_aux c "Sel < Sel" ].

Definition stpd G1 T1 G2 T2 := exists n, stp n G1 T1 G2 T2.



(* INVERSION CASES *)

Lemma stp_mem_invA: forall G1 G2 TA1 TA2,
    stpd G1 (TMem (Some TA1)) G2 (TMem (Some TA2)) ->
    stpd G1 TA1 G2 TA2.
Proof. intros. destruct H. inversion H. eexists. eauto. Qed.

Lemma stp_mem_invB: forall G1 G2 TA1 TA2,
    stpd G1 (TMem (Some TA1)) G2 (TMem (Some TA2)) ->
    stpd G2 TA2 G1 TA1.
Proof. intros. destruct H. inversion H. eexists. eauto. Qed.

        
Lemma stp_funA: forall m G1 G2 T11 T12 T21 T22,
    stpd G1 (TFun m T11 T12) G2 (TFun m T21 T22) ->
    stpd G2 T21 G1 T11.
Proof. intros. destruct H. inversion H. eexists. eauto. Qed.
Lemma stp_funB: forall m G1 G2 T11 T12 T21 T22,
    stpd G1 (TFun m T11 T12) G2 (TFun m T21 T22) ->
    stpd G1 T12 G2 T22.
Proof. intros. destruct H. inversion H. eexists. eauto. Qed.

(* invert `and` if one branch is impossible *)
Lemma nostp_no_rhs_and: forall T1 T2 T,
      nostp T (TAnd T1 T2) ->
      False.
Proof. intros. remember (TAnd T1 T2). induction H; inversion Heqt.
       eauto.
Qed.
Lemma nostp_no_rhs_sel: forall T x,
      nostp T (TSel x) ->
      False.
Proof. intros. remember (TSel x). induction H; inversion Heqt.
       eauto.
Qed.

Hint Resolve ex_intro.

Lemma stp_contra: forall T1 T2 G1 G2,
      nostp T1 T2 ->
      stpd G1 T1 G2 T2 ->
      False.
Proof. intros. induction H; destruct H0 as [n H0]; inversion H0; subst; eauto.
       eapply IHnostp1. eexists. eauto.
       eapply IHnostp2. eexists. eauto.
       eapply nostp_no_rhs_and. eauto. 
       eapply nostp_no_rhs_sel. eauto. 
Qed.
       
Lemma stp_andA: forall G1 G2 T1 T2 T,
    stpd G1 (TAnd T1 T2) G2 T ->
    nostp T2 T ->          
    stpd G1 T1 G2 T.
Proof. intros. destruct H. inversion H.
       subst. eexists. eauto. 
       eapply stp_contra in H0. contradiction. exists n1. eauto.
       subst. eapply nostp_no_rhs_and in H0. contradiction.
       subst. eapply nostp_no_rhs_sel in H0. contradiction.
Qed.
Lemma stp_andB: forall G1 G2 T1 T2 T,
    stpd G1 (TAnd T1 T2) G2 T ->
    nostp T1 T ->           
    stpd G1 T2 G2 T.
Proof. intros. destruct H. inversion H.
       eapply stp_contra in H0. contradiction. exists n1. eauto.
       subst. eexists. eauto.
       subst. eapply nostp_no_rhs_and in H0. contradiction.
       subst. eapply nostp_no_rhs_sel in H0. contradiction.
Qed.

Lemma stp_and2A: forall G1 G2 T1 T2 T,
    stpd G1 T G2 (TAnd T1 T2) ->
    stpd G1 T G2 T1.
Proof. intros. remember (TAnd T1 T2). destruct H. induction H; inversion Heqt.
       eapply IHstp1 in H1. destruct H1.
       eexists. eapply stp_and11. eauto. eauto.
       eapply IHstp1 in H1. destruct H1.
       eexists. eapply stp_and12. eauto. eauto.
       subst. eexists. eauto.
       eapply IHstp in H1. destruct H1.
       subst. eexists. eapply stp_sel1. eauto. eauto.
Qed.

Lemma stp_and2B: forall G1 G2 T1 T2 T,
    stpd G1 T G2 (TAnd T1 T2) ->
    stpd G1 T G2 T2.
Proof. intros. remember (TAnd T1 T2). destruct H. induction H; inversion Heqt.
       eapply IHstp1 in H1. destruct H1.
       eexists. eapply stp_and11. eauto. eauto.
       eapply IHstp1 in H1. destruct H1.
       eexists. eapply stp_and12. eauto. eauto.
       subst. eexists. eauto.
       eapply IHstp in H1. destruct H1.
       subst. eexists. eapply stp_sel1. eauto. eauto.
Qed.


(* EXTENSION *)

Hint Constructors stp.

Lemma index_extend : forall X n G1 x v (T:X),
    index n G1 = Some T ->
    index n((x,v)::G1) = Some T.
Proof. admit. Qed. (* proof below *)

Hint Resolve index_extend.

Lemma resolve_extend : forall n x v G1 GC TC,
    resolve G1 n = Some (GC,TC) ->
    resolve ((x,v)::G1) n = Some (GC,TC).
Proof. intros. unfold resolve in H. remember (index n G1). destruct o. symmetry in Heqo.
       assert (index n ((x,v)::G1) = Some v0). eapply index_extend; eauto.
       remember (resolve ((x,v)::G1) n). unfold resolve in Heqo0. rewrite H0 in Heqo0.
       rewrite H in Heqo0. eauto.
       inversion H.
Qed.

Hint Resolve resolve_extend.
       
Lemma stp_extend : forall SF G1 G2 T1 T2 x v,
    stp SF G1 T1 G2 T2 ->
    stp SF ((x,v)::G1) T1 G2 T2 /\
    stp SF G1 T1 ((x,v)::G2) T2 /\
    stp SF ((x,v)::G1) T1 ((x,v)::G2) T2.
Proof. intros. stp_cases (induction H) Case;
         try inversion IHstp as [IH_1 [IH_2 IH_12]];
         try inversion IHstp1 as [IH1_1 [IH1_2 IH1_12]];
         try inversion IHstp2 as [IH2_1 [IH2_2 IH2_12]];
         split; try solve [eauto; constructor; eauto].
Qed.

Lemma stp_extend1 : forall SF G1 G2 T1 T2 x v,
    stp SF G1 T1 G2 T2 ->
    stp SF ((x,v)::G1) T1 G2 T2.
Proof. intros. eapply stp_extend. eauto. Qed.

Lemma stp_extend2 : forall SF G1 G2 T1 T2 x v,
    stp SF G1 T1 G2 T2 ->
    stp SF G1 T1 ((x,v)::G2) T2.
Proof. intros. eapply stp_extend. eauto. Qed.


(* REGULARITY *)

Lemma stp_reg : forall G1 G2 T1 T2,
    stpd G1 T1 G2 T2 ->
    stpd G1 T1 G1 T1 /\ stpd G2 T2 G2 T2.
Proof. intros. destruct H. stp_cases (induction H) Case;
         try inversion IHstp as [[IH_n1 IH_1] [IH_n2 IH_2]];
         try inversion IHstp1 as [[IH_n1 IH_1] [IH_n2 IH_2]];
         try inversion IHstp2 as [[IH_n3 IH_3] [IH_n4 IH_4]];
         split;
         try solve [exists 0; eauto];
         try solve [eexists; eauto].
Qed.


Lemma stp_reg1 : forall G1 G2 T1 T2,
    stpd G1 T1 G2 T2 ->
    stpd G1 T1 G1 T1.
Proof. intros. eapply stp_reg in H. inversion H. eauto. Qed.

Lemma stp_reg2 : forall G1 G2 T1 T2,
    stpd G1 T1 G2 T2 ->
    stpd G2 T2 G2 T2.
Proof. intros. eapply stp_reg in H. inversion H. eauto. Qed.

(* HELPERS: these mirror stp_X cases, but for stpd (too lazy to fill in) *)

Lemma stpd_sel2: forall G1 T1 G2 GC TA f x dcs,
                      index x G2 = Some(vabs GC f TA dcs) ->
                      stpd G1 T1 ((f,vabs GC f TA dcs)::GC) TA ->
                      stpd G1 T1 G2 (TSel x)
.
Proof. admit. Qed.


Lemma stpd_sel1: forall G1 GC TA T2 G2 f x dcs,
                      index x G1 = Some(vabs GC f TA dcs) ->
                      stpd ((f,vabs GC f TA dcs)::GC) TA G2 T2 ->
                      stpd G1 (TSel x) G2 T2
.
Proof. admit. Qed.


Lemma stpd_and11: forall G1 G2 T1 T2 T,
                      stpd G1 T1 G2 T ->
                      stpd G1 T2 G1 T2 ->
                      stpd G1 (TAnd T1 T2) G2 T
.
Proof. admit. Qed.

Lemma stpd_and12: forall G1 G2 T1 T2 T,
                      stpd G1 T2 G2 T ->
                      stpd G1 T1 G1 T1 ->
                      stpd G1 (TAnd T1 T2) G2 T
.
Proof. admit. Qed.


Lemma stpd_and2: forall G1 G2 T1 T2 T,
                      stpd G1 T G2 T1 ->
                      stpd G1 T G2 T2 ->
                      stpd G1 T G2 (TAnd T1 T2)
.
Proof. admit. Qed.

Lemma stpd_fun:  forall m G1 G2 T11 T12 T21 T22,
    stpd G2 T21 G1 T11 ->
    stpd G1 T12 G2 T22 ->
    stpd G1 (TFun m T11 T12) G2 (TFun m T21 T22)
.
Proof. admit. Qed.

Lemma stpd_mem_ss: forall G1 G2 TA1 TA2,
    stpd G1 TA1 G2 TA2 ->
    stpd G2 TA2 G1 TA1 ->
    stpd G1 (TMem (Some TA1)) G2 (TMem (Some TA2)).
Proof. admit. Qed.

Lemma stpd_mema_sn: forall G1 G2 TA,
    stpd G1 TA G1 TA -> (* regularity *)
    stpd G1 (TMem (Some TA)) G2 (TMem None).
Proof. admit. Qed.

Lemma stpd_mema_nn: forall G1 G2,
    stpd G1 (TMem None) G2 (TMem None).
Proof. admit. Qed.


(* TRANSITIVITY *)

Definition trans_on n12 n23 := 
                      forall  T1 T2 T3 G1 G2 G3, 
                      stp n12 G1 T1 G2 T2 ->
                      stp n23 G2 T2 G3 T3 ->
                      stpd G1 T1 G3 T3.
Hint Unfold trans_on.

Definition trans_up n := forall n12 n23, n12 + n23 <= n ->
                      trans_on n12 n23.
Hint Unfold trans_up.

Lemma trans_le: forall n n1 n2,
                      trans_up n ->
                      n1 + n2 <= n ->
                      trans_on n1 n2
.
Proof. intros. unfold trans_up in H. eapply H. eauto. Qed.


Lemma nostp_inv_dcs_mem: forall dcs TA, (* not needed? *)
  nostp (dc_type_and dcs) (TMem TA).
Proof.
  intros.
  induction dcs.
  Case "nil". eauto.
  Case "cons".
    unfold dc_type_and. destruct a. destruct d.
    eapply nostp_and.
      eapply nostp_mem_fun.
      eapply IHdcs.
Qed.



Lemma stp_trans: forall n, trans_up n.
Proof. intros n.
       induction n.
       Case "z".
       unfold trans_up. unfold trans_on.
       intros.
       assert (n12 = 0). omega. assert (n23 = 0). omega. subst.
       inversion H0; inversion H1; subst;
       try solve [inversion H0];
       try solve [inversion H1];
       try solve [exists 0; eauto].

       SCase "Sel < Sel".
       inversion H13. subst. rewrite H3 in H9. inversion H9. subst.
       subst. exists 0. eapply stp_selx. eauto. eauto.

       Case "S n".
       unfold trans_up. intros n12 n23 NE   T1 T2 T3 G1 G2 G3    S12 S23.

       (* case analysis takes a long time! >= 144 cases to start with *)
       stp_cases(inversion S12) SCase;  stp_cases(inversion S23) SSCase;  subst;

       try solve [SSCase "? < Sel";
         eapply stpd_sel2; [eauto | eapply trans_le in IHn; [ eapply IHn; eauto | omega ]]];

       try solve [SCase "Sel < ?";
         eapply stpd_sel1; [eauto |  eapply trans_le in IHn; [ eapply IHn; eauto | omega ]]];

       try solve [SSCase "? < ? & ?";
         eapply stpd_and2; [ eapply trans_le in IHn; [ eapply IHn; eauto | omega] |
                             eapply trans_le in IHn; [ eapply IHn; eauto | omega]]];

       try solve [SCase "T & ? < T";
         eapply stpd_and11; [ eapply trans_le in IHn; [ eapply IHn; eauto | omega] | eexists; eauto]];

       try solve [SCase "? & T < T";
         eapply stpd_and12; [ eapply trans_le in IHn; [ eapply IHn; eauto | omega] | eexists; eauto]];


       try solve [exists 0; eauto];
       try solve by inversion;
       idtac. 

       try solve [SSCase "? < Sel";
         eapply stpd_sel2; [eauto | eapply trans_le in IHn; [ eapply IHn; eauto | omega ]]].
       
(*
       SCase "Bool < Bool". SSCase "Bool < Bool".
       eapply ex_intro with 0. eapply stp_bool.
*)

       SCase "Fun < Fun". SSCase "Fun < Fun". inversion H10. subst.
       eapply stpd_fun. eapply trans_le in IHn. eapply IHn. eauto. eauto. omega.
                        eapply trans_le in IHn. eapply IHn. eauto. eauto. omega.

       SCase "Mem Some < Mem Some". SSCase "Mem Some < Mem Some". inversion H10. subst.
       eapply stpd_mem_ss. eapply trans_le in IHn. eapply IHn. eauto. eauto. omega.
                           eapply trans_le in IHn. eapply IHn. eauto. eauto. omega.

       SCase "Mem Some < Mem Some". SSCase "Mem Some < Mem None". inversion H9. subst.
       eapply stpd_mema_sn. eapply trans_le in IHn. eapply IHn. eauto. eauto. omega.

       SCase "Mem Some < Mem None". SSCase "Mem None < Mem None". 
       eapply stpd_mema_sn. eapply trans_le in IHn. eapply IHn. eauto. eauto. omega.
                           
       SCase "? < ? & ?". SSCase "T & ? < T". inversion H10. subst.
       eapply trans_le in IHn. eapply IHn. apply H. apply H6. omega.

       SCase "? < ? & ?". SSCase "? & T < T". inversion H10. subst.
       eapply trans_le in IHn. eapply IHn. apply H0. apply H6. omega.

       SCase "? < Sel". SSCase "Sel < ?". (* proper mid *)
       assert (trans_on n2 n0) as IHX. eapply trans_le; [ eauto | omega ].
       inversion H10. subst x0. rewrite H in H6. inversion H6. subst.
       eapply IHX. apply H0. apply H7.
       
       SCase "? < Sel". SSCase "Sel < Sel".
       inversion H10. subst x1. rewrite H in H6. inversion H6. subst.
       eapply stpd_sel2. eauto. eexists. eapply H0. 

       SCase "Sel < Sel". SSCase "Sel < ?".
       inversion H10. subst x2. rewrite H0 in H6. inversion H6. subst.
       eapply stpd_sel1. eauto. eexists. eapply H7.

       SCase "Sel < Sel". SSCase "Sel < Sel".
       exists 0. eapply stp_selx. eauto. eauto.  inversion H10. subst.
         rewrite H0 in H6. inversion H6. subst. eapply H7.
Qed.




Lemma stpd_trans: forall G1 G2 G3 T1 T2 T3,
    stpd G1 T1 G2 T2 ->
    stpd G2 T2 G3 T3 ->
    stpd G1 T1 G3 T3.
Proof. intros.
    destruct H. destruct H0. eapply (stp_trans (x+x0) x x0). eauto. eapply H. eapply H0.
Qed.




Inductive has_type : list (nat*ty) -> tm -> ty -> Prop :=
| t_true: forall env,
           has_type env ttrue TBool
| t_false: forall env,
           has_type env tfalse TBool
| t_var: forall n (env:list (nat*ty)) t1,
           index n env = Some t1 ->
           wf_type env t1 ->
           has_type env (tvar n) t1
| t_vara: forall n env T T2,
           index n env = Some T ->
           atp env T T2 -> 
           wf_type env T2 ->
           has_type env (tvar n) T2

(*
| t_var_pack: forall n env T T2,
           index n env = Some T ->
           wf_type env T ->
           has_type env (tvar n) (TBind n T)
*)

| t_app: forall env f m x TF T1 T2,
           index f env = Some TF ->
           tresolve TF (TFun m T1 T2) ->
           wf_type env T1 ->
           wf_type env T2 ->
           has_type env x T1 ->
           has_type env (tapp f m x) T2
| t_abs: forall env TF TFN f z dcs TA T3,
           TF  = (TObj (Some TA) dcs) ->
           TFN = (TObj None      dcs) ->

           dc_has_type ((f,TF)::env) dcs ->

           has_type ((f,TFN)::env) z T3 -> 

           wf_type ((f,TF)::env) TF ->
           wf_type env T3 ->
           has_type env (tabs f TA dcs z) T3
| t_let: forall env x y z T1 T3,
           has_type env y T1 ->
           has_type ((x,T1)::env) z T3 -> 
           wf_type env T3 ->
           has_type env (tlet x T1 y z) T3

 with dc_has_type: list(nat * ty) -> list (nat*dc) -> Prop :=
      | dt_fun: forall env x y m T1 T2 dcs,
          has_type ((x,T1)::env) y T2 ->
          dc_has_type env dcs ->
          m = length dcs ->
          dc_has_type env ((m, dfun T1 T2 x y)::dcs)
      | dt_nil: forall env,
           dc_has_type env nil
.

Inductive wf_env : list (nat*vl) -> list (nat*ty) -> Prop := 
| wfe_nil : wf_env nil nil
| wfe_cons : forall n v t vs ts,
     val_type ((n,v)::vs) v t -> wf_env vs ts -> wf_env (cons (n,v) vs) (cons (n,t) ts)                                    

with val_type : env -> vl -> ty -> Prop :=
| v_bool: forall venv b T,
    stpd nil TBool venv T ->
    val_type venv (vbool b) T
| v_abs: forall env venv tenv TW TF f dcs TA,
    TF  = (TObj (Some TA) dcs) ->
    
    dc_has_type ((f,TF)::tenv) dcs ->

    wf_env env tenv ->
    wf_type ((f,TF)::tenv) TF ->
    stpd ((f,(vabs env f TA dcs))::env) TF venv TW ->
    val_type venv (vabs env f TA dcs) TW
.


(* could use do-notation to clean up syntax *)
Fixpoint teval(n: nat)(env: env)(t: tm){struct n}: option (option vl) :=
  match n with
    | 0 => None
    | S n =>
      match t with
        | ttrue  => Some (Some (vbool true))
        | tfalse => Some (Some (vbool false))
        | tvar x => Some (index x env)
        | tabs f T dcs z =>
          teval n ((f,vabs env f T dcs)::env) z
        | tapp x m ex =>
                  match teval n env ex with
                    | None => None
                    | Some None => Some None
                    | Some (Some vx) =>
          match index x env with
            | None => Some(None)
            | Some (vbool _) => Some(None)
            | Some (vabs env2 f T dcs) =>
              match index m dcs with
                | None => Some(None)
                | Some (dfun T1 T2 x ey) =>
                      teval n ((x,vx)::(f,vabs env2 f T dcs)::env2) ey
                  end
              end
          end
        | tlet x T1 y z =>
          match teval n env y with
            | None => None
            | Some None => Some None
            | Some (Some vx) =>
              teval n ((x,vx)::env) z
          end
      end
  end.

Inductive eval : env -> tm -> option vl -> Prop :=
| e_true: forall env, 
    eval env ttrue (Some (vbool true))
| e_false: forall env, 
    eval env tfalse (Some (vbool false))
| e_var: forall n (env:list (nat*vl)) v1,
    index n env = Some v1 ->
    eval env (tvar n) (Some v1)
| e_app: forall env env2 T T1 T2 n m f x ey ex vx rvy dcs,
    index n env = Some (vabs env2 f T dcs) ->
    index m dcs = Some (dfun T1 T2 x ey) -> 
    eval env ex (Some vx) -> 
    eval ((x,vx)::(f,vabs env2 f T dcs)::env2) ey rvy ->
    eval env (tapp n m ex) rvy
| e_abs: forall env f T dcs z rvz,
    eval ((f,vabs env f T dcs)::env) z rvz ->  
    eval env (tabs f T dcs z) rvz.





Hint Constructors ty.
Hint Constructors tm.
Hint Constructors vl.


Hint Constructors eval.
Hint Constructors has_type.
Hint Constructors val_type.
Hint Constructors wf_env.

Hint Constructors wf_type.
Hint Constructors stp.

Hint Constructors atp.
Hint Constructors dc_has_type.

Hint Unfold stpd.

Hint Constructors option.
Hint Constructors list.

Hint Unfold index.
Hint Unfold length.
Hint Unfold resolve.

Hint Constructors tresolve.



Hint Resolve ex_intro.

Require Import LibTactics.

Require Import Coq.Program.Equality.
Require Import Coq.Classes.Equivalence.
Require Import Coq.Classes.EquivDec.
Require Import Coq.Logic.Decidable.


(* examples *)

Definition TNat := TBool.

Definition f := 0. (*(Id 10).*)
Hint Unfold f.

Definition x := 1. (*(Id 0).*)
Definition y := 2. (*(Id 1).*)
Definition z := 3. (*(Id 2).*)
Hint Unfold x.
Hint Unfold y.
Hint Unfold z.

Definition t01 := (TArrow (Some TNat) TNat TNat).
Definition t11 := (TArrow None TNat TNat).
Definition t02 := (TArrow (Some TNat) (TSel f) (TSel f)).
Definition t12 := (TArrow None (TSel f) (TSel f)).

Hint Unfold t01.
Hint Unfold t11.
Hint Unfold t02.
Hint Unfold t12.

Definition idx (i:nat) a b := (i, dfun a b x (tvar x)).


Fixpoint tnew i t d z := tabs i t d z.

Example xx1 : eval nil ttrue (Some (vbool true)) .
Proof. eauto. Qed.

Example ev2 : eval nil
   (tnew f TNat [idx 0 TNat TNat] (tvar f))
   (Some (vabs nil f TNat [idx 0 TNat TNat])).
Proof.
  repeat (econstructor; eauto).
Qed.



Example tp2 : has_type nil
   (tabs f TNat [idx 0 TNat TNat] (tvar f))
   t11. (* want t11 here! *)
Proof.
  repeat (econstructor; compute; eauto).
Qed.

(*
let f: { A = Nat; Nat => Nat } = x => x
let x: { A; Nat => Nat } = f
let y: Nat = x(7)
true
*)
Example tp3 : has_type nil
   (tabs f TNat [idx 0 TNat TNat]
     (tlet x t11 (tvar f) (* abstract type mem *)
        ttrue))
   TBool.
Proof.
  repeat (econstructor; eauto).
Qed.


(* Hint Extern 1 (_ = _) => abstract compute. *)


Hint Constructors has_type.
Hint Constructors dc_has_type.

Hint Unfold idx.
Hint Unfold dc_type_and.

(*
match goal with
        | |- has_type _ (tvar _) _ =>
          try solve [apply t_vara;
                      repeat (econstructor; eauto)]
          | _ => idtac
      end;
*)

Ltac crush_has_tp :=
  try solve [econstructor; compute; eauto; crush_has_tp];
  try (eapply t_vara; compute; eauto; crush_has_tp).

(*
let f: { A = Nat; Nat => f.A } = x => x
true
*)
Example tp4 : has_type nil
   (tabs f TNat [idx 0 TNat (TSel f)]
        ttrue)
   TBool.
Proof.
  crush_has_tp.
Qed.

(*
let f: { A = Nat; Nat => f.A } = x => x
let x: { A; Nat => f.A } = f
true
*)
Example tp5 : has_type nil
   (tabs f TNat [idx 0 TNat (TSel f)]
     (tlet x (TArrow None TNat (TSel f)) (tvar f) (* abstract type mem *)
        ttrue))
   TBool.
Proof.
  crush_has_tp.
Qed.

(*
BRANDING
let f: { A = Nat; Nat => f.A } = x => x
let x: { A; Nat => f.A } = f
let y: f.A = x(7)
true
*)
Example tp6 : has_type nil
   (tabs f TNat [idx 0 TNat (TSel f)]
     (tlet x (TArrow None TNat (TSel f)) (tvar f) (* abstract type mem *)
        (tlet y (TSel f) (tapp x 0 ttrue)
           ttrue)))
   TBool.
Proof.
  crush_has_tp.
Qed.


(*
UNBRANDING
let f: { A = Nat; Nat => f.A ; f.A => Nat } = x => x ; x => x
let x: Nat = 7
let y: f.A = f.0(x) // intro
let z: Nat = f.1(y) // elim
z
*)
Example tp7 : has_type nil
   (tabs f TNat [idx 1 (TSel f) TNat; idx 0 TNat (TSel f)]
     (tlet x (TBool) (ttrue) 
       (tlet y (TSel f) (tapp f 0 (tvar x)) (* call intro *)
         (tlet z TNat (tapp f 1 (tvar y))   (* call elim *)
           (tvar z)))))
   TBool.
Proof.
  crush_has_tp.
Qed.


(*
branding/unbranding needs two methods

val a = new {
  type A = Nat
  def intro(x:Nat): a.A = x
  def elim(x:a.A): Nat = x 
} // type A abstract outside

val x: a.A = a.intro(7)
val y: Nat = a.elim(x)

val z: a.A = 7 // fail
val u: Nat = x // fail 

*)





Lemma index_max : forall X vs n (T: X),
                       index n vs = Some T ->
                       n < length vs.
Proof.
  intros X vs. induction vs.
  Case "nil". intros. inversion H.
  Case "cons".
  intros. inversion H. destruct a.
  case_eq (beq_nat n (length vs)); intros E.
  SCase "hit".
  rewrite E in H1. inversion H1. subst.
  eapply beq_nat_true in E. 
  unfold length. unfold length in E. rewrite E. eauto.
  SCase "miss".
  rewrite E in H1.
  assert (n < length vs). eapply IHvs. apply H1.
  compute. eauto.
Qed.

  
Lemma index_extend1 : forall X vs n a (T: X),
                       index n vs = Some T ->
                       index n (a::vs) = Some T.

Proof.
  intros.
  assert (n < length vs). eapply index_max. eauto.
  assert (n <> length vs). omega.
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff; eauto.
  unfold index. unfold index in H. rewrite H. rewrite E. destruct a. reflexivity.
Qed.


Hint Resolve index_extend.


Lemma wft_extend : forall vs x v1 T,
                       wf_type vs T ->
                       wf_type ((x,v1)::vs) T.
Proof. intros. induction H; eauto.  Qed.

Hint Resolve wft_extend.


Lemma stpd_extend1 : forall G1 G2 T1 T2 x v,
                       stpd G1 T1 G2 T2 ->
                       stpd ((x,v)::G1) T1 G2 T2.
Proof. intros. destruct H. eexists. eapply stp_extend1. apply H. Qed.

Hint Resolve stp_extend1.

Lemma stpd_extend2 : forall G1 G2 T1 T2 x v,
                       stpd G1 T1 G2 T2 ->
                       stpd G1 T1 ((x,v)::G2) T2.
Proof. intros. destruct H. eexists. eapply stp_extend2. apply H. Qed.

Hint Resolve stp_extend2.




(* used in abs preservation case *)
Lemma stpd_mem_abs : forall G1 TA dcs,
                      stpd G1 (TObj (Some TA) dcs) G1 (TObj (Some TA) dcs)  ->
                      stpd G1 (TObj (Some TA) dcs) G1 (TObj None dcs).
Proof.

  intros. unfold TObj. unfold TObj in H.

  eapply stpd_and2. eapply stpd_and11. eapply stpd_mema_sn.
    admit. (* TODO: TA < TA regularity *)
    admit. (* TODO: dcs < dcs regularity *)
    eapply stp_and2B. apply H.
Qed.


Hint Resolve stpd_extend2.

Lemma valtp_extend : forall vs x v v1 T,
                       val_type vs v T ->
                       val_type ((x,v1)::vs) v T.
Proof. intros. induction H; eauto. Qed.

Lemma valtp_widen: forall G1 G2 T1 T2 v,
                     val_type G1 v T1 ->
                     stpd G1 T1 G2 T2 ->
                     val_type G2 v T2.
Proof.
  intros. induction H.
    Case "Bool". eapply v_bool. eapply stpd_trans; eauto.
    Case "Abs". eapply v_abs. eauto. eauto. eauto. eauto. eapply stpd_trans; eauto.
Qed.




Lemma wf_length : forall vs ts,
                    wf_env vs ts ->
                    (length vs = length ts).
Proof. intros. induction H. auto.
assert ((length ((n,v)::vs)) = 1 + length vs). constructor.
assert ((length ((n,t)::ts)) = 1 + length ts). constructor.
rewrite IHwf_env in H1. auto. Qed.

Hint Resolve wf_length.

Lemma index_safe_ex: forall H1 G1 TF i,
             wf_env H1 G1 ->
             index i G1 = Some TF ->
             exists v, index i H1 = Some v /\ val_type H1 v TF.
Proof. intros. induction H.
       Case "nil". inversion H0.
       Case "cons". inversion H0.
         case_eq (beq_nat i (length ts)).
           SCase "hit".
             intros E.
             rewrite E in H3. inversion H3. subst t.
             assert (beq_nat i (length vs) = true). eauto.
             assert (index i ((n, v) :: vs) = Some v).  eauto. unfold index. rewrite H2. eauto.
             eauto.
           SCase "miss".
             intros E.
             assert (beq_nat i (length vs) = false). eauto.
             rewrite E in H3.
             assert (exists v0, index i vs = Some v0 /\ val_type vs v0 TF) as HI. eapply IHwf_env. eauto.
           inversion HI as [v0 HI1]. inversion HI1. 
           eexists. econstructor. eapply index_extend; eauto. eapply valtp_extend; eauto.
Qed.



Lemma index_safe_ex2: forall H1 G1 f0 dc TA i TF,
             wf_env H1 G1 ->
             index i ((f0, TObj (Some TA) dc):: G1) = Some TF ->
             exists v, index i ((f0, vabs H1 f0 TA dc):: H1) = Some v.
Proof. intros. 
       inversion H0.
       case_eq (beq_nat i (length G1)).
         Case "hit".
           intros. rewrite H2 in H3. inversion H3. eexists.
           assert (beq_nat i (length H1) = true). eauto. unfold index.
           rewrite H4. reflexivity.
         Case "miss".
           intros. assert (beq_nat i (length H1) = false). eauto.
           rewrite H2 in H3. 
           assert (exists v, index i H1 = Some v /\ val_type H1 v TF) as HI. eapply index_safe_ex; eauto.
         inversion HI as [v0 HI1]. inversion HI1.
         eexists. eapply index_extend. eauto.
 Qed.


(* important *)
Lemma stp_wf_refl: forall G1 H1 T1,
                     wf_env H1 G1 ->
                     wf_type G1 T1 ->
                     stpd H1 T1 H1 T1.
Proof.
  intros. wf_cases (induction H0) Case; try solve [exists 0; auto]; try solve [auto 4]. (* eauto would use trans *)
  Case "And".
    eapply stpd_and2.
      eapply stpd_and11. eapply IHwf_type1. eauto. eapply IHwf_type2. eauto.
      eapply stpd_and12. eapply IHwf_type2. eauto. eapply IHwf_type1. eauto.
  Case "Mem".
    eapply stpd_mem_ss; eapply IHwf_type; eauto.
  Case "Fun".
    eapply stpd_fun. eapply IHwf_type1; eauto. eapply IHwf_type2; eauto.
  Case "Sel".
    assert (exists v, index x0 H1 = Some(v) /\ val_type H1 v TE) as IE.
    SCase "IE". eapply index_safe_ex. eauto. eauto.
    inversion IE as [v IE']. inversion IE' as [IE1 IE2].
    exists 0. eapply stp_selx. eapply IE1. eapply IE1.
Qed.



(* important: used in eval_abs_safe *)
Lemma stp_cf_refl: forall G1 H1 T1 TA f dc,
                     wf_env H1 G1 ->
                     wf_type ((f,TObj (Some TA) dc)::G1) T1 ->
                     stpd ((f,vabs H1 f TA dc)::H1) T1 ((f,vabs H1 f TA dc)::H1) T1.
Proof.
  intros.
  remember ((f0, TObj (Some TA) dc0) :: G1) as G2.
  remember ((f0, vabs H1 f0 TA dc0) :: H1) as H2.
  wf_cases (induction H0) Case; try solve [exists 0; auto]; try solve [auto 4].
  Case "And".
    eapply stpd_and2.
      eapply stpd_and11. eapply IHwf_type1. eauto. eapply IHwf_type2. eauto.
      eapply stpd_and12. eapply IHwf_type2. eauto. eapply IHwf_type1. eauto.
  Case "Mem".
    eapply stpd_mem_ss; eapply IHwf_type; eauto.
  Case "Fun".
    eapply stpd_fun. eapply IHwf_type1; eauto. eapply IHwf_type2; eauto.
  Case "Sel".
    assert (exists v, index x0 H2 = Some v) as IE.
    SCase "IE". subst. eapply index_safe_ex2. eauto. subst. eauto.
    inversion IE as [v IE1]. 
    exists 0. eapply stp_selx. eapply IE1. eapply IE1.
Qed.

(* 
Note:

We need to consider wf_type and stp with extended environment relative
to wf_env, because this is part of the construction of a val_type that
will become part of the extended wf_env!
*)         



Lemma tresolve2stp: forall H1 H2 T1 T2 T3,
                 stpd H1 T1 H2 T2 ->
                 tresolve T2 T3 ->
                 stpd H1 T1 H2 T3.
Proof.
  intros.
  tresolve_cases (induction H0) Case.
  Case "Self". eauto.
  Case "And1". eapply IHtresolve. eapply stp_and2A. eauto.
  Case "And2". eapply IHtresolve. eapply stp_and2B. eauto.
Qed.

Lemma valtp_widen_tresolve: forall G1 T1 T2 v,
                     val_type G1 v T1 ->
                     tresolve T1 T2 ->
                     val_type G1 v T2.
Proof.
  intros. induction H; econstructor.
    Case "Bool". eapply tresolve2stp; eauto.
    Case "Abs". eauto. eauto. eauto. eauto. eapply tresolve2stp;  eauto.
Qed.


Lemma valtp_invert: forall v x0 H1 TF,
  index x0 H1 = Some v ->
  val_type H1 v TF ->
  exists HC TC, resolve H1 x0 = Some (HC,TC) /\ stpd HC TC H1 TF.
Proof.
  intros.
  inversion H0.  
  Case "Bool".
    subst. eexists.
    eexists.
    split. unfold resolve. rewrite H.
    reflexivity.
    eauto.
  Case "Fun".
    eexists. 
    eexists.
    split.
    unfold resolve.
    subst. rewrite H. 
    reflexivity.
    subst. eauto.
Qed.




Lemma stp_inv_obj_ex_mem: forall env0 env1 dcs TA TA2,
  stpd env0 (TObj (Some TA) dcs) env1 (TMem (Some TA2)) ->
      stpd env0 TA env1 TA2 /\ stpd env1 TA2 env0 TA.
Proof. intros.
       unfold TObj in H.
       assert (nostp (dc_type_and dcs) (TMem (Some TA2))). eapply nostp_inv_dcs_mem.
       eapply stp_andA in H. destruct H. inversion H.
       split; eexists; eauto.
       eauto. (* nostp *)
Qed.

Lemma stp_inv_obj_ex_mem0: forall env0 env1 dcs TA TA2,
  stpd env0 (TObj (Some TA) dcs) env1 (TMem (Some TA2)) ->
      stpd env0 (TObj (Some TA) dcs) env0 (TMem (Some TA)).
Proof. intros.
       unfold TObj in H.
       assert (nostp (dc_type_and dcs) (TMem (Some TA2))). eapply nostp_inv_dcs_mem.
       eapply stp_andA in H. destruct H. inversion H.
       subst.
       eapply stpd_and11. eapply stpd_mem_ss.
         eapply stpd_trans. eexists; eauto. eexists; eauto.
         eapply stpd_trans. eexists; eauto. eexists; eauto.
       admit. (* dcs regularity *)
       eauto. (* nostp *)  
Qed.


Lemma atp2stp: forall G1 H1 T1 T2,
                 wf_env H1 G1 ->
                 atp G1 T1 T2 ->
                 stpd H1 T1 H1 T2.
Proof.
  intros.
  atp_cases (induction H0) Case.
  Case "? < Sel".
    assert (exists v, index x0 H1 = Some v /\ val_type H1 v TF) as IE.
    SCase "IE". eapply index_safe_ex; eauto.
      inversion IE as [v IE']. inversion IE' as [IE1 IE2].

    assert (val_type H1 v (TMem (Some T))) as JE.
    SCase "JE". eapply valtp_widen_tresolve; eauto.

    assert (exists HC TC, resolve H1 x0 = Some (HC,TC) /\ stpd HC TC H1 (TMem (Some T))) as LE.
    SCase "LE". eapply valtp_invert; eauto.

    inversion LE as [HC LE']. inversion LE' as [TC LE'']. inversion LE'' as [LE1 LE2].
    unfold stpd in LE2.

    destruct v. inversion JE. subst. inversion H5. inversion H3. (* not bool *)

    inversion JE. unfold resolve in  LE1. rewrite IE1 in LE1. inversion LE1. subst.

    assert (stpd ((i, vabs l i t l0) :: l) t H1 T /\ stpd H1 T ((i, vabs l i t l0) :: l) t) as [HXL HXR].
      eapply stp_inv_obj_ex_mem. apply H13. (* stp HC TC H1 T *)
     
    inversion LE'' as [LE1' LE2']. subst.
    
    eapply stpd_sel2. apply IE1. apply HXR.

  Case "Sel < ?".

    assert (exists v, index x0 H1 = Some v /\ val_type H1 v TF) as IE.
    SCase "IE". eapply index_safe_ex; eauto.
      inversion IE as [v IE']. inversion IE' as [IE1 IE2].

    assert (val_type H1 v (TMem (Some T))) as JE.
    SCase "JE". eapply valtp_widen_tresolve; eauto.

    assert (exists HC TC, resolve H1 x0 = Some (HC,TC) /\ stpd HC TC H1 (TMem (Some T))) as LE.
    SCase "LE". eapply valtp_invert; eauto.

    inversion LE as [HC LE']. inversion LE' as [TC LE'']. inversion LE'' as [LE1 LE2].
    unfold stpd in LE2.

    destruct v. inversion JE. subst. inversion H5. inversion H3. (* not bool *)

    inversion JE. unfold resolve in  LE1. rewrite IE1 in LE1. inversion LE1. subst.

    assert (stpd ((i, vabs l i t l0) :: l) t H1 T /\ stpd H1 T ((i, vabs l i t l0) :: l) t) as [HXL HXR].
      eapply stp_inv_obj_ex_mem. apply H13. (* stp HC TC H1 T *)
     
    inversion LE'' as [LE1' LE2']. subst.
    
    eapply stpd_sel1. apply IE1. apply HXL.
Qed.




Lemma valtp_widen_atp: forall G H T1 T2 v,
                     val_type H v T1 ->
                     wf_env H G ->
                     atp G T1 T2 ->
                     val_type H v T2.
Proof.
  intros. eapply valtp_widen. eauto. eauto. eapply atp2stp. eauto. eauto. 
Qed.




Lemma hastp_wf: forall G e T, has_type G e T -> wf_type G T.
Proof. intros. induction H; eauto.
Qed.


Hint Resolve stp_extend1.
Hint Resolve stp_extend2.
Hint Resolve stp_reg1.
Hint Resolve stp_wf_refl.

Hint Resolve wft_extend.
Hint Resolve valtp_widen.



Lemma nostp_inv_dcs: forall m dcs T3 T4,
  length dcs <= m ->
  nostp (dc_type_and dcs) (TFun m T3 T4).
Proof.
  intros.
  induction dcs.
  Case "nil". eauto.
  Case "cons".
    assert (S (length dcs) = length (a::dcs)) as L. eauto.
    unfold dc_type_and. destruct a. destruct d.
    eapply nostp_and.
      eapply nostp_fun. omega.
      eapply IHdcs. omega. 
Qed.






Lemma stp_inv_obj_ex: forall m dcs env0 env1 T3 T4 TA,
  stpd env0 (TObj (Some TA) dcs) env1 (TFun m T3 T4) ->
  exists T1 T2 x ey,
    index m dcs = Some (dfun T1 T2 x ey) /\
    stpd env0 (TFun m T1 T2) env1 (TFun m T3 T4).
Proof.
  intros.

  unfold TObj in H.
  eapply stp_andB in H. (* it's not the TMem *)

  induction dcs.
  Case "nil". destruct H. inversion H. (* can't happen *)
  Case "cons". 
    case_eq (beq_nat m (length dcs)); intros E. 
    SCase "hit".    
      unfold dc_type_and in H. destruct a. destruct d. subst.
      assert (m = length dcs) as L. eapply beq_nat_true; eauto.

      eexists. eexists. eexists. eexists. eexists.
      unfold index. rewrite E. reflexivity.      
      eapply stp_andA. subst m. eapply H. eapply nostp_inv_dcs. omega.
    SCase "miss".
      unfold dc_type_and in H. destruct a. destruct d.
      assert (not (m = length dcs)) as L. eapply beq_nat_false; eauto.
      assert (exists T1 T2 x ey,
  index m dcs = Some (dfun T1 T2 x ey) /\
  stpd env0 (TFun m T1 T2) env1 (TFun m T3 T4)) as HI. eapply IHdcs.
        eapply stp_andB. eapply H. eapply nostp_fun. eauto.

  destruct HI as [T1 [T2 [x0 [ey [IX ST]]]]].
  eexists. eexists. eexists. eexists. eexists.
  eapply index_extend; eauto. eauto.      
        
  eapply nostp_fun_mem.
Qed.



Lemma dc_inv_has_type: forall m x ey dcs tenv0 T1 T2,
  index m dcs = Some (dfun T1 T2 x ey) ->
  dc_has_type tenv0 dcs ->
  has_type ((x,T1) :: tenv0) ey T2.
Proof.
  intros.
  induction dcs.
  Case "nil". inversion H.
  Case "cons". inversion H. destruct a.
    case_eq (beq_nat m (length dcs)); intros E; rewrite E in H2; inversion H2; subst.
    SCase "hit". inversion H0. eauto.
    SCase "miss". inversion H0. eapply IHdcs; eauto.
Qed.


Lemma invert_abs: forall venv vf vx m T1 T2,
  val_type venv vf (TFun m T1 T2) ->
  exists env tenv f x y dcs T3 T4 TA TF,
    TF = TObj (Some TA) dcs /\ 
    vf = (vabs env f TA dcs) /\
    wf_env env tenv /\
    wf_type ((f,TF)::tenv) TF /\
    dc_has_type ((f, TF) :: tenv) dcs /\
    index m dcs = Some (dfun T3 T4 x y) /\
    has_type ((x,T3)::(f,TF)::tenv) y T4 /\
    stpd venv T1 ((x,vx)::(f,vf)::env) T3 /\
    stpd ((x,vx)::(f,vf)::env) T4 venv T2.
Proof.
  (*  intros. inversion H. repeat eexists; repeat eauto. *)

  intros. inversion H. destruct H0. inversion H0. (* bool case *)

  assert (exists T3 T4 x y, index m dcs = Some (dfun T3 T4 x y) /\
         stpd ((f0, vabs env0 f0 TA dcs) :: env0) (TFun m T3 T4) venv (TFun m T1 T2)). eapply stp_inv_obj_ex. subst TF. eapply H4.

  destruct H8 as [T3 [T4 [x0 [y0 [IX ST]]]]].
  
  subst TF.
  destruct ST as [nx ST]. inversion ST.

  repeat eexists. 
  eauto. eauto. eauto. eauto. eauto. eapply dc_inv_has_type; eauto.
  eauto. eauto.
Qed.


Inductive res_type: env -> option vl -> ty -> Prop :=
| not_stuck: forall v T venv,
      val_type venv v T ->
      res_type venv (Some v) T.

Hint Constructors res_type.
Hint Resolve not_stuck.

(* if not a timeout, then result not stuck and well-typed *)

Theorem full_safety : forall n e tenv venv res T,
  teval n venv e = Some res -> has_type tenv e T -> wf_env venv tenv ->
  res_type venv res T.

Proof.
  intros n. induction n.
  (* 0 *)   intros. inversion H.
  (* S n *) intros. destruct e; inversion H; inversion H0.
  
  Case "True".  eapply not_stuck. eapply v_bool. exists 0. eauto.
  Case "False". eapply not_stuck. eapply v_bool. exists 0. eauto.

  Case "Var".
    SCase "TVar".
      destruct (index_safe_ex venv tenv0 T i) as [v [I V]]; eauto. 
      rewrite I. eapply not_stuck. eapply V.
    SCase "TVara".
      destruct (index_safe_ex venv tenv0 T0 i) as [v [I V]]; eauto. 
      rewrite I. eapply not_stuck. eapply valtp_widen_atp. eapply V. eauto. eauto.

  Case "App".
    (*remember (teval n venv e1) as tf.*)
    remember (teval n venv e) as tx. 
    subst T.
    
    destruct tx as [rx|]; try solve by inversion.
    assert (res_type venv rx T1) as HRX. SCase "HRX". subst. eapply IHn; eauto.
    inversion HRX as [vx]. 

    (*
    destruct tf as [rf|]; subst rx; try solve by inversion.  
    assert (res_type venv rf (TFun T1 T2)) as HRF. SCase "HRF". subst. eapply IHn; eauto.
    inversion HRF as [vf].
     *)

    destruct (index_safe_ex venv tenv0 TF i) as [vf [I V]]; eauto. 

    eapply valtp_widen_tresolve in V; eauto.
    subst i0.
    destruct (invert_abs venv vf vx m T1 T2) as
        [env1 [tenv [f1 [x1 [y1 [dcs [T3 [T4 [TA [TF1
        [ETF [EVF [WFE [WFT [HDCS [HDC [HTY [STX STY]]]]]]]]]]]]]]]]]]. eapply V.
    (* now we know it's a closure, and we have has_type evidence,
    so we can check the body *)

    rewrite I in H3. 
    assert (res_type ((x1,vx)::(f1,vf)::env1) res T4) as HRY.
      SCase "HRY".
        subst. rewrite HDC in H3. eapply IHn. eauto. eauto.
        (* wf_env f x *) econstructor. eapply valtp_widen; eauto.
        (* wf_env f   *) econstructor. eapply v_abs; eauto. eapply stp_cf_refl; eauto.
        eauto.

    inversion HRY as [vy].

    eapply not_stuck. eapply valtp_widen; eauto.
    
  Case "Abs". 
    remember (teval n ((i, vabs venv i t l) :: venv) e) as tx.
    destruct tx as [rx|]; subst; try solve by inversion.

     remember i as f0.
     remember l as dcs.
     remember venv as env0.
     remember (TObj (Some t) dcs) as TF.
     remember (TObj None     dcs) as TFA.
     remember ((f0, vabs env0 f0 t dcs) :: env0) as venvf.
     
     assert (stpd venvf TF venvf TF) as ST0. SCase "ST0".
       subst. eapply stp_cf_refl; eauto. 
     assert (stpd venvf TF venvf TFA) as STA. SCase "STA".
       subst. eapply stpd_mem_abs. eauto.
     assert (res_type venvf res T) as HI. SCase "HI".
       subst. eapply IHn; eauto.
     inversion HI.
       
     subst. eapply not_stuck. eapply valtp_widen. eauto.
       eapply stpd_extend1. eapply stp_reg1. eapply stp_wf_refl; eauto.

   Case "Let".
     remember (teval n venv e1) as tx.
     destruct tx as [rx|]; subst; try solve by inversion.
     assert (res_type venv rx t) as HRX. SCase "HRX". subst. eapply IHn; eauto.
     inversion HRX as [vx].

     subst. 

     assert (res_type ((i, vx) :: venv) res T) as HI. SCase "HI".
       subst. eapply IHn; eauto. constructor. eapply valtp_widen. eauto.
       eapply stpd_extend2. eapply stp_wf_refl. eauto. eapply hastp_wf. eauto. eauto.
     inversion HI.
       
     subst. eapply not_stuck. eapply valtp_widen. eauto.
       eapply stpd_extend1. eapply stp_reg1. eapply stp_wf_refl; eauto.
     
Qed.

End DOT.

