{-# LANGUAGE LambdaCase   #-}
{-# LANGUAGE TypeFamilies #-}

module Ling.Reify where

import           Ling.Fwd
import qualified Ling.Norm    as N
import           Ling.Prelude
import           Ling.Proc
import           Ling.Raw
import           Ling.Session.Core
import           Prelude      hiding (log)

newtype RawSession = RawSession { rawSession :: Term }

class Norm a where
  type Normalized a
  norm  :: a -> Normalized a
  reify :: Normalized a -> a

  normalize :: Endom a
  normalize = reify . norm

normalized :: (Norm a, Norm b) => Iso a b (Normalized a) (Normalized b)
normalized = iso norm reify

reified :: (Norm a, Norm b) => Iso (Normalized a) (Normalized b) a b
reified = from normalized

instance Norm a => Norm [a] where
  type Normalized [a] = [Normalized a]
  reify = map reify
  norm = map norm

instance Norm CSession where
  type Normalized CSession = N.Session
  reify s
    | endS `is` s = Done
    | otherwise   = Cont . rawSession $ reify s
  norm Done = endS # ()
  norm (Cont s) = norm (RawSession s)

instance Norm ASession where
  type Normalized ASession = N.Session
  norm (AS s) = s ^. normalized . from N.tSession
  reify = AS . paren . rawSession . reify

instance Norm RawSession where
  type Normalized RawSession = N.Session
  norm = review N.tSession . norm . rawSession
  reify = RawSession . \case
            N.Array k s      -> aTerm $ reifyArray k (reify (s ^. N._Sessions))
            N.IO N.Write a s -> Snd (reifyVarDec a) (reify s)
            N.IO N.Read a s  -> Rcv (reifyVarDec a) (reify s)
            N.TermS o e      -> sessionOp o (reify e
                                          -- `annot` RawApp (Var $ Name "Session") []
                                            )

reifySession :: N.Session -> Term
reifySession = rawSession . reify

reifySessions :: [N.Session] -> [Term]
reifySessions = map reifySession

reifyDec :: N.Dec -> Dec
reifyDec = reify

instance Norm OptRepl where
  type Normalized OptRepl = N.RFactor
  reify r
    | N.litR1 `is` r = One
    | otherwise      = Some $ r ^. N.rterm . reified
  norm  One                  = ø
  norm (Some t)              = N.RFactor (norm t)

instance Norm RSession where
  type Normalized RSession = N.RSession
  reify (N.Repl s r) = Repl (reifySession s) (reify r)
  norm  (Repl s r)   = N.Repl (norm (RawSession s)) (norm r)

reifyRSession :: N.RSession -> RSession
reifyRSession = reify

reifyRSessions :: [N.RSession] -> [RSession]
reifyRSessions = reify

instance Norm Proc where
  type Normalized Proc        = N.Proc
  reify = \case
    N.Act act -> reifyAct act
    proc0 `N.Dot` proc1 -> reify proc0 `pDot` reify proc1
    N.Procs (Prll procs) -> pPrll $ reify procs
    N.LetP defs proc0 -> reifyDefsP defs (reify proc0)
    N.NewSlice cs t x p ->
      NewSlice ((justChannel #) <$> cs) (t ^. N.rterm . reified) x (reify p)
  norm = \case
    PAct act         -> normAct act
    PNxt proc0 proc1 -> norm proc0 `dotP` norm proc1
    PDot proc0 proc1 -> norm proc0 `dotP` norm proc1
    PSem proc0 proc1 -> norm proc0 `dotP` norm proc1
    PPrll procs      -> mconcat $ norm procs
    NewSlice cs t x p -> N.NewSlice (view justChannel <$> cs) (norm (Some t)) x (norm p)

kCPatt :: N.TraverseKind -> [CPatt] -> CPatt
kCPatt = \case
  N.TenK -> TenPatt
  N.ParK -> ParPatt
  N.SeqK -> SeqPatt

kTopPatt :: N.TraverseKind -> [CPatt] -> TopCPatt
kTopPatt = \case
  N.TenK -> TenTopPatt
  N.ParK -> ParTopPatt
  N.SeqK -> SeqTopPatt

newChans :: N.TraverseKind -> [ChanDec] -> NewPatt
newChans = \case
  N.TenK -> TenNewPatt
  N.SeqK -> SeqNewPatt
  N.ParK -> error "newChans: IMPOSSIBLE"

instance Norm CPatt where
  type Normalized CPatt = N.CPatt
  reify (N.ChanP cd) = ChaPatt (reify cd)
  reify (N.ArrayP k ps) = kCPatt k (reify ps)
  norm = \case
    TenPatt ps -> N.ArrayP N.TenK (norm ps)
    ParPatt ps -> N.ArrayP N.ParK (norm ps)
    SeqPatt ps -> N.ArrayP N.SeqK (norm ps)
    ChaPatt cd -> N.ChanP (norm cd)

instance Norm TopCPatt where
  type Normalized TopCPatt = N.CPatt
  reify (N.ChanP cd) = OldTopPatt [reify cd]
  reify (N.ArrayP k ps) = kTopPatt k (reify ps)
  norm = \case
    OldTopPatt [cd] -> N.ChanP (norm cd)
    OldTopPatt cs   -> N.ArrayP N.ParK (N.ChanP . norm <$> cs)
    TenTopPatt ps   -> N.ArrayP N.TenK (norm ps)
    ParTopPatt ps   -> N.ArrayP N.ParK (norm ps)
    SeqTopPatt ps   -> N.ArrayP N.SeqK (norm ps)

justChannel :: Iso' ChanDec Name
justChannel = iso go (\c-> CD c One NoSession)
  where
    go (CD x One NoSession) = x
    go (CD (Name x) _ SoSession{}) =
      error $ "unexpected session annotation for channel " ++ x
    go (CD (Name x) Some{} NoSession) =
      error $ "unexpected session replication for channel " ++ x

normSplit :: Split -> (Name, N.CPatt)
normSplit = \case
  PatSplit c _ pat -> (c, norm pat)
  ParSplit c ds    -> (c, _ArrayCs # (N.ParK, norm ds))
  TenSplit c ds    -> (c, _ArrayCs # (N.TenK, norm ds))
  SeqSplit c ds    -> (c, _ArrayCs # (N.SeqK, norm ds))

normAct :: Act -> N.Proc
normAct = \case
    -- These two clauses expand the forwarders
    Ax        s cs    -> fwdProc' id (norm s) (view justChannel <$> cs)
    SplitAx n s c     -> fwdProc (n ^?! integral) (norm s) c

    -- TODO make a flag to turn these on
{-
    Ax       s cs     -> toProc $ ax               (norm s) cs
    SplitAx  n s c    -> toProc ... (splitAx        n (norm s) c)
-}

    Nu newalloc       -> toProc $ N._Nu # norm newalloc
    Split split       -> toProc $ N._Split # normSplit split
    Send     c t      -> toProc $ N.Send c Nothing     (norm t)
    Recv     c a      -> toProc $ N.Recv c             (norm a)
    NewSend  c os t   -> toProc $ N.Send c (normOS os) (norm t)
    NewRecv x os c    -> toProc $ N.Recv c             (norm (VD x os))
    At       t pa     -> toProc $ N.At   (norm t) (norm pa)
    LetA     x os t   -> toProc $ N.aDef (norm x) (norm os) (norm t)
    LetRecv _x _os _t -> error "`let ... <= ...` is not supported yet (Issue #16)"

normOS :: OptSession -> Maybe N.Session
normOS NoSession     = Nothing
normOS (SoSession s) = Just (normS s)

normS :: RSession -> N.Session
normS (Repl s r)
  | One <- r  = norm (RawSession s)
  | otherwise = error "Unsupported replication in session annotation"

instance Norm Name where
  type Normalized Name = Name
  -- reify x = x ^? suffixedName "norm" ?| x
  reify x = x
  norm x = x
    -- | x == anonName = x
    -- | otherwise     = suffixedName "norm" # x

reifyProc :: N.Proc -> Proc
reifyProc = reify

reifyLetA :: Arg N.AnnTerm -> Act
reifyLetA (Arg x (Ann os tm)) = LetA (reify x) (reify os) (reify tm)

reifyDefsP :: N.Defs -> Endom Proc
reifyDefsP defs proc0 = pDots $ defs ^.. each . to reifyLetA . to PAct ++ [proc0]

newRecv :: Name -> VarDec -> Act
newRecv c (VD x os) = NewRecv x os c

reifyAct :: N.Act -> Proc
reifyAct = \case
  N.Nu anns newpatt   -> PAct $ Nu (reify (anns, newpatt))
  N.Split c pat       -> PAct . Split $ PatSplit c NoAs (reify pat)
  N.Send     c os t   -> PAct $ NewSend c (reify (oneS <$> os)) (reify t)
  N.Recv     c a      -> PAct $ newRecv c                       (reify a)
  N.Ax       s cs     -> PAct $ Ax (reify s) ((justChannel #) <$> cs)
  N.At       t ps     -> PAct $ At (reify t) (reify ps)

-- Really naive rawApp parsing
-- Next step is to carry an environment with
-- the operators and their fixity.
-- TODO:
--   * this only supports naive right-infix
--   * this currently fails to parse: `f x + y`
normRawApp :: [ATerm] -> N.Term
normRawApp [e] = norm e
normRawApp (e0:Op d:es)
  | (unOpName # d) `elem` ["-", "+", "*", "/", "%", "-D", "+D", "*D", "/D", "++S"] =
      N.Def (norm (infixed # d)) [norm e0, normRawApp es]
normRawApp (Var (Name "Fwd"):es)
  | [e0, e1] <- es
  , Just n <- e0 ^? normalized . N.litTerm . integral =
      fwd n (norm (AS e1)) ^. N.tSession
  | otherwise =
      error "invalid usage of Fwd"
normRawApp (Var (Name "Log"):es)
  | [e] <- es = log (norm (AS e)) ^. N.tSession
  | otherwise = error "invalid usage of Log"
normRawApp (Var x:es) = N.Def (norm x) (norm es)
normRawApp [] = error "normRawApp: IMPOSSIBLE"
normRawApp _ = error "normRawApp: unexpected application"

reifyRawApp :: N.Term -> [ATerm]
reifyRawApp e0 =
  case reify e0 of
    Paren (RawApp e1 es) NoSig -> e1 : es
    e0'                        -> [e0']

reifyArray :: N.TraverseKind -> [RSession] -> ATerm
reifyArray N.ParK = Par
reifyArray N.SeqK = Seq
reifyArray N.TenK = Ten

instance Norm ATerm where
  type Normalized ATerm = N.Term
  reify = \case
    N.Def x []                -> Var (reify x)
    N.Lit l                   -> Lit l
    N.Con n                   -> Con (reify n)
    N.TTyp                    -> TTyp
    N.TProto ss               -> TProto (reify $ ss ^. N._Sessions)
    N.TSession (N.Array k ss) -> reifyArray k (reify (ss ^. N._Sessions))
    e                         -> paren (reify e)
  norm = \case
    Var x      -> N.Def (norm x) []
    Op x       -> error $ "Unexpected operator-part: " ++ show x
    Lit l      -> N.Lit l
    Con n      -> N.Con (norm n)
    TTyp       -> N.TTyp
    TProto ss  -> N.TProto (N.Sessions (norm ss))
    End        -> (endS # ()) ^. N.tSession
    Par s      -> (N.Array N.ParK . N.Sessions $ norm s) ^. N.tSession
    Ten s      -> (N.Array N.TenK . N.Sessions $ norm s) ^. N.tSession
    Seq s      -> (N.Array N.SeqK . N.Sessions $ norm s) ^. N.tSession
    Paren t os -> N.optSig (norm t) (norm os)

mkVDsA :: ATerm -> [VarDec]
mkVDsA = \case
  Paren (RawApp a as) (SoSig s) ->
    VD <$> (a:as) ^.. each . _Var <*> [SoSig s]
  _ ->
    []

mkVDs :: Term -> [VarDec]
mkVDs = \case
  RawApp a as | vds@(_:_) <- mkVDsA =<< (a : as) -> vds
  e -> [VD anonName (SoSig e)]

mkVDsALam :: ATerm -> [VarDec]
mkVDsALam = \case
  Var x -> [VD x NoSig]
  a     -> mkVDsA a

mkVDsLam :: Term -> [VarDec]
mkVDsLam = \case
  RawApp a as | vds@(_:_) <- mkVDsALam =<< (a : as) -> vds
  _ -> error "Unexpected "

reifyDef :: Name -> [N.Term] -> Term
reifyDef (Name "_:_") [e1,e2]
  = aTerm $ Paren (reify e2) (SoSig (reify e1))
reifyDef x es
  | Just d <- x ^? infixed, [e1, e2] <- es
  = RawApp (reify e1) (Op d : reifyRawApp e2)
  | otherwise = RawApp (Var x) (reify es)

reifyVarDecA :: N.VarDec -> ATerm
reifyVarDecA (Arg _ Nothing) = error "reifyVarDecA: no type annotation"
reifyVarDecA (Arg a0 (Just t))
  | a == anonName = Paren (reify t)            NoSig
  | otherwise     = Paren (RawApp (Var a) []) (SoSig (reify t))

  where a = reify a0

reifyVarDec :: N.VarDec -> Term
reifyVarDec = aTerm . reifyVarDecA

reifyDefs :: N.Defs -> Endom Term
reifyDefs = composeMapOf each $ \case
  Arg x (Ann mty tm) -> Let (reify x) (reify mty) (reify tm)

instance Norm Term where
  type Normalized Term = N.Term
  reify = \case
    N.Def x es   -> reifyDef (reify x) es
    N.Let d t    -> reifyDefs d (reify t)
    N.Lit l      -> RawApp (Lit l) []
    N.Con n      -> RawApp (Con (reify n)) []
    N.TTyp       -> RawApp TTyp []
    N.TProto ss  -> RawApp (TProto (reify (ss ^. N._Sessions))) []
    N.Proc cs p  -> TProc (reify cs) (reify p)
    N.Lam  arg s -> Lam  (reifyVarDec arg) (reify s)
    N.TFun arg s -> TFun (reifyVarDec arg) (reify s)
    N.TSig arg s -> TSig (reifyVarDec arg) (reify s)
    N.Case t brs -> Case (reify t) (reify brs)
    N.TSession s -> reifySession s
  norm = \case
    RawApp e es  -> normRawApp (e : es)
    Case t brs   -> N.Case (norm t) (sort (norm brs))
    TProc cs p   -> N.Proc (norm cs) (norm p)
    Lam  u t     -> normVarDecs N.Lam  (mkVDsLam u) t
    TFun u t     -> normVarDecs N.TFun (mkVDs u) t
    TSig u t     -> normVarDecs N.TSig (mkVDs u) t
    Snd t s      -> normVarDecs (N.IO N.Write) (mkVDs t) s ^. N.tSession
    Rcv t s      -> normVarDecs (N.IO N.Read ) (mkVDs t) s ^. N.tSession
    Loli s t     -> norm (RawSession s) `loli` norm (RawSession t) ^. N.tSession
    Dual s       -> dual (norm s)
    TRecv _c     -> error "Receive as an expression (Issue #16) is not supported yet"
    Let x os t u -> N.Let (N.aDef (norm x) (norm os) (norm t)) (norm u)

instance Norm Branch where
  type Normalized Branch = (Name, N.Term)
  reify (n, t) = Br (reify n) (reify t)
  norm (Br n t) = (norm n, norm t)

instance Norm ConName where
  type Normalized ConName = Name
  reify = CN
  norm (CN n) = n

reifyTerm :: N.Term -> Term
reifyTerm = reify

instance Norm AllocTerm where
  type Normalized AllocTerm = N.Term
  reify (N.Lit lit)  = ALit lit
  reify (N.Def d []) = AVar (reify d)
  reify t            = AParen (reify t) NoSig
  norm (ALit lit)    = N.Lit lit
  norm (AVar d)      = N.Def (norm d) []
  norm (AParen t os) = N.optSig (norm t) (norm os)

instance Norm NewPatt where
  type Normalized NewPatt = N.NewPatt
  reify = \case
    N.NewChans k cds -> newChans k (reify cds)
    N.NewChan c os   -> CntNewPatt (reify c) (reify os)

  norm = \case
    TenNewPatt cds  -> N.NewChans N.TenK $ norm cds
    SeqNewPatt cds  -> N.NewChans N.SeqK $ norm cds
    CntNewPatt c os -> N.NewChan  (norm c) (norm os)

instance Norm NewAlloc where
  type Normalized NewAlloc = ([N.Term], N.NewPatt)
  reify (os, kcds) =
    case os of
      [] -> New (reify kcds)
      [N.Def (Name d) ts] -> NewNAnn (OpName ("new/" ++ d)) (reify ts) (reify kcds)
      [t] -> NewSAnn (reify t) NoSig (reify kcds)
      _ -> error "reify/NewAlloc: IMPOSSIBLE"
  norm (New newpatt) = ([], norm newpatt)
  norm (NewSAnn t os newpatt) = ([N.optSig (norm t) (norm os)], norm newpatt)
  norm (NewNAnn (OpName newd) ts newpatt)
    | Just d <- newd ^? prefixed "new/" = ([N.Def (Name d) (norm ts)], norm newpatt)
    | otherwise                         = error "norm/NewAlloc: IMPOSSIBLE"

instance Norm ChanDec where
  type Normalized ChanDec  = N.ChanDec
  reify (N.ChanDec c r os) = CD c (reify r) (reify os)
  norm  (CD c r os)        = N.ChanDec c (norm r) (norm os)

instance Norm VarDec where
  type Normalized VarDec = N.VarDec
  reify (Arg x s) = VD  (reify x) (reify s)
  norm  (VD x s)  = Arg (norm x) (norm  s)

instance Norm OptSession where
  type Normalized OptSession = Maybe N.RSession
  reify (Just s)     = SoSession (reify s)
  reify Nothing      = NoSession
  norm NoSession     = Nothing
  norm (SoSession s) = Just (norm s)

normVarDecs :: (Norm a, Normalized a ~ b) => (N.VarDec -> b -> b) -> [VarDec] -> a -> b
normVarDecs f vds z = foldr f (norm z) (norm vds)

instance Norm Program where
  type Normalized Program = N.Program
  reify (N.Program decs)  =   Prg     (reify decs)
  norm  (Prg       decs)  = N.Program (norm  decs)

reifyProgram :: N.Program -> Program
reifyProgram = reify

instance Norm OptSig where
  type Normalized OptSig = Maybe N.Term
  reify Nothing          = NoSig
  reify (Just t)         = SoSig (reify t)
  norm NoSig             = Nothing
  norm (SoSig t)         = Just (norm t)

instance Norm Dec where
  type Normalized Dec   = N.Dec

  norm = \case
    DSig d ty    -> N.Sig (norm d) (Just $ norm ty) Nothing
    DDef d ty tm -> N.Sig (norm d) (norm ty) (Just $ norm tm)
    DDat d cs    -> N.Dat (norm d) (norm cs)
    DAsr a       -> N.Assert (norm a)
  reify = \case
    N.Sig _ Nothing   Nothing -> error "IMPOSSIBLE Norm Dec/reify: no def nor sig"
    N.Sig d (Just ty) Nothing -> DSig (reify d) (reify ty)
    N.Sig d ty (Just tm)      -> DDef (reify d) (reify ty) (reify tm)
    N.Dat d cs                -> DDat (reify d) (reify cs)
    N.Assert a                -> DAsr (reify a)

instance Norm Assertion where
  type Normalized Assertion = N.Assertion
  norm  (AEq t1 t2 os)      = N.Equal (norm t1) (norm t2) (norm os)
  reify (N.Equal t1 t2 mty) = AEq (reify t1) (reify t2) (reify mty)

-- -}
