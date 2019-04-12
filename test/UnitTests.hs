{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

-- |
-- Module       : UnitTests
-- Description  : Run the TPTP parser on selected examples from the TPTP World.
-- Copyright    : (c) Evgenii Kotelnikov, 2019
-- License      : GPL-3
-- Maintainer   : evgeny.kotelnikov@gmail.com
-- Stability    : experimental
--

module UnitTests (tests) where

import Distribution.TestSuite

import System.Directory

import Data.Text (Text)
import qualified Data.Text.IO as Text.IO
import Data.List
import Control.Monad.Extra

import Data.TPTP.Parse.Text

testDataDir :: FilePath
testDataDir = "test-data"

listTestDirectory :: FilePath -> IO [FilePath]
listTestDirectory d = listDirectory (testDataDir ++ "/" ++ d)

readTestFile :: FilePath -> IO Text
readTestFile f = Text.IO.readFile (testDataDir ++ "/" ++ f)

parseFile :: FilePath -> IO Result
parseFile path = buildResult . parseDerivationOnly <$> readTestFile path
  where
    buildResult (Left e)  = Error e
    buildResult (Right _) = Pass

type TestCase = (FilePath, FilePath, FilePath)

testFile :: TestCase -> Test
testFile (space, lang, file) = Test $ TestInstance {
  run = Finished <$> parseFile path,
  name = path,
  tags = [space, lang],
  options = [],
  setOption = const . const $ Left "not supported"
} where path = intercalate "/" [space, lang, file]

listSpaces :: IO [FilePath]
listSpaces = listTestDirectory ""

listLangs :: FilePath -> IO [(FilePath, FilePath)]
listLangs s = fmap (s,) <$> listTestDirectory s

listFiles :: (FilePath, FilePath) -> IO [(FilePath, FilePath, FilePath)]
listFiles (s, l) = fmap (s, l,) <$> listTestDirectory (s ++ "/" ++ l)

cases :: IO [TestCase]
cases = listSpaces >>= concatMapM listLangs >>= concatMapM listFiles

tests :: IO [Test]
tests =  fmap testFile <$> cases
