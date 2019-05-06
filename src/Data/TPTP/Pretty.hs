{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}

-- |
-- Module       : Data.TPTP.Pretty
-- Description  : Pretty printers for the TPTP language.
-- Copyright    : (c) Evgenii Kotelnikov, 2019
-- License      : GPL-3
-- Maintainer   : evgeny.kotelnikov@gmail.com
-- Stability    : experimental
--

module Data.TPTP.Pretty (
  Pretty(..)
) where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List (genericReplicate)
import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NEL (nonEmpty, toList)
import Data.Maybe (maybeToList)
import Data.Text (Text)
import qualified Data.Text as Text (all, head, tail, cons, snoc,
                                    pack, singleton, replace)

#if __GLASGOW_HASKELL__ >= 803
import Prelude hiding ((<>))
#endif

import Data.TPTP

import Data.Text.Prettyprint.Doc (Doc, Pretty(..), hsep, sep, (<>), (<+>),
                                  brackets, parens, punctuate, comma, space)


-- * Helper functions

sepBy :: [Doc ann] -> Doc ann -> Doc ann
sepBy as s = hsep (punctuate s as)

sepBy1 :: NonEmpty (Doc ann) -> Doc ann -> Doc ann
sepBy1 as s = hsep (punctuate s (NEL.toList as))

application :: Pretty f => f -> [Doc ann] -> Doc ann
application f [] = pretty f
application f as = pretty f <> parens (as `sepBy` comma)

bracketList :: Pretty a => [a] -> Doc ann
bracketList as = brackets (fmap pretty as `sepBy` comma)


-- * Names

quoted :: Char -> Text -> Text
quoted q = Text.cons q . flip Text.snoc q
         . Text.replace (Text.singleton q) (Text.pack ['\\', q])
         . Text.replace "\\" "\\\\"

newtype SingleQuoted = SingleQuoted Text
  deriving (Eq, Show, Ord)

instance Pretty SingleQuoted where
  pretty (SingleQuoted t) = pretty (quoted '\'' t)

instance Pretty Atom where
  pretty (Atom s)
    | isLowerWord s = pretty s
    | otherwise = pretty (SingleQuoted s)
    where
      isLowerWord w = isAsciiLower (Text.head w)
                   && Text.all isAlphaNum (Text.tail w)
      isAlphaNum c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '_'

instance Pretty Var where
  pretty (Var s) = pretty s

newtype DoubleQuoted = DoubleQuoted Text
  deriving (Eq, Show, Ord)

instance Pretty DoubleQuoted where
  pretty (DoubleQuoted t) = pretty (quoted '"' t)

instance Pretty DistinctObject where
  pretty (DistinctObject s) = pretty (DoubleQuoted s)

newtype DollarWord = DollarWord Text
  deriving (Eq, Show, Ord)

instance Pretty DollarWord where
  pretty (DollarWord w) = pretty (Text.cons '$' w)

tType :: DollarWord
tType = DollarWord "tType"

instance Named s => Pretty (Name s) where
  pretty = \case
    Reserved s -> pretty (DollarWord (name s))
    Defined  a -> pretty a

instance Named s => Named (Reserved s) where
  name = \case
    Standard s -> name s
    Extended w -> w

instance Named s => Pretty (Reserved s) where
  pretty = pretty . name


-- * Sorts and types

instance Pretty TFF1Sort where
  pretty = \case
    SortVariable v -> pretty v
    TFF1Sort  f ss -> application f (fmap pretty ss)

prettyMapping :: Pretty a => [a] -> a -> Doc ann
prettyMapping as r = args <> pretty r
  where
    args = case as of
      []  -> mempty
      [a] -> pretty a <+> ">" <> space
      _   -> parens (fmap pretty as `sepBy` (space <> "*")) <+> ">" <> space

instance Pretty Type where
  pretty = \case
    Type as r -> prettyMapping as r
    TFF1Type vs as r -> prefix <> if null as then matrix else parens matrix
      where
        prefix = case NEL.nonEmpty vs of
          Nothing  -> mempty
          Just vs' -> "!>" <+> brackets (vars vs') <> ":" <> space
        vars vs' = fmap prettyVar vs' `sepBy1` comma
        prettyVar v = pretty v <> ":" <+> pretty tType
        matrix = prettyMapping as r


-- * First-order logic

instance Pretty Number where
  pretty = \case
    IntegerConstant    i -> pretty i
    RationalConstant n d -> pretty n <> "/" <> pretty d
    RealConstant       r -> pretty (show r)

instance Pretty Term where
  pretty = \case
    Function  f ts -> application f (fmap pretty ts)
    Variable     v -> pretty v
    Number       i -> pretty i
    DistinctTerm d -> pretty d

instance Pretty Literal where
  pretty = \case
    Predicate p ts -> application p (fmap pretty ts)
    Equality a s b -> pretty a <+> pretty s <+> pretty b

instance Pretty Sign where
  pretty = pretty . name

instance Pretty Clause where
  pretty = \case
    Clause ls -> fmap p ls `sepBy1` (space <> pretty Disjunction)
      where
        p (Positive, l) = pretty l
        p (Negative, l) = "~" <+> parens (pretty l)

instance Pretty Quantifier where
  pretty = pretty . name

instance Pretty Connective where
  pretty = pretty . name

instance Pretty Unsorted where
  pretty = mempty

instance Pretty s => Pretty (Sorted s) where
  pretty = \case
    Sorted Nothing  -> mempty
    Sorted (Just s) -> ":" <+> pretty s

instance Pretty QuantifiedSort where
  pretty = const (pretty tType)

instance Pretty (Either QuantifiedSort TFF1Sort) where
  pretty = either pretty pretty

unitary :: FirstOrder s -> Bool
unitary = \case
  Atomic{}     -> True
  Negated{}    -> True
  Quantified{} -> True
  Connected{}  -> False

pretty' :: Pretty s => FirstOrder s -> Doc ann
pretty' f
  | unitary f = pretty f
  | otherwise = parens (pretty f)

instance Pretty s => Pretty (FirstOrder s) where
  pretty = \case
    Atomic l -> pretty l
    Negated f -> "~" <+> pretty' f
    Connected f c g -> pretty'' f <+> pretty c <+> pretty'' g
      where
        -- Nested applications of associative connectives do not require
        -- parenthesis. Otherwise, the connectives do not have precedence
        pretty'' e@(Connected _ c' _) | c' == c && isAssociative c = pretty e
        pretty'' e = pretty' e
    Quantified q vs f -> pretty q <+> vs' <> ":" <+> pretty' f
      where
        vs' = brackets (fmap var vs `sepBy1` comma)
        var (v, s) = pretty v <> pretty s


-- ** Units

instance Pretty Language where
  pretty = pretty . name

instance Pretty Formula where
  pretty = \case
    CNF  c -> pretty c
    FOF  f -> pretty f
    TFF0 f -> pretty f
    TFF1 f -> pretty f

instance Pretty UnitName where
  pretty = either pretty pretty
  prettyList = bracketList

instance Pretty Declaration where
  pretty = \case
    Formula _ f -> pretty f
    Typing  s t -> pretty s <> ":" <+> pretty t
    Sort    s n -> pretty s <> ":" <+> prettyMapping tTypes tType
      where tTypes = genericReplicate n tType

instance Pretty Unit where
  pretty = \case
    Include (Atom f) ns -> application (Atom "include") args <> "."
      where
        args = pretty (SingleQuoted f) : [prettyList ns | not (null ns)]
    Unit nm decl a -> application (declarationLanguage decl) args <> "."
      where
        args = pretty nm : role : pretty decl : ann

        role = case decl of
          Sort{}      -> "type"
          Typing{}    -> "type"
          Formula r _ -> pretty (name r)

        ann = case a of
          Just (s, i) -> pretty s : maybeToList (fmap prettyList i)
          Nothing -> []

  prettyList us = sep (fmap pretty us)

instance Pretty TPTP where
  pretty (TPTP us) = prettyList us


-- * Annotations

instance Pretty Intro where
  pretty = pretty . name

instance Pretty Status where
  pretty = pretty . name

instance Pretty Expression where
  pretty = \case
    Logical f -> application (DollarWord . name $ formulaLanguage f) [pretty f]
    Term    t -> application (DollarWord "fot") [pretty t]

instance Pretty GeneralData where
  pretty = \case
    GeneralFunction f gts -> application f (fmap pretty gts)
    GeneralVariable     v -> pretty v
    GeneralNumber       n -> pretty n
    GeneralExpression   e -> pretty e
    GeneralBind       v e -> application (Atom "bind") [pretty v, pretty e]
    GeneralDistinct     d -> pretty d

instance Pretty GeneralTerm where
  pretty = \case
    GeneralData gd Nothing  -> pretty gd
    GeneralData gd (Just t) -> pretty gd <> ":" <> pretty t
    GeneralList gts -> prettyList gts
  prettyList = bracketList

instance Pretty Parent where
  pretty = \case
    Parent s  [] -> pretty s
    Parent s gts -> pretty s <> ":" <> prettyList gts
  prettyList = bracketList

instance Pretty Source where
  pretty = \case
    UnitSource un -> pretty un
    UnknownSource -> "unknown"
    File (Atom n) i -> source "file" (SingleQuoted n) (pretty     <$> i)
    Theory     n  i -> source "theory"             n  (prettyList <$> i)
    Creator    n  i -> source "creator"            n  (prettyList <$> i)
    Introduced n  i -> source "introduced"         n  (prettyList <$> i)
    Inference  n  i ps ->
      application (Atom "inference") [pretty n, pretty i, prettyList ps]
    where
      source f n i = application (Atom f) (pretty n : maybeToList i)

  prettyList = bracketList
