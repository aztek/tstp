module Main where

import Test.DocTest (doctest)

main :: IO ()
main = doctest ["-isrc", "--fast", "src/Data/TPTP.hs"]
