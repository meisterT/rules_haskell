{-# LANGUAGE ForeignFunctionInterface #-}

module Lib where

foreign import ccall "add" add :: Int -> Int -> Int

x :: Int
x = add 1 1
