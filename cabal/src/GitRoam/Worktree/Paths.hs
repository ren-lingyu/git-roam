{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Worktree.Paths (shortName, encodePath, decodePath, safeAbsolutePath, within, checkPathCollisions) where

import Control.Exception (IOException, try)
import qualified Crypto.Hash.SHA256 as SHA256
import Data.Bits (shiftR, (.&.))
import qualified Data.ByteString as BS
import Data.List (groupBy, sortOn)
import qualified GHC.Foreign as Foreign
import GHC.IO.Encoding (getFileSystemEncoding)
import GitRoam.Protocol.Identity
import System.Directory (doesDirectoryExist, getCurrentDirectory, pathIsSymbolicLink)
import System.FilePath
import System.IO.Error (isDoesNotExistError)

shortName :: NodeId -> FilePath
shortName node = [alphabet !! fromIntegral ((value `shiftR` bits) .&. 31) | bits <- [35, 30 .. 0]]
  where
    value = BS.foldl' (\acc byte -> acc * 256 + fromIntegral byte) (0 :: Integer) (BS.take 5 (SHA256.hash (nodeIdBytes node)))
    alphabet = "abcdefghijklmnopqrstuvwxyz234567"

-- Use the filesystem encoding so POSIX undecodable bytes round-trip, including
-- filenames that cannot be represented as ordinary UTF-8 text.
encodePath :: FilePath -> IO BS.ByteString
encodePath path = do
    encoding <- getFileSystemEncoding
    Foreign.withCStringLen encoding path BS.packCStringLen

decodePath :: BS.ByteString -> IO FilePath
decodePath bytes = do
    encoding <- getFileSystemEncoding
    BS.useAsCStringLen bytes (Foreign.peekCStringLen encoding)

within :: FilePath -> FilePath -> Bool
within parent child =
    let relative = makeRelative parent child
     in relative == "." || (not (isAbsolute relative) && all (/= "..") (splitDirectories relative))

checkPathCollisions :: [(NodeId, FilePath)] -> Either String ()
checkPathCollisions pairs = case filter ((> 1) . length) (groupBy (\a b -> snd a == snd b) (sortOn snd pairs)) of
    [] -> Right ()
    conflicts -> Left ("Deployment path collision: " ++ show conflicts)

-- Inspect original components before processing '..'; normalizing a symlink/..
-- first would silently select a different filesystem location.
safeAbsolutePath :: FilePath -> IO (Either String FilePath)
safeAbsolutePath input
    | null input || '\0' `elem` input = pure (Left "Empty path or NUL byte")
    | otherwise = do
        path <- if isAbsolute input then pure input else (</> input) <$> getCurrentDirectory
        walk "/" (filter (`notElem` ["/", ""]) (splitDirectories path))
  where
    walk current [] = pure (Right (dropTrailingPathSeparator current))
    walk current (part : rest)
        | part == "." = walk current rest
        | part == ".." = walk (takeDirectory current) rest
        | otherwise = do
            let next = current </> part
            symbolic <- try (pathIsSymbolicLink next) :: IO (Either IOException Bool)
            case symbolic of
                Right True -> pure (Left ("Symbolic link in deployment path: " ++ show next))
                Left problem | not (isDoesNotExistError problem) -> pure (Left (show problem))
                _ -> do
                    directory <- doesDirectoryExist next
                    if not directory && not (null rest)
                        then case symbolic of
                            Left _ -> walk next rest -- missing ancestors are checked again before creation
                            _ -> pure (Left ("Non-directory path component: " ++ show next))
                        else walk next rest
