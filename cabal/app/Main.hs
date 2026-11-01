module Main (main) where

import qualified Data.ByteString as BS
import qualified Data.Text.Encoding as Text
import GitRoam.Cli
import System.Environment (getArgs)
import System.Exit (exitWith)
import System.IO (stderr, stdout)

main :: IO ()
main = do
    response <- runCli <$> getArgs
    BS.hPut stdout (Text.encodeUtf8 (responseStdout response))
    BS.hPut stderr (Text.encodeUtf8 (responseStderr response))
    exitWith (responseExitCode response)
