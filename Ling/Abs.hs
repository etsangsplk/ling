

module Ling.Abs where

-- Haskell module generated by the BNF converter




newtype Name = Name String deriving (Eq, Ord, Show, Read)
newtype OpName = OpName String deriving (Eq, Ord, Show, Read)
data Program = Prg [Dec]
  deriving (Eq, Ord, Show, Read)

data Dec
    = DDef Name OptSig Term
    | DSig Name Term
    | DDat Name [ConName]
    | DAsr Assertion
  deriving (Eq, Ord, Show, Read)

data Assertion = AEq Term Term OptSig
  deriving (Eq, Ord, Show, Read)

data ConName = CN Name
  deriving (Eq, Ord, Show, Read)

data OptSig = NoSig | SoSig Term
  deriving (Eq, Ord, Show, Read)

data VarDec = VD Name OptSig
  deriving (Eq, Ord, Show, Read)

data ChanDec = CD Name OptRepl OptSession
  deriving (Eq, Ord, Show, Read)

data Branch = Br ConName Term
  deriving (Eq, Ord, Show, Read)

data Literal
    = LInteger Integer | LDouble Double | LString String | LChar Char
  deriving (Eq, Ord, Show, Read)

data ATerm
    = Var Name
    | Op OpName
    | Lit Literal
    | Con ConName
    | TTyp
    | TProto [RSession]
    | Paren Term OptSig
    | End
    | Par [RSession]
    | Ten [RSession]
    | Seq [RSession]
  deriving (Eq, Ord, Show, Read)

data Term
    = RawApp ATerm [ATerm]
    | Case Term [Branch]
    | Snd Term CSession
    | Rcv Term CSession
    | Dual Term
    | TRecv Name
    | Loli Term Term
    | TFun Term Term
    | TSig Term Term
    | Let Name OptSig Term Term
    | Lam Term Term
    | TProc [ChanDec] Proc
  deriving (Eq, Ord, Show, Read)

data Proc
    = PAct Act
    | PPrll [Proc]
    | PRepl ReplKind ATerm WithIndex Proc
    | PNxt Proc Proc
    | PDot Proc Proc
    | PSem Proc Proc
  deriving (Eq, Ord, Show, Read)

data ReplKind = ReplSeq | ReplPar
  deriving (Eq, Ord, Show, Read)

data WithIndex = NoIndex | SoIndex Name
  deriving (Eq, Ord, Show, Read)

data Act
    = Nu NewAlloc
    | Split Split
    | Send Name ATerm
    | NewSend Name OptSession ATerm
    | Recv Name VarDec
    | NewRecv Name OptSig Name
    | LetRecv Name OptSig ATerm
    | Ax ASession [ChanDec]
    | SplitAx Integer ASession Name
    | At ATerm TopCPatt
    | LetA Name OptSig ATerm
  deriving (Eq, Ord, Show, Read)

data ASession = AS ATerm
  deriving (Eq, Ord, Show, Read)

data Split
    = PatSplit Name OptAs CPatt
    | ParSplit Name [ChanDec]
    | TenSplit Name [ChanDec]
    | SeqSplit Name [ChanDec]
  deriving (Eq, Ord, Show, Read)

data OptAs = NoAs | SoAs
  deriving (Eq, Ord, Show, Read)

data TopCPatt
    = OldTopPatt [ChanDec]
    | ParTopPatt [CPatt]
    | TenTopPatt [CPatt]
    | SeqTopPatt [CPatt]
  deriving (Eq, Ord, Show, Read)

data CPatt
    = ChaPatt ChanDec
    | ParPatt [CPatt]
    | TenPatt [CPatt]
    | SeqPatt [CPatt]
  deriving (Eq, Ord, Show, Read)

data OptSession = NoSession | SoSession RSession
  deriving (Eq, Ord, Show, Read)

data RSession = Repl Term OptRepl
  deriving (Eq, Ord, Show, Read)

data OptRepl = One | Some ATerm
  deriving (Eq, Ord, Show, Read)

data CSession = Cont Term | Done
  deriving (Eq, Ord, Show, Read)

data AllocTerm = AVar Name | ALit Literal | AParen Term OptSig
  deriving (Eq, Ord, Show, Read)

data NewSig = NoNewSig | NewTypeSig Term | NewSessSig Term
  deriving (Eq, Ord, Show, Read)

data NewPatt
    = TenNewPatt [CPatt] | SeqNewPatt [CPatt] | CntNewPatt Name NewSig
  deriving (Eq, Ord, Show, Read)

data NewAlloc
    = New NewPatt
    | NewSAnn Term OptSig NewPatt
    | NewNAnn OpName [AllocTerm] NewPatt
  deriving (Eq, Ord, Show, Read)
