(* smallstep proof *)

Require Export SfLib.

Require Export Arith.EqNat.
Require Export Arith.Lt.

Module STLC.

Definition id := nat.

Inductive ty : Type :=
  | TBot   : ty
  | TTop   : ty
  | TBool  : ty           
  | TFun   : ty -> ty -> ty
  | TMem   : ty -> ty -> ty (* intro *)
  | TVar   : bool -> id -> ty
  | TVarB  : id -> ty                   
  | TSel   : ty -> ty (* elim *)
  | TBind  : ty -> ty
  | TAnd   : ty -> ty -> ty
.

Inductive tm : Type :=
  | tvar  : bool -> id -> tm
  | tbool : bool -> tm
  | tobj  : dm -> tm (* todo: multiple members *)
  | tapp  : tm -> tm -> tm

with dm : Type :=
  | dfun : ty -> ty -> tm -> dm
  | dty  : ty -> dm
.

Inductive vl : Type :=
  | vbool : bool -> vl
  | vobj  : dm -> vl
.

Definition venv := list vl.
Definition tenv := list ty.

Hint Unfold venv.
Hint Unfold tenv.

Fixpoint index {X : Type} (n : id) (l : list X) : option X :=
  match l with
    | [] => None
    | a :: l'  => if beq_nat n (length l') then Some a else index n l'
  end.


Inductive closed: nat -> nat -> nat -> ty -> Prop :=
| cl_bot: forall i j k,
    closed i j k TBot
| cl_top: forall i j k,
    closed i j k TTop
| cl_bool: forall i j k,
    closed i j k TBool
| cl_fun: forall i j k T1 T2,
    closed i j k T1 ->
    closed i j k T2 ->
    closed i j k (TFun T1 T2)
| cl_mem: forall i j k T1 T2,
    closed i j k T1 ->
    closed i j k T2 ->        
    closed i j k (TMem T1 T2)
| cl_var0: forall i j k x,
    i > x ->
    closed i j k (TVar false x)
| cl_var1: forall i j k x,
    j > x ->
    closed i j k (TVar true x)
| cl_varB: forall i j k x,
    k > x ->
    closed i j k (TVarB x)
| cl_sel: forall i j k T1,
    closed i j k T1 ->
    closed i j k (TSel T1)
| cl_bind: forall i j k T1,
    closed i j (S k) T1 ->
    closed i j k (TBind T1)
| cl_and: forall i j k T1 T2,
    closed i j k T1 ->
    closed i j k T2 ->        
    closed i j k (TAnd T1 T2)
.


Fixpoint open (k: nat) (u: ty) (T: ty) { struct T }: ty :=
  match T with
    | TVar b x => TVar b x (* free var remains free. functional, so we can't check for conflict *)
    | TVarB x => if beq_nat k x then u else TVarB x
    | TTop        => TTop
    | TBot        => TBot
    | TBool       => TBool
    | TSel T1     => TSel (open k u T1)                  
    | TFun T1 T2  => TFun (open k u T1) (open k u T2)
    | TMem T1 T2  => TMem (open k u T1) (open k u T2)
    | TBind T1    => TBind (open (S k) u T1)
    | TAnd T1 T2  => TAnd (open k u T1) (open k u T2)
  end.

Fixpoint subst (U : ty) (T : ty) {struct T} : ty :=
  match T with
    | TTop         => TTop
    | TBot         => TBot
    | TBool        => TBool
    | TMem T1 T2   => TMem (subst U T1) (subst U T2)
    | TSel T1      => TSel (subst U T1)
    | TVarB i      => TVarB i
    | TVar true i  => TVar true i
    | TVar false i => if beq_nat i 0 then U else TVar false (i-1)
    | TFun T1 T2   => TFun (subst U T1) (subst U T2)
    | TBind T2     => TBind (subst U T2)
    | TAnd T1 T2   => TAnd (subst U T1) (subst U T2)
  end.



Inductive has_type : tenv -> venv -> tm -> ty -> nat -> Prop :=
  | T_Varx : forall m GH G1 x T n1,
      vtp m G1 x T n1 ->
      has_type GH G1 (tvar true x) T (S n1)
  | T_Vary : forall G1 GH x T n1,
      index x GH = Some T ->
      closed (length GH) (length G1) 0 T -> 
      has_type GH G1 (tvar false x) T (S n1)
  (* todo: add var pack/unpack *)
  (* todo: recursive objects with multiple members *)
  | T_Mem : forall GH G1 T11 n1,
      closed (length GH) (length G1) 0 T11 -> 
      has_type GH G1 (tobj (dty T11)) (TMem T11 T11) (S n1)
  | T_Abs : forall GH G1 T11 T12 t12 n1,
      has_type (T11::GH) G1 t12 T12 n1 ->
      closed (length GH) (length G1) 0 T11 ->
      closed (length GH) (length G1) 0 T12 -> 
      has_type GH G1 (tobj (dfun T11 T12 t12)) (TFun T11 T12) (S n1)
  | T_App : forall T1 T2 GH G1 t1 t2 n1 n2,
      has_type GH G1 t1 (TFun T1 T2) n1 ->
      has_type GH G1 t2 T1 n2 ->
      has_type GH G1 (tapp t1 t2) T2 (S (n1+n2))
  (* todo: add app-var and use dependent functions *)
  | T_Sub : forall GH G1 t T1 T2 n1 n2,
      has_type GH G1 t T1 n1 ->
      stp2 GH G1 T1 T2 n2 ->
      has_type GH G1 t T2 (S (n1 + n2))


with stp2: tenv -> venv -> ty -> ty -> nat -> Prop :=
| stp2_bot: forall GH G1 T n1,
    closed (length GH) (length G1) 0  T ->
    stp2 GH G1 TBot T (S n1)
| stp2_top: forall GH G1 T n1,
    closed (length GH) (length G1) 0 T ->
    stp2 GH G1 T  TTop (S n1)
| stp2_bool: forall GH G1 n1,
    stp2 GH G1 TBool TBool (S n1)
(* todo: enabled dependent functions *)
| stp2_fun: forall GH G1 T1 T2 T3 T4 n1 n2,
    stp2 GH G1 T3 T1 n1 ->
    stp2 GH G1 T2 T4 n2 ->
    stp2 GH G1 (TFun T1 T2) (TFun T3 T4) (S (n1+n2))
| stp2_mem: forall GH G1 T1 T2 T3 T4 n1 n2,
    stp2 GH G1 T3 T1 n2 ->
    stp2 GH G1 T2 T4 n1 ->
    stp2 GH G1 (TMem T1 T2) (TMem T3 T4) (S (n1+n2))

| stp2_varx: forall GH G1 x n1,
    x < length G1 ->
    stp2 GH G1 (TVar true x) (TVar true x) (S n1)
| stp2_varax: forall GH G1 x n1,
    x < length GH ->
    stp2 GH G1 (TVar false x) (TVar false x) (S n1)

| stp2_strong_sel1: forall GH G1 T2 TX x n1,
    index x G1 = Some (vobj (dty TX)) ->
    stp2 [] G1 TX T2 n1 ->
    stp2 GH G1 (TSel (TVar true x)) T2 (S n1)
| stp2_strong_sel2: forall GH G1 T1 TX x n1,
    index x G1 = Some (vobj (dty TX)) ->
    stp2 [] G1 T1 TX n1 ->
    stp2 GH G1 T1 (TSel (TVar true x)) (S n1)

| stp2_sel1: forall GH G1 T2 x n1,
    htp  GH G1 x (TMem TBot T2) n1 ->
    stp2 GH G1 (TSel (TVar false x)) T2 (S n1)

| stp2_sel2: forall GH G1 T1 x n1,
    htp  GH G1 x (TMem T1 TTop) n1 ->
    stp2 GH G1 T1 (TSel (TVar false x)) (S n1)

| stp2_selx: forall GH G1 T1 n1,
    closed (length GH) (length G1) 0 T1 ->
    stp2 GH G1 (TSel T1) (TSel T1) (S n1)

         

| stp2_bind1: forall GH G1 T1 T1' T2 n1,
    htp (T1'::GH) G1 (length GH) T2 n1 ->
    T1' = (open 0 (TVar false (length GH)) T1) ->
    closed (length GH) (length G1) 1 T1 ->
    closed (length GH) (length G1) 0 T2 ->
    stp2 GH G1 (TBind T1) T2 (S n1)

| stp2_bindx: forall GH G1 T1 T1' T2 T2' n1,
    htp (T1'::GH) G1 (length GH) T2' n1 ->
    T1' = (open 0 (TVar false (length GH)) T1) ->
    T2' = (open 0 (TVar false (length GH)) T2) -> 
    closed (length GH) (length G1) 1 T1 ->
    closed (length GH) (length G1) 1 T2 ->
    stp2 GH G1 (TBind T1) (TBind T2) (S n1)
         
| stp2_and11: forall GH G1 T1 T2 T n1,
    stp2 GH G1 T1 T n1 ->
    closed (length GH) (length G1) 0 T2 ->
    stp2 GH G1 (TAnd T1 T2) T (S n1)
| stp2_and12: forall GH G1 T1 T2 T n1,
    stp2 GH G1 T2 T n1 ->
    closed (length GH) (length G1) 0 T1 ->
    stp2 GH G1 (TAnd T1 T2) T (S n1)
| stp2_and2: forall GH G1 T1 T2 T n1 n2,
    stp2 GH G1 T T1 n1 ->
    stp2 GH G1 T T2 n2 ->
    stp2 GH G1 T (TAnd T1 T2) (S (n1+n2))
         
| stp2_transf: forall GH G1 T1 T2 T3 n1 n2,
    stp2 GH G1 T1 T2 n1 ->
    stp2 GH G1 T2 T3 n2 -> 
    stp2 GH G1 T1 T3 (S (n1+n2))
         

with htp: tenv -> venv -> nat -> ty -> nat -> Prop :=
| htp_var: forall GH G1 x TX n1,
    index x GH = Some TX ->
    closed (length GH) (length G1) 0 TX ->         
    htp GH G1 x TX (S n1)
| htp_bind: forall GH G1 x TX n1,
    htp GH G1 x (TBind TX) n1 ->
    closed x (length G1) 1 TX ->
    htp GH G1 x (open 0 (TVar false x) TX) (S n1)
| htp_sub: forall GH GU GL G1 x T1 T2 n1 n2,
    (* use restricted GH. note: this is slightly different
    from the big-step version b/c here we do not distinguish
    if variables are bound in terms vs types. it would be easy 
    to do exactly the same thing by adding this distinction. *)
    htp GH G1 x T1 n1 ->
    stp2 GL G1 T1 T2 n2 ->
    length GL = S x ->
    GH = GU ++ GL -> 
    htp GH G1 x T2 (S (n1+n2))
             
with vtp : nat -> venv -> nat -> ty -> nat -> Prop :=
| vtp_top: forall m G1 x n1,
    x < length G1 ->
    vtp m G1 x TTop (S n1)
| vtp_bool: forall m G1 x b n1,
    index x G1 = Some (vbool b) ->
    vtp m G1 x (TBool) (S (n1))
| vtp_mem: forall m G1 x TX T1 T2 n1 n2,
    index x G1 = Some (vobj (dty TX)) ->
    stp2 [] G1 T1 TX n1 ->
    stp2 [] G1 TX T2 n2 ->
    vtp m G1 x (TMem T1 T2) (S (n1+n2))
| vtp_fun: forall m G1 x T1 T2 T3 T4 t n1 n2 n3,
    index x G1 = Some (vobj (dfun T1 T2 t)) ->
    has_type [T1] G1 t T2 n3 ->
    stp2 [] G1 T3 T1 n1 ->
    stp2 [] G1 T2 T4 n2 ->             
    vtp m G1 x (TFun T3 T4) (S (n1+n2+n3))
| vtp_bind: forall m G1 x T2 n1,
    vtp m G1 x (open 0 (TVar true x) T2) n1 ->
    closed 0 (length G1) 1 T2 ->
    vtp (S m) G1 x (TBind T2) (S (n1))
| vtp_sel: forall m G1 x y TX n1,
    index y G1 = Some (vobj (dty TX)) ->
    vtp m G1 x TX n1 ->
    vtp m G1 x (TSel (TVar true y)) (S (n1))
| vtp_and: forall m m1 m2 G1 x T1 T2 n1 n2,
    vtp m1 G1 x T1 n1 ->
    vtp m2 G1 x T2 n2 ->
    m1 <= m -> m2 <= m ->
    vtp m G1 x (TAnd T1 T2) (S (n1+n2))
.

Definition has_typed GH G1 x T1 := exists n, has_type GH G1 x T1 n.

Definition stpd2 GH G1 T1 T2 := exists n, stp2 GH G1 T1 T2 n.

Definition htpd GH G1 x T1 := exists n, htp GH G1 x T1 n.

Definition vtpd m G1 x T1 := exists n, vtp m G1 x T1 n.

Definition vtpdd m G1 x T1 := exists m1 n, vtp m1 G1 x T1 n /\ m1 <= m.

Hint Constructors stp2.
Hint Constructors vtp.

Ltac ep := match goal with
             | [ |- stp2 ?GH ?G1 ?T1 ?T2 ?N ] => assert (exists (n:nat), stp2 GH G1 T1 T2 n) as EEX
           end.

Ltac eu := match goal with
             | H: has_typed _ _ _ _ |- _ => destruct H as [? H]
             | H: stpd2 _ _ _ _ |- _ => destruct H as [? H]
             | H: htpd _ _ _ _ |- _ => destruct H as [? H]
             | H: vtpd _ _ _ _ |- _ => destruct H as [? H]
             | H: vtpdd _ _ _ _ |- _ => destruct H as [? [? [H ?]]]
           end.

Lemma stpd2_bot: forall GH G1 T,
    closed (length GH) (length G1) 0 T ->
    stpd2 GH G1 TBot T.
Proof. intros. exists 1. eauto. Qed.
Lemma stpd2_top: forall GH G1 T,
    closed (length GH) (length G1) 0 T ->
    stpd2 GH G1 T TTop.
Proof. intros. exists 1. eauto. Qed.
Lemma stpd2_bool: forall GH G1,
    stpd2 GH G1 TBool TBool.
Proof. intros. exists 1. eauto. Qed.
Lemma stpd2_fun: forall GH G1 T1 T2 T3 T4,
    stpd2 GH G1 T3 T1 ->
    stpd2 GH G1 T2 T4 ->
    stpd2 GH G1 (TFun T1 T2) (TFun T3 T4).
Proof. intros. repeat eu. eexists. eauto. Qed.
Lemma stpd2_mem: forall GH G1 T1 T2 T3 T4,
    stpd2 GH G1 T3 T1 ->
    stpd2 GH G1 T2 T4 ->
    stpd2 GH G1 (TMem T1 T2) (TMem T3 T4).
Proof. intros. repeat eu. eexists. eauto. Qed.



Lemma stpd2_transf: forall GH G1 T1 T2 T3,
    stpd2 GH G1 T1 T2 ->
    stpd2 GH G1 T2 T3 ->
    stpd2 GH G1 T1 T3.
Proof. intros. repeat eu. eexists. eauto. Qed.




Hint Constructors ty.
Hint Constructors vl.


Hint Constructors stp2.
Hint Constructors vtp.
Hint Constructors htp.
Hint Constructors has_type.

Hint Unfold has_typed.
Hint Unfold stpd2.
Hint Unfold vtpd.
Hint Unfold vtpdd.

Hint Constructors option.
Hint Constructors list.

Hint Unfold index.
Hint Unfold length.

Hint Resolve ex_intro.


Ltac ev := repeat match goal with
                    | H: exists _, _ |- _ => destruct H
                    | H: _ /\  _ |- _ => destruct H
           end.





Lemma index_max : forall X vs n (T: X),
                       index n vs = Some T ->
                       n < length vs.
Proof.
  intros X vs. induction vs.
  Case "nil". intros. inversion H.
  Case "cons".
  intros. inversion H.
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

Lemma index_exists : forall X vs n,
                       n < length vs ->
                       exists (T:X), index n vs = Some T.
Proof.
  intros X vs. induction vs.
  Case "nil". intros. inversion H.
  Case "cons".
  intros. inversion H.
  SCase "hit".
  assert (beq_nat n (length vs) = true) as E. eapply beq_nat_true_iff. eauto.
  simpl. subst n. rewrite E. eauto.
  SCase "miss".
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff. omega.
  simpl. rewrite E. eapply IHvs. eauto.
Qed.


Lemma index_extend : forall X vs n a (T: X),
                       index n vs = Some T ->
                       index n (a::vs) = Some T.

Proof.
  intros.
  assert (n < length vs). eapply index_max. eauto.
  assert (n <> length vs). omega.
  assert (beq_nat n (length vs) = false) as E. eapply beq_nat_false_iff; eauto.
  unfold index. unfold index in H. rewrite H. rewrite E. reflexivity.
Qed.


Lemma closed_extend : forall T X (a:X) i k G,
                       closed i (length G) k T ->
                       closed i (length (a::G)) k T.
Proof.
  intros T. induction T; intros; inversion H;  econstructor; eauto.
  simpl. omega.
Qed.


Lemma all_extend: forall ni,
  (forall GH  v1 G1 T1 T2 n,
     stp2 GH G1 T1 T2 n -> n < ni ->
     stp2 GH (v1::G1) T1 T2 n) /\
  (forall m v1 x G1 T2 n,
     vtp m G1 x T2 n -> n < ni ->
     vtp m (v1::G1) x T2 n) /\
  (forall v1 x GH G1 T2 n,
     htp GH G1 x T2 n -> n < ni ->
     htp GH (v1::G1) x T2 n) /\
  (forall GH G1 t T v n,
     has_type GH G1 t T n -> n < ni ->
     has_type GH (v::G1) t T n).
Proof.
  intros n. induction n. repeat split; intros; omega.
  repeat split; intros; inversion H.
  (* stp *)
  - econstructor. eapply closed_extend. eauto.
  - econstructor. eapply closed_extend. eauto.
  - econstructor. 
  - econstructor. eapply IHn. eauto. omega. eapply IHn. eauto. omega.
  - econstructor. eapply IHn. eauto. omega. eapply IHn. eauto. omega. 
  - econstructor. simpl. eauto.
  - econstructor. eauto.
  - econstructor. eapply index_extend. eauto. eapply IHn. eauto. omega.
  - econstructor. eapply index_extend. eauto. eapply IHn. eauto. omega.
  - econstructor. eapply IHn. eauto. omega.
  - econstructor. eapply IHn. eauto. omega.
  - econstructor. eapply closed_extend. eauto. 
  - econstructor. eapply IHn. eauto. omega. eauto. eapply closed_extend. eauto. eapply closed_extend. eauto. 
  - eapply stp2_bindx. eapply IHn. eauto. omega. eauto. eauto. eapply closed_extend. eauto. eapply closed_extend. eauto.
  - eapply stp2_and11. eapply IHn. eauto. omega. eapply closed_extend. eauto.
  - eapply stp2_and12. eapply IHn. eauto. omega. eapply closed_extend. eauto.
  - eapply stp2_and2. eapply IHn. eauto. omega. eapply IHn. eauto. omega.
  - eapply stp2_transf. eapply IHn. eauto. omega. eapply IHn. eauto. omega. 
  (* vtp *)    
  - econstructor. simpl. eauto.
  - econstructor. eapply index_extend. eauto.
  - econstructor. eapply index_extend. eauto. eapply IHn. eauto. omega. eapply IHn. eauto. omega.
  - econstructor. eapply index_extend. eauto. eapply IHn. eauto. omega. eapply IHn. eauto. omega. eapply IHn. eauto. omega.
  - econstructor. eapply IHn. eauto. omega. eapply closed_extend. eauto. 
  - econstructor. eapply index_extend. eauto. eapply IHn. eauto. omega.
  - econstructor. eapply IHn. eauto. omega. eapply IHn. eauto. omega. eauto. eauto. 
  (* htp *)
  - econstructor. eauto. eapply closed_extend. eauto. 
  - eapply htp_bind. eapply IHn. eauto. omega. eapply closed_extend. eauto. 
  - eapply htp_sub. eapply IHn. eauto. omega. eapply IHn. eauto. omega. eauto. eauto.
  (* has_type *)
  - econstructor. eapply IHn. eauto. omega.
  - econstructor. eauto. eapply closed_extend. eauto.
  - econstructor. eapply closed_extend. eauto.
  - econstructor. eapply IHn. eauto. omega. eapply closed_extend. eauto. eapply closed_extend. eauto.
  - econstructor. eapply IHn. eauto. omega. eapply IHn. eauto. omega.
  - econstructor. eapply IHn. eauto. omega. eapply IHn. eauto. omega. 
Qed.


Lemma closed_upgrade_gh: forall i i1 j k T1,
  closed i j k T1 -> i <= i1 -> closed i1 j k T1.
Proof.
  intros. generalize dependent i1. induction H; intros; econstructor; eauto. omega.
Qed.

Lemma closed_upgrade: forall i j k k1 T1,
  closed i j k T1 -> k <= k1 -> closed i j k1 T1.
Proof.
  intros. generalize dependent k1. induction H; intros; econstructor; eauto. omega.
  eapply IHclosed. omega. 
Qed.

Lemma closed_open: forall j k n b V T, closed k n (j+1) T -> closed k n j (TVar b V) -> closed k n j (open j (TVar b V) T).
Proof.
  intros. generalize dependent j. induction T; intros; inversion H; try econstructor; try eapply IHT1; eauto; try eapply IHT2; eauto; try eapply IHT; eauto.

  - Case "TVarB". simpl.
    case_eq (beq_nat j i); intros E. eauto. 
    econstructor. eapply beq_nat_false_iff in E. omega.
  - eapply closed_upgrade; eauto.
Qed.





Lemma all_closed: forall ni,
  (forall GH G1 T1 T2 n,
     stp2 GH G1 T1 T2 n -> n < ni ->
     closed (length GH) (length G1) 0 T1) /\
  (forall GH G1 T1 T2 n,
     stp2 GH G1 T1 T2 n -> n < ni ->
     closed (length GH) (length G1) 0 T2) /\
  (forall m x G1 T2 n,
     vtp m G1 x T2 n -> n < ni ->
     x < length G1) /\
  (forall m x G1 T2 n,
     vtp m G1 x T2 n -> n < ni ->
     closed 0 (length G1) 0 T2) /\
  (forall x GH G1 T2 n,
     htp GH G1 x T2 n -> n < ni ->
     x < length GH) /\
  (forall x GH G1 T2 n,
     htp GH G1 x T2 n -> n < ni ->
     closed (length GH) (length G1) 0 T2) /\
  (forall GH G1 t T n,
     has_type GH G1 t T n -> n < ni ->
     closed (length GH) (length G1) 0 T).
Proof.
  intros n. induction n. repeat split; intros; omega.
  repeat split; intros; inversion H; destruct IHn as [IHS1 [IHS2 [IHV1 [IHV2 [IHH1 [IHH2 IHT]]]]]].
  (* stp left *)
  - econstructor. 
  - eauto. 
  - econstructor. 
  - econstructor. eapply IHS2. eauto. omega. eapply IHS1. eauto. omega.
  - econstructor. eapply IHS2. eauto. omega. eapply IHS1. eauto. omega. 
  - econstructor. simpl. eauto.
  - econstructor. eauto.
  - econstructor. econstructor. eapply index_max. eauto. 
  - eapply closed_upgrade_gh. eapply IHS1. eapply H2. omega. simpl. omega.  
  - econstructor. econstructor. eapply IHH1. eauto. omega.
  - eapply closed_upgrade_gh. eapply IHH2 in H1. inversion H1. eauto. omega. simpl. omega.
  - econstructor. eauto.
  - econstructor. eauto.
  - econstructor. eauto.
  - econstructor. eapply IHS1. eauto. omega. eauto.
  - econstructor. eauto. eapply IHS1. eauto. omega.
  - eapply IHS1. eauto. omega. 
  - eapply IHS1. eauto. omega.
  (* stp right *)
  - eauto. 
  - econstructor. 
  - econstructor. 
  - econstructor. eapply IHS1. eauto. omega. eapply IHS2. eauto. omega.
  - econstructor. eapply IHS1. eauto. omega. eapply IHS2. eauto. omega. 
  - econstructor. simpl. eauto.
  - econstructor. eauto.
  - eapply closed_upgrade_gh. eapply IHS2. eapply H2. omega. simpl. omega.  
  - econstructor. econstructor. eapply index_max. eauto.
  - eapply closed_upgrade_gh. eapply IHH2 in H1. inversion H1. eauto. omega. simpl. omega.
  - econstructor. econstructor. eapply IHH1. eauto. omega.
  - econstructor. eauto.
  - eauto. 
  - econstructor. eauto.
  - eapply IHS2. eauto. omega. 
  - eapply IHS2. eauto. omega.
  - econstructor. eapply IHS2. eauto. omega. eapply IHS2. eauto. omega. 
  - eapply IHS2. eauto. omega.
  (* vtp left *)
  - eauto.
  - eapply index_max. eauto.
  - eapply index_max. eauto.
  - eapply index_max. eauto.
  - eapply IHV1. eauto. omega.
  - eapply IHV1. eauto. omega.
  - eapply IHV1. eauto. omega. 
  (* vtp right *)
  - econstructor.
  - econstructor.
  - change 0 with (length ([]:tenv)) at 1. econstructor. eapply IHS1. eauto. omega. eapply IHS2. eauto. omega.
  - change 0 with (length ([]:tenv)) at 1. econstructor. eapply IHS1. eauto. omega. eapply IHS2. eauto. omega.
  - econstructor. eauto. (* eapply IHV2 in H1. eauto. omega. *)
  - econstructor. econstructor. eapply index_max. eauto.
  - econstructor. eapply IHV2. eauto. omega. eapply IHV2. eauto. omega. 
  (* htp left *)
  - eapply index_max. eauto.
  - eapply IHH1. eauto. omega.
  - eapply IHH1. eauto. omega.
  (* htp right *)
  - eauto. 
  - eapply IHH1 in H1. eapply closed_open. simpl. eapply closed_upgrade_gh. eauto. omega. econstructor. eauto. omega. 
  - eapply closed_upgrade_gh. eapply IHS2. eauto. omega. rewrite H4. rewrite app_length. omega. 
  (* has_type *)
  - eapply closed_upgrade_gh. eapply IHV2. eauto. omega. omega.
  - eauto.
  - econstructor. eauto. eauto.
  - econstructor. eauto. eauto. 
  - eapply IHT in H1. inversion H1. eauto. omega.
  - eapply IHS2. eauto. omega. 
Qed.



Lemma vtp_extend : forall m v1 x G1 T2 n,
                      vtp m G1 x T2 n ->
                      vtp m (v1::G1) x T2 n.
Proof. intros. eapply all_extend. eauto. eauto. Qed.

Lemma htp_extend : forall v1 x GH G1 T2 n,
                      htp GH G1 x T2 n ->
                      htp GH (v1::G1) x T2 n.
Proof. intros. eapply all_extend. eauto. eauto. Qed.

Lemma stp2_extend : forall GH  v1 G1 T1 T2 n,
                      stp2 GH G1 T1 T2 n ->
                      stp2 GH (v1::G1) T1 T2 n.
Proof. intros. eapply all_extend. eauto. eauto. Qed.

Lemma stp2_extend_mult : forall GH G1 G' T1 T2 n,
                      stp2 GH G1 T1 T2 n ->
                      stp2 GH (G'++G1) T1 T2 n.
Proof. intros. induction G'. simpl. eauto. simpl. eapply stp2_extend. eauto. Qed. 

Lemma has_type_extend: forall GH G1 t T v n1,
  has_type GH G1 t T n1 ->
  has_type GH (v::G1) t T n1.
Proof. intros. eapply all_extend. eauto. eauto. Qed. 

Lemma has_type_extend_mult: forall GH G1 t T G' n1,
  has_type GH G1 t T n1 ->
  has_type GH (G'++G1) t T n1.
Proof. intros. induction G'. simpl. eauto. simpl. eapply has_type_extend. eauto. Qed. 




Lemma vtp_closed: forall m G1 x T2 n1,
  vtp m G1 x T2 n1 -> 
  closed 0 (length G1) 0 T2.
Proof. intros. eapply all_closed. eauto. eauto. Qed.

Lemma vtp_closed1: forall m G1 x T2 n1,
  vtp m G1 x T2 n1 -> 
  x < length G1.
Proof. intros. eapply all_closed. eauto. eauto. Qed.

Lemma has_type_closed: forall GH G1 t T n1,
  has_type GH G1 t T n1 ->
  closed (length GH) (length G1) 0 T.
Proof. intros. eapply all_closed. eauto. eauto. Qed.



Lemma stp2_closed1 : forall GH G1 T1 T2 n1,
                      stp2 GH G1 T1 T2 n1 ->
                      closed (length GH) (length G1) 0 T1.
Proof. intros. edestruct all_closed. eapply H0. eauto. eauto. Qed.

Lemma stp2_closed2 : forall GH G1 T1 T2 n1,
                      stp2 GH G1 T1 T2 n1 ->
                      closed (length GH) (length G1) 0 T2.
Proof. intros. edestruct all_closed. destruct H1. eapply H1. eauto. eauto. Qed.

Lemma stpd2_closed1 : forall GH G1 T1 T2,
                      stpd2 GH G1 T1 T2 ->
                      closed (length GH) (length G1) 0 T1.
Proof. intros. eu. eapply stp2_closed1. eauto. Qed. 


Lemma stpd2_closed2 : forall GH G1 T1 T2,
                      stpd2 GH G1 T1 T2 ->
                      closed (length GH) (length G1) 0 T2.
Proof. intros. eu. eapply stp2_closed2. eauto. Qed. 


Lemma beq_nat_true_eq: forall A, beq_nat A A = true.
Proof. intros. eapply beq_nat_true_iff. eauto. Qed.


Lemma stpd2_refl: forall GH G1 T1,
  closed (length GH) (length G1) 0 T1 ->
  stpd2 GH G1 T1 T1.
Proof.
  intros. induction T1; inversion H.
  - Case "bot". exists 1. eauto.
  - Case "top". exists 1. eauto.
  - Case "bool". eapply stpd2_bool; eauto.
  - Case "fun". eapply stpd2_fun; try eapply stpd2_wrapf; eauto.
  - Case "mem". eapply stpd2_mem; try eapply stpd2_wrapf; eauto.
  - Case "var0". exists 1. eauto. 
  - Case "var1".
    assert (exists v, index i G1 = Some v) as E. eapply index_exists; eauto.
    destruct E.
    eexists. eapply stp2_varx; eauto.
  - Case "varb". inversion H4. 
  - Case "sel". exists 1. eapply stp2_selx. eauto. 
  - Case "bind".
    eexists. eapply stp2_bindx. eapply htp_var. simpl. rewrite beq_nat_true_eq. eauto.
    instantiate (1:=open 0 (TVar false (length GH)) T1).
    eapply closed_open. simpl. eapply closed_upgrade_gh. eauto. omega. econstructor. simpl. omega.
    eauto. eauto. eauto. eauto.
  - Case "and".
    destruct IHT1_1. eauto. destruct IHT1_2. eauto.
    eexists. eapply stp2_and2. eapply stp2_and11. eauto. eauto. eapply stp2_and12. eauto. eauto. 
Grab Existential Variables.
apply 0. apply 0.
Qed.

Lemma stpd2_reg1 : forall GH G1 T1 T2,
                      stpd2 GH G1 T1 T2 ->
                      stpd2 GH G1 T1 T1.
Proof. intros. eapply stpd2_refl. eapply stpd2_closed1. eauto. Qed.

Lemma stpd2_reg2 : forall GH G1 T1 T2,
                      stpd2 GH G1 T1 T2 ->
                      stpd2 GH G1 T2 T2.
Proof. intros. eapply stpd2_refl. eapply stpd2_closed2. eauto. Qed.



Ltac index_subst := match goal with
                      | H1: index ?x ?G = ?V1 , H2: index ?x ?G = ?V2 |- _ => rewrite H1 in H2; inversion H2; subst
                      | _ => idtac
                    end.

Ltac invty := match goal with
                | H1: TBot     = _ |- _ => inversion H1
                | H1: TBool    = _ |- _ => inversion H1
                | H1: TSel _   = _ |- _ => inversion H1
                | H1: TMem _ _ = _ |- _ => inversion H1
                | H1: TVar _ _ = _ |- _ => inversion H1
                | H1: TFun _ _ = _ |- _ => inversion H1
                | H1: TBind  _ = _ |- _ => inversion H1
                | H1: TAnd _ _ = _ |- _ => inversion H1
                | _ => idtac
              end.

Ltac invstp_var := match goal with
  | H1: stp2 _ true _ _ TBot        (TVar _ _) _ |- _ => inversion H1
  | H1: stp2 _ true _ _ TTop        (TVar _ _) _ |- _ => inversion H1
  | H1: stp2 _ true _ _ TBool       (TVar _ _) _ |- _ => inversion H1
  | H1: stp2 _ true _ _ (TFun _ _)  (TVar _ _) _ |- _ => inversion H1
  | H1: stp2 _ true _ _ (TMem _ _)  (TVar _ _) _ |- _ => inversion H1
  | H1: stp2 _ true _ _ (TAnd _ _)  (TVar _ _) _ |- _ => inversion H1
  | _ => idtac
end.

Definition substt x T := (subst (TVar true x) T).

Hint Immediate substt.



Lemma closed_no_open: forall T x k l j,
  closed l k j T ->
  T = open j (TVar false x) T.
Proof.
  intros. induction H; intros; eauto;
  try solve [compute; compute in IHclosed; rewrite <-IHclosed; auto];
  try solve [compute; compute in IHclosed1; compute in IHclosed2; rewrite <-IHclosed1; rewrite <-IHclosed2; auto].

  Case "TSelB".
    simpl. 
    assert (k <> x0). omega.
    apply beq_nat_false_iff in H0.
    rewrite H0. auto.
Qed.


Lemma closed_no_subst: forall T j k TX,
   closed 0 j k T ->
   subst TX T = T.
Proof.
  intros T. induction T; intros; inversion H; simpl; eauto;
    try rewrite (IHT j (S k) TX); eauto;
    (* try rewrite (IHT2 (S j) TX); eauto; *)
    try rewrite (IHT j k TX); eauto;
    try rewrite (IHT1 j k TX); eauto;
    try rewrite (IHT2 j k TX); eauto.

  subst. inversion H4. 

  eapply closed_upgrade. eauto. eauto.
Qed.

Lemma closed_subst: forall j n k V T, closed (n+1) k j T -> closed n k 0 V -> closed n k j (subst V T).
Proof.
  intros. generalize dependent j. induction T; intros; inversion H; try econstructor; try eapply IHT1; eauto; try eapply IHT2; eauto; try eapply IHT; eauto.

  - Case "TSelH". simpl.
    case_eq (beq_nat i 0); intros E. eapply closed_upgrade. eapply closed_upgrade_gh. eauto. eauto. omega. econstructor. subst. 
    assert (i > 0). eapply beq_nat_false_iff in E. omega. omega.
Qed.

(* not used? *)
Lemma subst_open_commute_m: forall j k n m V T2, closed (n+1) k (j+1) T2 -> closed m k 0 V ->
    subst V (open j (TVar false (n+1)) T2) = open j (TVar false n) (subst V T2).
Proof.
  intros. generalize dependent j. generalize dependent n.
  induction T2; intros; inversion H; simpl; eauto;
          try rewrite IHT2_1; try rewrite IHT2_2; try rewrite IHT2; eauto.
  
  simpl. case_eq (beq_nat i 0); intros E.
  eapply closed_no_open. eapply closed_upgrade. eauto. omega.
  simpl. eauto.
  
  simpl. case_eq (beq_nat j i); intros E.
  simpl. case_eq (beq_nat (n+1) 0); intros E2. eapply beq_nat_true_iff in E2. omega.
  assert (n+1-1 = n) as A. omega. rewrite A. eauto.
  eauto.
Qed.

(* not used? *)
Lemma subst_open_commute: forall j k n V T2, closed (n+1) k (j+1) T2 -> closed 0 k 0 V ->
    subst V (open j (TVar false (n+1)) T2) = open j (TVar false n) (subst V T2).
Proof.
  intros. eapply subst_open_commute_m; eauto.
Qed.

Lemma subst_open_commute0: forall T0 n j TX,
  closed 0 n (j+1) T0 ->
  (subst TX (open j (TVar false 0) T0)) = open j TX T0.
Proof.
  intros T0 n. induction T0; intros.
  eauto. eauto. eauto.
  simpl. inversion H. rewrite IHT0_1. rewrite IHT0_2. eauto. eauto. eauto.
  simpl. inversion H. rewrite IHT0_1. rewrite IHT0_2. eauto. eauto. eauto.
  simpl. inversion H. omega. eauto.
  simpl. inversion H. subst. destruct i. case_eq (beq_nat j 0); intros E; simpl; eauto.
  case_eq (beq_nat j (S i)); intros E; simpl; eauto. 

  simpl. inversion H. rewrite IHT0. eauto. eauto.
  simpl. inversion H. rewrite IHT0. eauto. subst. eauto.
  simpl. inversion H. rewrite IHT0_1. rewrite IHT0_2. eauto. eauto. eauto.
Qed.


Lemma subst_open_commute1: forall T0 x x0 j,
 (open j (TVar true x0) (subst (TVar true x) T0)) 
 = (subst (TVar true x) (open j (TVar true x0) T0)).
Proof.
  induction T0; intros.
  eauto. eauto. eauto. 
  simpl. rewrite IHT0_1. rewrite IHT0_2. eauto. eauto. eauto.
  simpl. rewrite IHT0_1. rewrite IHT0_2. eauto. eauto. eauto.
  simpl. destruct b. simpl. eauto.
  case_eq (beq_nat i 0); intros E. simpl. eauto. simpl. eauto.

  simpl. case_eq (beq_nat j i); intros E. simpl. eauto. simpl. eauto.

  simpl. rewrite IHT0. eauto.
  simpl. rewrite IHT0. eauto.
  simpl. rewrite IHT0_1. rewrite IHT0_2. eauto. 
Qed.


Lemma subst_closed_id: forall x j k T2,
  closed 0 j k T2 ->
  substt x T2 = T2.
Proof. intros. eapply closed_no_subst. eauto. Qed. 

Lemma closed_subst0: forall i j k x T2,
  closed (i + 1) j k T2 -> x < j ->
  closed i j k (substt x T2).
Proof. intros. eapply closed_subst. eauto. econstructor. eauto. Qed.

Lemma closed_subst1: forall i j k x T2,
  closed i j k T2 -> x < j -> i <> 0 ->
  closed (i-1) j k (substt x T2).
Proof.
  intros. eapply closed_subst.
  assert ((i - 1 + 1) = i) as R. omega.
  rewrite R. eauto. econstructor. eauto.
Qed.

Lemma index_subst: forall GH TX T0 T3 x,
  index (length (GH ++ [TX])) (T0 :: GH ++ [TX]) = Some T3 ->
  index (length GH) (map (substt x) (T0 :: GH)) = Some (substt x T3).
Proof.
  intros GH. induction GH; intros; inversion H.
  - eauto.
  - rewrite beq_nat_true_eq in H1. inversion H1. subst. simpl.
    rewrite map_length. rewrite beq_nat_true_eq. eauto.
Qed.

Lemma index_subst1: forall GH TX T3 x x0,
  index x0 (GH ++ [TX]) = Some T3 -> x0 <> 0 ->
  index (x0-1) (map (substt x) GH) = Some (substt x T3).
Proof.
  intros GH. induction GH; intros; inversion H.
  - eapply beq_nat_false_iff in H0. rewrite H0 in H2. inversion H2.
  - simpl.
    assert (beq_nat (x0 - 1) (length (map (substt x) GH)) = beq_nat x0 (length (GH ++ [TX]))). {
      case_eq (beq_nat x0 (length (GH ++ [TX]))); intros E.
      eapply beq_nat_true_iff. rewrite map_length. eapply beq_nat_true_iff in E. subst x0.
      rewrite app_length. simpl. omega.
      eapply beq_nat_false_iff. eapply beq_nat_false_iff in E.
      rewrite app_length in E. simpl in E. rewrite map_length.
      destruct x0. destruct H0. reflexivity. omega.
    }
    rewrite H1. case_eq (beq_nat x0 (length (GH ++ [TX]))); intros E; rewrite E in H2.
    inversion H2. subst. eauto. eauto. 
Qed.

Lemma index_hit0: forall (GH:tenv) TX T2,
 index 0 (GH ++ [TX]) = Some T2 -> T2 = TX.
Proof.
  intros GH. induction GH; intros; inversion H.
  - eauto.
  - rewrite app_length in H1. simpl in H1.
    remember (length GH + 1) as L. destruct L. omega. eauto.
Qed. 

Lemma subst_open: forall TX n x j,
  (substt x (open j (TVar false (n+1)) TX)) =
  (open j (TVar false n) (substt x TX)).
Proof.
  intros TX. induction TX; intros; eauto.
  - unfold substt. simpl. unfold substt in IHTX1. unfold substt in IHTX2. erewrite <-IHTX1. erewrite <-IHTX2. eauto.
  - unfold substt. simpl. unfold substt in IHTX1. unfold substt in IHTX2. erewrite <-IHTX1. erewrite <-IHTX2. eauto.
  - unfold substt. simpl. destruct b. eauto.
    case_eq (beq_nat i 0); intros E. eauto. eauto.
  - unfold substt. simpl.
    case_eq (beq_nat j i); intros E. simpl. 
    assert (beq_nat (n + 1) 0 = false). eapply beq_nat_false_iff. omega.
    assert ((n + 1 - 1 = n)). omega. 
    rewrite H. rewrite H0. eauto. eauto.
  - unfold substt. simpl. unfold substt in IHTX. erewrite <-IHTX. eauto.
  - unfold substt. simpl. unfold substt in IHTX. erewrite <-IHTX. eauto.
  - unfold substt. simpl. unfold substt in IHTX1. unfold substt in IHTX2. erewrite <-IHTX1. erewrite <-IHTX2. eauto.
Qed.

Lemma subst_open3: forall TX0 (GH:tenv) TX  x,
  (substt x (open 0 (TVar false (length (GH ++ [TX]))) TX0)) =
  (open 0 (TVar false (length GH)) (substt x TX0)).
Proof. intros. rewrite app_length. simpl. eapply subst_open. Qed.

Lemma subst_open4: forall T0 (GH:tenv) TX x, 
  substt x (open 0 (TVar false (length (GH ++ [TX]))) T0) =
  open 0 (TVar false (length (map (substt x) GH))) (substt x T0).
Proof. intros. rewrite map_length. eapply subst_open3. Qed.

Lemma subst_open5: forall (GH:tenv) T0 x xi, 
  xi <> 0 -> substt x (open 0 (TVar false xi) T0) =
  open 0 (TVar false (xi-1)) (substt x T0).
Proof.
  intros. remember (xi-1) as n. assert (xi=n+1) as R. omega. rewrite R.
  eapply subst_open.
Qed.

Lemma gh_match1: forall (GU:tenv) GH GL TX,
  GH ++ [TX] = GU ++ GL ->
  length GL > 0 ->
  exists GL1, GL = GL1 ++ [TX] /\ GH = GU ++ GL1.
Proof.
  intros GU. induction GU; intros.
  - eexists. simpl in H. eauto. 
  - destruct GH. simpl in H.
    assert (length [TX] = 1). eauto.
    rewrite H in H1. simpl in H1. rewrite app_length in H1. omega.
    destruct (IHGU GH GL TX).
    simpl in H. inversion H. eauto. eauto.
    eexists. split. eapply H1. simpl. destruct H1. simpl in H. inversion H. subst. eauto.
Qed.

Lemma gh_match: forall (GH:tenv) GU GL TX T0,
  T0 :: GH ++ [TX] = GU ++ GL ->
  length GL = S (length (GH ++ [TX])) ->
  GU = [] /\ GL = T0 :: GH ++ [TX].
Proof.
  intros. edestruct gh_match1. rewrite app_comm_cons in H. eapply H. omega.
  assert (length (T0 :: GH ++ [TX]) = length (GU ++ GL)). rewrite H. eauto.
  assert (GU = []). destruct GU. eauto. simpl in H.
  simpl in H2. rewrite app_length in H2. simpl in H2. rewrite app_length in H2.
  simpl in H2. rewrite H0 in H2. rewrite app_length in H2. simpl in H2.
  omega.
  split. eauto. rewrite H3 in H1. simpl in H1. subst. simpl in H1. eauto.
Qed.

Lemma sub_env1: forall (GL:tenv) GU GH TX,
  GH ++ [TX] = GU ++ GL ->
  length GL = 1 ->
  GL = [TX].
Proof.
  intros.
  destruct GL. inversion H0. destruct GL.
  eapply app_inj_tail in H. destruct H. subst. eauto.
  inversion H0.
Qed. 

Lemma app_cons1: forall (G1:venv) v,
  v::G1 = [v]++G1.
Proof.
  intros. simpl. eauto. 
Qed.



Lemma stp2_subst_narrow0: forall n, forall GH G1 T1 T2 TX x n2,
   stp2 (GH++[TX]) G1 T1 T2 n2 -> x < length G1 -> n2 < n -> 
   (forall GH (T3 : ty) (n1 : nat),
      htp (GH++[TX]) G1 0 T3 n1 -> n1 < n ->
      exists m2, vtpd m2 G1 x (substt x T3)) ->
   stpd2 (map (substt x) GH) G1 (substt x T1) (substt x T2).
Proof.
  intros n. induction n. intros. omega.
  intros ? ? ? ? ? ? ? ? ? ? narrowX.

  (* helper lemma for htp *)
  assert (forall ni n2, forall GH T2 xi,
    htp (GH ++ [TX]) G1 xi T2 n2 -> xi <> 0 -> n2 < ni -> ni < S n ->
    htpd (map (substt x) GH) G1 (xi-1) (substt x T2)) as htp_subst_narrow02. {
      induction ni. intros. omega. 
      intros. inversion H2.
      + (* var *) subst.
        repeat eexists. eapply htp_var. eapply index_subst1. eauto. eauto.
        rewrite map_length. eauto. eapply closed_subst0. rewrite app_length in H7. eapply H7. eauto.
      + (* bind *) subst.
        assert (htpd (map (substt x) (GH0)) G1 (xi-1) (substt x (TBind TX0))) as BB.
        eapply IHni. eapply H6. eauto. omega. omega.
        rewrite subst_open5. 
        eu. repeat eexists. eapply htp_bind. eauto. eapply closed_subst1. eauto. eauto. eauto. apply []. eauto.
      + (* sub *) subst.
        assert (exists GL0, GL = GL0 ++ [TX] /\ GH0 = GU ++ GL0) as A. eapply gh_match1. eauto. omega.
        destruct A as [GL0 [? ?]]. subst GL.
        assert (htpd (map (substt x) GH0) G1 (xi-1) (substt x T3)) as AA.
        eapply IHni. eauto. eauto. omega. omega. 
        assert (stpd2 (map (substt x) GL0) G1 (substt x T3) (substt x T0)) as BB.
        eapply IHn. eauto. eauto. omega. { intros. eapply narrowX. eauto. eauto. }
        eu. eu. repeat eexists. eapply htp_sub. eauto. eauto.
        (* - *)
        rewrite map_length. rewrite app_length in H8. simpl in H8. omega.
        subst GH0. rewrite map_app. eauto. 
  }
  (* special case *)                                                                                   
  assert (forall ni n2, forall T0 T2,
    htp (T0 :: GH ++ [TX]) G1 (length (GH ++ [TX])) T2 n2 -> n2 < ni -> ni < S n ->
    htpd (map (substt x) (T0::GH)) G1 (length GH) (substt x T2)) as htp_subst_narrow0. {
      intros.
      rewrite app_comm_cons in H2. 
      remember (T0::GH) as GH1. remember (length (GH ++ [TX])) as xi.
      rewrite app_length in Heqxi. simpl in Heqxi.
      assert (length GH = xi-1) as R. omega.
      rewrite R. eapply htp_subst_narrow02. eauto. omega. eauto. eauto. 
  }

                                                                                               
  (* main logic *)  
  inversion H.
  - Case "bot". subst.
    eapply stpd2_bot; eauto. rewrite map_length. simpl. eapply closed_subst0. rewrite app_length in H2. simpl in H2. eapply H2. eauto.
  - Case "top". subst.
    eapply stpd2_top; eauto. rewrite map_length. simpl. eapply closed_subst0. rewrite app_length in H2. simpl in H2. eapply H2. eauto.
  - Case "bool". subst.
    eapply stpd2_bool; eauto.
  - Case "fun". subst.
    eapply stpd2_fun. eapply IHn; eauto. omega. eapply IHn; eauto. omega.
  - Case "mem". subst.
    eapply stpd2_mem. eapply IHn; eauto. omega. eapply IHn; eauto. omega.


  - Case "varx". subst.
    eexists. eapply stp2_varx. eauto.
  - Case "varax". subst.
    case_eq (beq_nat x0 0); intros E.
    + (* hit *)
      assert (x0 = 0). eapply beq_nat_true_iff. eauto. 
      repeat eexists. unfold substt. subst x0. simpl. eapply stp2_varx. eauto. 
    + (* miss *)
      assert (x0 <> 0). eapply beq_nat_false_iff. eauto. 
      repeat eexists. unfold substt. simpl. rewrite E. eapply stp2_varax. rewrite map_length. rewrite app_length in H2. simpl in H2. omega. 
  - Case "ssel1". subst. 
    assert (substt x T2 = T2) as R. eapply subst_closed_id. eapply stpd2_closed2 with (GH:=[]). eauto. 
    eexists. eapply stp2_strong_sel1. eauto. rewrite R. eauto. 
    
  - Case "ssel2". subst. 
    assert (substt x T1 = T1) as R. eapply subst_closed_id. eapply stpd2_closed1 with (GH:=[]). eauto. 
    eexists. eapply stp2_strong_sel2. eauto. rewrite R. eauto. 

  - Case "sel1". subst. (* invert htp to vtp and create strong_sel node *)
    case_eq (beq_nat x0 0); intros E.
    + assert (x0 = 0). eapply beq_nat_true_iff. eauto. subst x0.
      assert (exists m0, vtpd m0 G1 x (substt x (TMem TBot T2))) as A. eapply narrowX. eauto. omega.
      destruct A as [? A]. eu. inversion A. subst.
      repeat eexists. eapply stp2_strong_sel1. eauto. unfold substt. 
      eauto.
    + assert (x0 <> 0). eapply beq_nat_false_iff. eauto.
      eapply htp_subst_narrow02 in H2. 
      eu. repeat eexists. unfold substt. simpl. rewrite E. eapply stp2_sel1. eapply H2. eauto. eauto. eauto. 
      
  - Case "sel2". subst. (* invert htp to vtp and create strong_sel node *)
    case_eq (beq_nat x0 0); intros E.
    + assert (x0 = 0). eapply beq_nat_true_iff. eauto. subst x0.
      assert (exists m0, vtpd m0 G1 x (substt x (TMem T1 TTop))) as A. eapply narrowX. eauto. omega.
      destruct A as [? A]. eu. inversion A. subst. 
      repeat eexists. eapply stp2_strong_sel2. eauto. unfold substt. 
      eauto.
    + assert (x0 <> 0). eapply beq_nat_false_iff. eauto.
      eapply htp_subst_narrow02 in H2. 
      eu. repeat eexists. unfold substt. simpl. rewrite E. eapply stp2_sel2. eapply H2. eauto. eauto. eauto. 
  - Case "selx".
    eexists. eapply stp2_selx. eapply closed_subst0. rewrite app_length in H2. simpl in H2. rewrite map_length. eauto. eauto.
      
  - Case "bind1". 
    assert (htpd (map (substt x) (T1'::GH)) G1 (length GH) (substt x T2)). 
    eapply htp_subst_narrow0. eauto. eauto. omega. 
    eu. repeat eexists. eapply stp2_bind1. rewrite map_length. eapply H11.
    simpl. subst T1'. fold subst. eapply subst_open4.
    fold subst. eapply closed_subst0. rewrite app_length in H4. simpl in H4. rewrite map_length. eauto. eauto. 
    eapply closed_subst0. rewrite map_length. rewrite app_length in H5. simpl in H5. eauto. eauto.
   
  - Case "bindx". 
    assert (htpd (map (substt x) (T1'::GH)) G1 (length GH) (substt x T2')). 
    eapply htp_subst_narrow0. eauto. eauto. omega. 
    eu. repeat eexists. eapply stp2_bindx. rewrite map_length. eapply H12. 
    subst T1'. fold subst. eapply subst_open4. 
    subst T2'. fold subst. eapply subst_open4.
    rewrite app_length in H5. simpl in H5. eauto. eapply closed_subst0. rewrite map_length. eauto. eauto.
    rewrite app_length in H6. simpl in H6. eauto. eapply closed_subst0. rewrite map_length. eauto. eauto.

  - Case "and11".
    assert (stpd2 (map (substt x) GH) G1 (substt x T0) (substt x T2)). eapply IHn. eauto. eauto. omega. eauto. 
    eu. eexists. eapply stp2_and11. eauto. eapply closed_subst0. rewrite app_length in H3. rewrite map_length. eauto. eauto. 
  - Case "and12".
    assert (stpd2 (map (substt x) GH) G1 (substt x T3) (substt x T2)). eapply IHn. eauto. eauto. omega. eauto. 
    eu. eexists. eapply stp2_and12. eauto. eapply closed_subst0. rewrite app_length in H3. rewrite map_length. eauto. eauto. 
  - Case "and2".
    assert (stpd2 (map (substt x) GH) G1 (substt x T1) (substt x T0)). eapply IHn. eauto. eauto. omega. eauto. 
    assert (stpd2 (map (substt x) GH) G1 (substt x T1) (substt x T3)). eapply IHn. eauto. eauto. omega. eauto. 
    eu. eu. eexists. eapply stp2_and2. eauto. eauto. 
    
  - Case "transf". 
    assert (stpd2 (map (substt x) GH) G1 (substt x T1) (substt x T3)).
    eapply IHn; eauto. omega.
    assert (stpd2 (map (substt x) GH) G1 (substt x T3) (substt x T2)).
    eapply IHn; eauto. omega.
    eu. eu. repeat eexists. eapply stp2_transf. eauto. eauto. 
    
Grab Existential Variables.
apply 0. apply 0. apply 0. apply 0. apply 0.
Qed. 


Lemma stp2_subst_narrowX: forall ml, forall nl, forall m GH G1 T2 TX x n1 n2,
   vtp m G1 x (substt x TX) n1 ->
   htp (GH++[TX]) G1 0 T2 n2 -> x < length G1 -> m < ml -> n2 < nl ->
   (forall (m0 : nat) (G1 : venv) x (T2 T3 : ty) (n1 n2 : nat),
        vtp m0 G1 x T2 n1 ->
        stp2 [] G1 T2 T3 n2 -> m0 <= m ->
        vtpdd m0 G1 x T3) ->
   vtpdd m G1 x (substt x T2). (* decrease b/c transitivity *)
Proof. 
  intros ml. (* induction ml. intros. omega. *)
  intros nl. induction nl. intros. omega.
  intros.
  inversion H0.
  - Case "var". subst.
    assert (T2 = TX). eapply index_hit0. eauto. 
    subst T2.
    repeat eexists. eauto. eauto. 
  - Case "bind". subst.
    assert (vtpdd m G1 x (substt x (TBind TX0))) as A.
    eapply IHnl. eauto. eauto. eauto. eauto. omega. eauto.
    destruct A as [? [? [A ?]]]. inversion A. subst.
    repeat eexists. unfold substt. erewrite subst_open_commute0.
    assert (closed 0 (length G1) 0 (TBind (substt x TX0))). eapply vtp_closed. unfold substt in A. simpl in A. eapply A.
    assert ((substt x (TX0)) = TX0) as R. eapply subst_closed_id. eauto.
    unfold substt in R. rewrite R in H9. eapply H9. simpl. eauto. omega.
  - Case "sub". subst. 
    assert (GL = [TX]). eapply sub_env1; eauto. subst GL.
    assert (vtpdd m G1 x (substt x T1)) as A.
    eapply IHnl. eauto. eauto. eauto. eauto. omega. eauto. 
    eu.
    assert (stpd2 (map (substt x) []) G1 (substt x T1) (substt x T2)) as B.
    eapply stp2_subst_narrow0. eauto. eauto. eauto. {
      intros. eapply IHnl in H. eu. repeat eexists. eauto. eauto. eauto. eauto. omega. eauto. 
    }
    simpl in B. eu. 
    assert (vtpdd x0 G1 x (substt x T2)).
    eapply H4. eauto. eauto. eauto.
    eu. repeat eexists. eauto. omega. 
Qed.



Lemma vtp_widen: forall l, forall n, forall k, forall m1 G1 x T2 T3 n1 n2,
  vtp m1 G1 x T2 n1 -> 
  stp2 [] G1 T2 T3 n2 ->
  m1 < l -> n2 < n -> n1 < k -> 
  vtpdd m1 G1 x T3.
Proof.
  intros l. induction l. intros. solve by inversion.
  intros n. induction n. intros. solve by inversion.
  intros k. induction k; intros. solve by inversion.
  inversion H.
  - Case "top". inversion H0; subst; invty.
    + SCase "top". repeat eexists; eauto.
    + SCase "ssel2".
      assert (vtpdd m1 G1 x TX). eapply IHn; eauto. omega. 
      eu. repeat eexists. eapply vtp_sel. eauto. eauto. eauto.
    + SCase "sel2".
      eapply stp2_closed2 in H0. simpl in H0. inversion H0. inversion H9. omega.
    + SCase "and".
      assert (vtpdd m1 G1 x T1). eapply IHn; eauto. omega. eu. 
      assert (vtpdd m1 G1 x T0). eapply IHn; eauto. omega. eu.
      repeat eexists. eapply vtp_and; eauto. eauto.
    + SCase "trans".
      assert (vtpdd m1 G1 x T0) as LHS. eapply IHn. eauto. eauto. eauto. omega. eauto. eu.
      assert (vtpdd x0 G1 x T3) as BB. eapply IHn. eapply LHS. eauto. omega. omega. eauto. eu.
      repeat eexists. eauto. omega. 
  - Case "bool". inversion H0; subst; invty.
    + SCase "top". repeat eexists. eapply vtp_top. eapply index_max. eauto. eauto. 
    + SCase "bool". repeat eexists; eauto. 
    + SCase "ssel2". 
      assert (vtpdd m1 G1 x TX). eapply IHn; eauto. omega. 
      eu. repeat eexists. eapply vtp_sel. eauto. eauto. eauto.
    + SCase "sel2". 
      eapply stp2_closed2 in H0. simpl in H0. inversion H0. inversion H9. omega.  
    + SCase "and".
      assert (vtpdd m1 G1 x T1). eapply IHn; eauto. omega. eu. 
      assert (vtpdd m1 G1 x T0). eapply IHn; eauto. omega. eu.
      repeat eexists. eapply vtp_and; eauto. eauto.
    + SCase "trans".
      assert (vtpdd m1 G1 x T0) as LHS. eapply IHn. eauto. eauto. eauto. omega. eauto. eu.
      assert (vtpdd x0 G1 x T3) as BB. eapply IHn. eapply LHS. eauto. omega. omega. eauto. eu.
      repeat eexists. eauto. omega. 
  - Case "mem". inversion H0; subst; invty.
    + SCase "top". repeat eexists. eapply vtp_top. eapply index_max. eauto. eauto. 
    + SCase "mem". invty. subst.
      repeat eexists. eapply vtp_mem. eauto.
      eapply stp2_transf. eauto. eapply H5.
      eapply stp2_transf. eauto. eapply H13.
      eauto. 
    + SCase "sel2". 
      assert (vtpdd m1 G1 x TX0). eapply IHn; eauto. omega. 
      eu. repeat eexists. eapply vtp_sel. eauto. eauto. eauto. 
    + SCase "sel2". 
      eapply stp2_closed2 in H0. simpl in H0. inversion H0. inversion H11. omega.
    + SCase "and".
      assert (vtpdd m1 G1 x T4). eapply IHn; eauto. omega. eu. 
      assert (vtpdd m1 G1 x T5). eapply IHn; eauto. omega. eu.
      repeat eexists. eapply vtp_and; eauto. eauto.
    + SCase "trans".
      assert (vtpdd m1 G1 x T5) as LHS. eapply IHn. eauto. eauto. eauto. omega. eauto. eu.
      assert (vtpdd x0 G1 x T3) as BB. eapply IHn. eapply LHS. eauto. omega. omega. eauto. eu.
      repeat eexists. eauto. omega. 
  - Case "fun". inversion H0; subst; invty.
    + SCase "top". repeat eexists. eapply vtp_top. eapply index_max. eauto. eauto. 
    + SCase "fun". invty. subst.
      repeat eexists. eapply vtp_fun. eauto. eauto. 
      eapply stp2_transf. eauto. eapply H6.
      eapply stp2_transf. eauto. eapply H14.
      eauto. 
    + SCase "sel2". 
      assert (vtpdd m1 G1 x TX). eapply IHn; eauto. omega. 
      eu. repeat eexists. eapply vtp_sel. eauto. eauto. eauto. 
    + SCase "sel2". 
      eapply stp2_closed2 in H0. simpl in H0. inversion H0. inversion H12. omega.
    + SCase "and".
      assert (vtpdd m1 G1 x T6). eapply IHn; eauto. omega. eu. 
      assert (vtpdd m1 G1 x T7). eapply IHn; eauto. omega. eu.
      repeat eexists. eapply vtp_and; eauto. eauto.
    + SCase "trans".
      assert (vtpdd m1 G1 x T7) as LHS. eapply IHn. eauto. eauto. eauto. omega. eauto. eu.
      assert (vtpdd x0 G1 x T3) as BB. eapply IHn. eapply LHS. eauto. omega. omega. eauto. eu.
      repeat eexists. eauto. omega. 
  - Case "bind". 
    inversion H0; subst; invty.
    + SCase "top". repeat eexists. eapply vtp_top. eapply vtp_closed1. eauto. eauto. 
    + SCase "sel2". 
      assert (vtpdd (S m) G1 x TX). eapply IHn; eauto. omega. 
      eu. repeat eexists. eapply vtp_sel. eauto. eauto. eauto. 
    + SCase "sel2". 
      eapply stp2_closed2 in H0. simpl in H0. inversion H0. inversion H10. omega.  
    + SCase "bind1".
      invty. subst.
      remember (TVar false (length [])) as VZ.
      remember (TVar true x) as VX.

      (* left *)
      assert (vtpd m G1 x (open 0 VX T0)) as LHS. eexists. eassumption.
      eu.
      (* right *)
      assert (substt x (open 0 VZ T0) = (open 0 VX T0)) as R. unfold substt. subst. eapply subst_open_commute0. eauto. 
      assert (substt x T3 = T3) as R1. eapply subst_closed_id. eauto. 

      assert (vtpdd m G1 x (substt x T3)) as BB. {
        eapply stp2_subst_narrowX. rewrite <-R in LHS. eapply LHS.
        instantiate (2:=nil). simpl. eapply H11. eapply vtp_closed1. eauto. eauto. eauto. 
        { intros. eapply IHl. eauto. eauto. omega. eauto. eauto. }
      }
      rewrite R1 in BB. 
      eu. repeat eexists. eauto. omega. 
    + SCase "bindx".
      invty. subst.
      remember (TVar false (length [])) as VZ.
      remember (TVar true x) as VX.

      (* left *)
      assert (vtpd m G1 x (open 0 VX T0)) as LHS. eexists. eassumption.
      eu.
      (* right *)
      assert (substt x (open 0 VZ T0) = (open 0 VX T0)) as R. unfold substt. subst. eapply subst_open_commute0. eauto.

      assert (vtpdd m G1 x (substt x (open 0 VZ T4))) as BB. {
        eapply stp2_subst_narrowX. rewrite <-R in LHS. eapply LHS.
        instantiate (2:=nil). simpl. eapply H11. eapply vtp_closed1. eauto. eauto. eauto. 
        { intros. eapply IHl. eauto. eauto. omega. eauto. eauto. }
      }
      unfold substt in BB. subst. erewrite subst_open_commute0 in BB. 
      clear R.
      eu. repeat eexists. eapply vtp_bind. eauto. eauto. omega. eauto. (* enough slack to add bind back *)
    + SCase "and".
      assert (vtpdd (S m) G1 x T1). eapply IHn; eauto. omega. eu. 
      assert (vtpdd (S m) G1 x T4). eapply IHn; eauto. omega. eu.
      repeat eexists. eapply vtp_and; eauto. eauto.
    + SCase "trans".
      assert (vtpdd (S m) G1 x T4) as LHS. eapply IHn. eauto. eauto. eauto. omega. eauto. eu.
      assert (vtpdd x0 G1 x T3) as BB. eapply IHn. eapply LHS. eauto. omega. omega. eauto. eu.
      repeat eexists. eauto. omega. 
  - Case "ssel2". subst. inversion H0; subst; invty.
    + SCase "top". repeat eexists. eapply vtp_top. eapply vtp_closed1. eauto. eauto. 
    + SCase "ssel1". index_subst. eapply IHn. eauto. eauto. eauto. omega. eauto.
    + SCase "ssel2". 
      assert (vtpdd m1 G1 x TX0). eapply IHn; eauto. omega. 
      eu. repeat eexists. eapply vtp_sel. eauto. eauto. eauto.
    + SCase "sel1".
      assert (closed (length ([]:tenv)) (length G1) 0 (TSel (TVar false x0))).
      eapply stpd2_closed2. eauto.
      simpl in H7. inversion H7. inversion H12. omega.
    + SCase "selx".
      eauto. 
    + SCase "and".
      assert (vtpdd m1 G1 x T1). eapply IHn; eauto. omega. eu. 
      assert (vtpdd m1 G1 x T2). eapply IHn; eauto. omega. eu.
      repeat eexists. eapply vtp_and; eauto. eauto.
    + SCase "trans".
      assert (vtpdd m1 G1 x T2) as LHS. eapply IHn. eauto. eauto. eauto. omega. eauto. eu.
      assert (vtpdd x0 G1 x T3) as BB. eapply IHn. eapply LHS. eauto. omega. omega. eauto. eu.
      repeat eexists. eauto. omega. 
  - Case "and". subst. inversion H0; subst; invty.
    + SCase "top". repeat eexists. eapply vtp_top. eapply vtp_closed1. eauto. eauto. 
    + SCase "sel2". 
      assert (vtpdd m1 G1 x TX). eapply IHn; eauto. omega. 
      eu. repeat eexists. eapply vtp_sel. eauto. eauto. eauto. 
    + SCase "sel2". 
      eapply stp2_closed2 in H0. simpl in H0. inversion H0. inversion H13. omega.
    + SCase "and11". eapply IHn in H4. eu. repeat eexists. eauto. omega. eauto. omega. omega. eauto.
    + SCase "and12". eapply IHn in H5. eu. repeat eexists. eauto. omega. eauto. omega. omega. eauto. 
    + SCase "and".
      assert (vtpdd m1 G1 x T2). eapply IHn; eauto. omega. eu. 
      assert (vtpdd m1 G1 x T4). eapply IHn; eauto. omega. eu.
      repeat eexists. eapply vtp_and; eauto. eauto.
    + SCase "trans".
      assert (vtpdd m1 G1 x T4) as LHS. eapply IHn. eauto. eauto. eauto. omega. eauto. eu.
      assert (vtpdd x0 G1 x T3) as BB. eapply IHn. eapply LHS. eauto. omega. omega. eauto. eu.
      repeat eexists. eauto. omega. 

Grab Existential Variables.
apply 0. apply 0. apply 0. apply 0. apply 0. apply 0.
Qed.



(* Reduction semantics  *)


Fixpoint subst_tm (u:nat) (T : tm) {struct T} : tm :=
  match T with
    | tvar true i         => tvar true i
    | tvar false i        => if beq_nat i 0 then (tvar true u) else tvar false (i-1)
    | tbool b             => tbool b
    | tobj (dty T)        => tobj (dty (subst (TVar true u) T))
    | tobj (dfun T1 T2 t) => tobj (dfun (subst (TVar true u) T1) (subst (TVar true u) T2) (subst_tm u t))
    | tapp t1 t2          => tapp (subst_tm u t1) (subst_tm u t2)
  end.


Inductive step : venv -> tm -> venv -> tm -> Prop :=
| ST_Obj : forall G1 D,
    step G1 (tobj D) (vobj D::G1) (tvar true (length G1))
| ST_AppAbs : forall G1 f x T1 T2 t12,
    index f G1 = Some (vobj (dfun T1 T2 t12)) ->
    step G1 (tapp (tvar true f) (tvar true x)) G1 (subst_tm x t12)
| ST_App1 : forall G1 G1' t1 t1' t2,
    step G1 t1 G1' t1' ->
    step G1 (tapp t1 t2) G1' (tapp t1' t2)
| ST_App2 : forall G1 G1' f t2 t2',
    step G1 t2 G1' t2' ->
    step G1 (tapp (tvar true f) t2) G1' (tapp (tvar true f) t2')
.



Lemma hastp_inv: forall G1 x T n1,
  has_type [] G1 (tvar true x) T n1 ->
  exists m n1, vtp m G1 x T n1.
Proof.
  intros. remember [] as GH. remember (tvar true x) as t.
  induction H; subst; try inversion Heqt.
  - Case "varx". subst. repeat eexists. eauto.
  - Case "sub".
    destruct IHhas_type. eauto. eauto. ev.
    assert (exists m0, vtpdd m0 G1 x T2). eexists. eapply vtp_widen; eauto. 
    ev. eu. repeat eexists. eauto. 
Qed.

Lemma hastp_subst: forall m G1 GH TX T x t n1 n2,
  has_type (GH++[TX]) G1 t T n2 ->
  vtp m G1 x TX n1 ->
  exists n3, has_type (map (substt x) GH) G1 (subst_tm x t) (substt x T) n3.
Proof.
  intros. remember (GH++[TX]) as GH0. revert GH HeqGH0. induction H; intros.
  - Case "varx". simpl. eexists. eapply T_Varx. erewrite subst_closed_id. eauto. eapply vtp_closed. eauto.
  - Case "vary". subst. simpl.
    case_eq (beq_nat x0 0); intros E.
    + assert (x0 = 0). eapply beq_nat_true_iff; eauto. subst x0.
      eexists. eapply T_Varx. eapply index_hit0 in H. subst. erewrite subst_closed_id. eauto. eapply vtp_closed. eauto. 
    + assert (x0 <> 0). eapply beq_nat_false_iff; eauto.
      eexists. eapply T_Vary. eapply index_subst1. eauto. eauto. rewrite map_length. eapply closed_subst0. rewrite app_length in H1. simpl in H1. eapply H1. eapply vtp_closed1. eauto.
  - Case "mem". subst. simpl.
    eexists. eapply T_Mem. eapply closed_subst0. rewrite app_length in H. rewrite map_length. eauto. eapply vtp_closed1. eauto.
  - Case "abs". subst. simpl.
    assert (has_typed (map (substt x) (T11::GH0)) G1 (subst_tm x t12) (substt x T12)) as HI.
    eapply IHhas_type. eauto. eauto.
    eu. simpl in HI. 
    eexists. eapply T_Abs. eapply HI. eapply closed_subst0. rewrite map_length. rewrite app_length in H1. simpl in H1. eauto. eauto. eapply vtp_closed1. eauto.
    eapply closed_subst0. rewrite map_length. rewrite app_length in H2. simpl in H2. eauto. eapply vtp_closed1. eauto.
  - Case "app".
    edestruct IHhas_type1. eauto. eauto.
    edestruct IHhas_type2. eauto. eauto. 
    eexists. eapply T_App. eapply H2. eapply H3. 
  - Case "sub". subst. 
    edestruct stp2_subst_narrow0. eapply H1. eapply vtp_closed1. eauto. eauto. 
    { intros. edestruct stp2_subst_narrowX. erewrite subst_closed_id.
      eapply H0. eapply vtp_closed. eauto. eauto. eapply vtp_closed1. eauto. eauto. eauto.
      { intros. eapply vtp_widen; eauto. }
      ev. repeat eexists. eauto.
    }
    edestruct IHhas_type. eauto. eauto.
    eexists. eapply T_Sub. eauto. eauto.
Grab Existential Variables.
  apply 0. apply 0.
Qed.

Theorem type_safety : forall G t T n1,
  has_type [] G t T n1 ->
  (exists x, t = tvar true x) \/
  (exists G' t' n2, step G t (G'++G) t' /\ has_type [] (G'++G) t' T n2).
Proof. 
  intros.
  assert (closed (length ([]:tenv)) (length G) 0 T) as CL. eapply has_type_closed. eauto. 
  remember [] as GH. remember t as tt. remember T as TT.
  revert T t HeqTT HeqGH Heqtt CL. 
  induction H; intros. 
  - Case "varx". eauto. 
  - Case "vary". subst GH. inversion H. 
  - Case "mem". right.
    assert (stpd2 [] (vobj (dty T11)::G1) T11 T11).
    eapply stpd2_refl. subst. eapply closed_extend. eauto. 
    eu. repeat eexists. rewrite <-app_cons1. eapply ST_Obj. eapply T_Varx. eapply vtp_mem.
    simpl. rewrite beq_nat_true_eq. eauto. eauto. eauto. 
  - Case "abs". right.
    inversion CL.
    assert (stpd2 [] (vobj (dfun T11 T12 t12)::G1) T11 T11).
    eapply stpd2_refl. subst. eapply closed_extend. eauto. 
    assert (stpd2 [] (vobj (dfun T11 T12 t12)::G1) T12 T12).
    eapply stpd2_refl. subst. eapply closed_extend. eauto. 
    eu. eu. repeat eexists. rewrite <-app_cons1. eapply ST_Obj. eapply T_Varx. eapply vtp_fun.
    simpl. rewrite beq_nat_true_eq. eauto. subst.
    eapply has_type_extend. eauto. eauto. eauto. 
  - Case "app". subst.
    assert (closed (length ([]:tenv)) (length G1) 0 (TFun T1 T)) as TF. eapply has_type_closed. eauto. 
    assert ((exists x : id, t2 = tvar true x) \/
                (exists (G' : venv) (t' : tm) n2,
                   step G1 t2 (G'++G1) t' /\ has_type [] (G'++G1) t' T1 n2)) as HX.
    eapply IHhas_type2. eauto. eauto. eauto. inversion TF. eauto. 
    assert ((exists x : id, t1 = tvar true x) \/
                (exists (G' : venv) (t' : tm) n2,
                   step G1 t1 (G'++G1) t' /\ has_type [] (G'++G1) t' (TFun T1 T) n2)) as HF.
    eapply IHhas_type1. eauto. eauto. eauto. eauto.
    destruct HF.
    + SCase "fun-val".
      destruct HX.
      * SSCase "arg-val".
        ev. ev. subst. 
        assert (exists m n1, vtp m G1 x (TFun T1 T) n1). eapply hastp_inv. eauto.
        assert (exists m n1, vtp m G1 x0 T1 n1). eapply hastp_inv. eauto.
        ev. inversion H1. subst.
        assert (vtpdd x1 G1 x0 T0). eapply vtp_widen. eauto. eauto. eauto. eauto. eauto.
        eu.
        assert (has_typed (map (substt x0) []) G1 (subst_tm x0 t) (substt x0 T2)) as HI.
        eapply hastp_subst; eauto.
        eu. simpl in HI. erewrite subst_closed_id in HI. 
        right. repeat eexists. rewrite app_nil_l. eapply ST_AppAbs. eauto.
        eapply T_Sub. eauto. eauto.
        change 0 with (length ([]:tenv)). eapply stpd2_closed1. eauto. 
      * SSCase "arg_step".
        ev. subst. 
        right. repeat eexists. eapply ST_App2. eauto. eapply T_App.
        eapply has_type_extend_mult. eauto. eauto. 
    + SCase "fun_step".
      ev. subst. right. repeat eexists. eapply ST_App1. eauto. eapply T_App.
      eauto. eapply has_type_extend_mult. eauto. 
  - Case "sub". subst.
    assert ((exists x : id, t0 = tvar true x) \/
               (exists (G' : venv) (t' : tm) n2,
                  step G1 t0 (G'++G1) t' /\ has_type [] (G'++G1) t' T1 n2)) as HH.
    eapply IHhas_type; eauto. change 0 with (length ([]:tenv)) at 1. eapply stpd2_closed1; eauto.
    destruct HH.
    + SCase "val".
      ev. subst. left. eexists. eauto.
    + SCase "step".
      ev. subst. 
      right. repeat eexists. eauto. eapply T_Sub. eauto. eapply stp2_extend_mult. eauto. 
      
Grab Existential Variables.
apply 0. apply 0.
Qed. 


End STLC.