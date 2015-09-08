{-# LANGUAGE TemplateHaskell, Rank2Types #-}
module Ling.Utils where

import Ling.Abs
import Ling.Print (Print, Doc, prt)
import qualified Data.Set as Set
import Data.Set (Set)
import qualified Data.Map as Map
import Data.Map (Map)
import Control.Lens
import Debug.Trace

type Endom a = a -> a
type Msg = String
type Verbosity = Bool

data Arg a = Arg { _argName :: Name, _unArg :: a }
  deriving (Eq,Ord,Show,Read)

$(makeLenses ''Arg)

type Channel = Name

nameString :: Iso' Name String
nameString = iso unName Name

prefName :: String -> Endom Name
prefName s n = n & nameString %~ (s ++)

suffName :: String -> Endom Name
suffName s n = n & nameString %~ (++ s)

traceShow :: Show a => String -> a -> a
traceShow msg x = trace (msg ++ " " ++ show x) x

tracePretty :: Print a => String -> a -> a
tracePretty msg x = trace (msg ++ " " ++ pretty x) x

debugTraceWhen :: Bool -> [Msg] -> a -> a
debugTraceWhen b xs =
  if b then trace (unlines (map ("[DEBUG]  "++) xs)) else id

optChanDecs :: OptChanDecs -> [ChanDec]
optChanDecs NoChanDecs       = []
optChanDecs (SoChanDecs cds) = cds

unName :: Name -> String
unName (Name x) = x

l2s :: Ord a => [a] -> Set a
l2s = Set.fromList
s2l :: Ord a => Set a -> [a]
s2l = Set.toList
l2m :: Ord k => [(k,a)] -> Map k a
l2m = Map.fromList
m2l :: Ord k => Map k a -> [(k,a)]
m2l = Map.toList

countMap :: (a -> Bool) -> Map k a -> Int
countMap p = Map.size . Map.filter p

singletons :: Ord a => [a] -> Set (Set a)
singletons = l2s . map Set.singleton

-- the top-level printing method
pretty :: Print a => a -> String
pretty = render . prt 0

render :: Doc -> String
render d = rend 0 (map ($ "") $ d []) "" where
  rend :: Int -> [String] -> ShowS
  rend i ss = case ss of
    "["      :ts -> showChar '[' . rend i ts
    "("      :ts -> showChar '(' . rend i ts
    "."      :ts -> showString ".\n" . rend i ts
{-
    "{"      :ts -> showChar '{' . new (i+1) . rend (i+1) ts
    "}" : ";":ts -> new (i-1) . space "}" . showChar ';' . new (i-1) . rend (i-1) ts
    "}"      :ts -> new (i-1) . showChar '}' . new (i-1) . rend (i-1) ts
    ";"      :ts -> showChar ';' . new i . rend i ts
-}
    "{"      :ts -> showChar '{' . rend i ts
    t  : "," :ts -> showString t . space "," . rend i ts
    t  : ")" :ts -> showString t . showChar ')' . rend i ts
    t  : "]" :ts -> showString t . showChar ']' . rend i ts
    t  : "}" :ts -> showString t . showChar '}' . rend i ts
    t        :ts -> space t . rend i ts
    _            -> id
  -- new i   = showChar '\n' . replicateS (2*i) (showChar ' ') . dropWhile isSpace
  space t = showString t . (\s -> if null s then "" else ' ':s)

infixr 3 ||>
(||>) :: Monad m => Bool -> m Bool -> m Bool
True  ||> _  = return True
False ||> my = my

infixr 3 <||>
(<||>) :: Monad m => m Bool -> m Bool -> m Bool
mx <||> my = do x <- mx
                if x then return True
                     else my

infixr 3 &&>
(&&>) :: Monad m => Bool -> m Bool -> m Bool
True  &&> my = my
False &&> _  = return False

infixr 3 <&&>
(<&&>) :: Monad m => m Bool -> m Bool -> m Bool
mx <&&> my = do x <- mx
                if x then my
                     else return False

subList :: Eq a => [a] -> [a] -> Bool
subList []    _  = True
subList (_:_) [] = False
subList (x:xs) (y:ys)
  | x == y    = xs     `subList` ys
  | otherwise = (x:xs) `subList` ys

rmDups :: Eq a => [a] -> [a]
rmDups (x1:x2:xs)
  | x1 == x2  = rmDups (x1:xs)
  | otherwise = x1 : rmDups (x2:xs)
rmDups xs = xs

-- TODO write quickcheck props about this function
substList :: Ord a => Set a -> a -> [a] -> [a]
substList xs y = rmDups . map f where
  f z | z `Set.member` xs = y
      | otherwise         = z

subst1 :: Eq a => (a,a) -> Endom a
subst1 (x,y) z | x == z    = y
               | otherwise = z

hasKey :: At m => Index m -> Getter m Bool
hasKey k = at k . to (isn't _Nothing)

hasNoKey :: At m => Index m -> Getter m Bool
hasNoKey k = at k . to (isn't _Just)