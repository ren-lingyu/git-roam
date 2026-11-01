module TestSupport (assertEqual, assertTrue, expectRight, expectLeft, runTests, withTempDirectory) where

import Control.Exception (SomeException, bracket, displayException, try)
import Control.Monad (unless)
import System.Directory (
    canonicalizePath,
    createDirectory,
    getTemporaryDirectory,
    removeDirectoryRecursive,
    removeFile,
 )
import System.Exit (exitFailure)
import System.IO (hClose, openTempFile)

assertEqual :: (Eq a, Show a) => a -> a -> IO ()
assertEqual expected actual =
    unless (expected == actual) $
        ioError (userError ("Expected " ++ show expected ++ ", got " ++ show actual))

assertTrue :: String -> Bool -> IO ()
assertTrue description condition = unless condition (ioError (userError description))

expectRight :: (Show e) => Either e a -> IO a
expectRight (Right value) = pure value
expectRight (Left problem) = ioError (userError (show problem))

expectLeft :: (Show a) => Either e a -> IO ()
expectLeft (Left _) = pure ()
expectLeft (Right value) = ioError (userError ("Unexpected success: " ++ show value))

runTests :: [(String, IO ())] -> IO ()
runTests tests = do
    passed <- mapM run tests
    unless (and passed) exitFailure
    putStrLn ("Passed " ++ show (length tests) ++ " tests")
  where
    run (name, action) = do
        outcome <- try action
        case outcome :: Either SomeException () of
            Right () -> putStrLn ("PASS " ++ name) >> pure True
            Left problem ->
                putStrLn ("FAIL " ++ name ++ ": " ++ displayException problem) >> pure False

withTempDirectory :: (FilePath -> IO a) -> IO a
withTempDirectory = bracket acquire removeDirectoryRecursive
  where
    acquire = do
        parent <- getTemporaryDirectory
        (name, handle) <- openTempFile parent "git-roam-test"
        hClose handle
        removeFile name
        createDirectory name
        canonicalizePath name
