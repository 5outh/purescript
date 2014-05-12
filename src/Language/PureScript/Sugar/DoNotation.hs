-----------------------------------------------------------------------------
--
-- Module      :  Language.PureScript.Sugar.DoNotation
-- Copyright   :  (c) Phil Freeman 2013
-- License     :  MIT
--
-- Maintainer  :  Phil Freeman <paf31@cantab.net>
-- Stability   :  experimental
-- Portability :
--
-- |
-- This module implements the desugaring pass which replaces do-notation statements with
-- appropriate calls to (>>=) from the Prelude.Monad type class.
--
-----------------------------------------------------------------------------

module Language.PureScript.Sugar.DoNotation (
    desugarDoModule
) where

import Language.PureScript.Names
import Language.PureScript.Scope
import Language.PureScript.Declarations
import Language.PureScript.Errors

import qualified Language.PureScript.Constants as C

import Control.Applicative

-- |
-- Replace all @DoNotationBind@ and @DoNotationValue@ constructors with applications of the Prelude.(>>=) function,
-- and all @DoNotationLet@ constructors with let expressions.
--
desugarDoModule :: Module -> Either ErrorStack Module
desugarDoModule (Module mn ds exts) = Module mn <$> mapM desugarDo ds <*> pure exts

desugarDo :: Declaration -> Either ErrorStack Declaration
desugarDo (PositionedDeclaration pos d) = rethrowWithPosition pos $ desugarDo d
desugarDo d =
  let (f, _, _) = everywhereOnValuesM return replace return
  in f d
  where
  prelude :: ModuleName
  prelude = ModuleName [ProperName C.prelude]

  bind :: Value
  bind = Var (Qualified (Just prelude) (Op (C.>>=)))

  replace :: Value -> Either ErrorStack Value
  replace (Do els) = go els
  replace (PositionedValue pos d) = rethrowWithPosition pos $ replace d
  replace other = return other

  go :: [DoNotationElement] -> Either ErrorStack Value
  go [] = error "The impossible happened in desugarDo"
  go [DoNotationValue val] = return val
  go (DoNotationValue val : rest) = do
    rest' <- go rest
    return $ App (App bind val) (Abs (Left (Ident "_")) rest')
  go [DoNotationBind _ _] = Left $ mkErrorStack "Bind statement cannot be the last statement in a do block" Nothing
  go (DoNotationBind NullBinder val : rest) = go (DoNotationValue val : rest)
  go (DoNotationBind (VarBinder ident) val : rest) = do
    rest' <- go rest
    return $ App (App bind val) (Abs (Left ident) rest')
  go (DoNotationBind binder val : rest) = do
    rest' <- go rest
    let used = concatMap usedNamesDoNotationElement rest
        ident = head $ unusedNames used
    return $ App (App bind val) (Abs (Left ident) (Case [Var (Qualified Nothing ident)] [CaseAlternative [binder] Nothing rest']))
  go [DoNotationLet _] = Left $ mkErrorStack "Let statement cannot be the last statement in a do block" Nothing
  go (DoNotationLet ds : rest) = do
    rest' <- go rest
    return $ Let ds rest'
  go (PositionedDoNotationElement pos el : rest) = rethrowWithPosition pos $ PositionedValue pos <$> go (el : rest)
