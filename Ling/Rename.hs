module Ling.Rename where

import           Control.Applicative
import           Control.Lens

import           Ling.Abs            (Name)
import           Ling.Norm
import           Ling.Scoped
import           Ling.Utils          as Utils
-- import        Ling.Print.Instances ()

type Ren = Name -> Name

class Rename a where
  rename :: Ren -> Endom a

rename1 :: Rename a => (Name, Name) -> Endom a
rename1 = rename . Utils.subst1

subst1 :: Rename a => Name -> (Name, Term) -> Scoped a -> Scoped a
subst1 f (x,e) (Scoped defs s) =
  Scoped (addEDef x' e defs) (rename1 (x,x') s)
  where
    x'  = prefName (unName f ++ "#") x

instance Rename Name where
  rename f n = f n

instance Rename Term where
  rename f e0 = case e0 of
    Def x es   -> Def (rename f x) (rename f es)

    Lam  arg t -> Lam  (rename f arg) (rename (hideArg arg f) t)
    TFun arg t -> TFun (rename f arg) (rename (hideArg arg f) t)
    TSig arg t -> TSig (rename f arg) (rename (hideArg arg f) t)
    Con x      -> Con  (rename f x)
    Case t brs -> Case (rename f t) (rename f brs)
    TTyp       -> e0
    Lit{}      -> e0

    Proc{}     -> error "rename/Proc: TODO"
    TProto{}   -> error "rename/TProto: TODO"

instance Rename a => Rename (Arg a) where
  rename f (Arg x e) = Arg (rename f x) (rename f e)

instance Rename a => Rename [a] where
  rename = map . rename

instance Rename a => Rename (Maybe a) where
  rename = fmap . rename

instance (Rename a, Rename b) => Rename (a, b) where
  rename f = bimap (rename f) (rename f)

hideName :: Name -> Endom Ren
hideName x f y | x == y    = y
               | otherwise = f y

hideArg :: Arg a -> Endom Ren
hideArg (Arg x _) = hideName x

hidePref :: Pref -> Endom Ren
hidePref (Recv _ arg)   = hideArg arg
hidePref _              = id

hidePrefs :: [Pref] -> Endom Ren
hidePrefs = flip (foldr hidePref)

instance Rename Pref where
  rename f pref = case pref of
    Split k c ds  -> Split k (rename f c) (rename f ds)
    Send c e      -> Send (rename f c) (rename f e)
    Recv c arg    -> Recv (rename f c) (rename f arg)
    Nu c d        -> Nu (rename f c) (rename f d)

instance Rename Proc where
  rename f proc0 = case proc0 of
    NewSlice cs t x p -> NewSlice (rename f cs) (rename f t) (rename f x)
                                  (rename (hideName x f) p)
    Act prefs procs   -> Act (rename f prefs) (rename (hidePrefs prefs f) procs)
    Ax s c d es       -> Ax (rename f s) (rename f c) (rename f d) (rename f es)
    At t cs           -> At (rename f t) (rename f cs)

instance Rename Session where
  rename f s0 = case s0 of
    Ten ss  -> Ten (rename f ss)
    Par ss  -> Par (rename f ss)
    Seq ss  -> Seq (rename f ss)
    Snd t s -> Snd (rename f t) (rename f s)
    Rcv t s -> Rcv (rename f t) (rename f s)
    Atm p n -> Atm p (rename f n)
    End     -> End

instance Rename RSession where
  rename f (Repl s t) = Repl (rename f s) (rename f t)