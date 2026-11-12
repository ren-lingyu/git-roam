{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Git.Status (WorkingTreeStatus (..), workingTreeDirty, decodeWorkingTreeStatus, readWorkingTreeStatus) where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath)
import System.Directory (canonicalizePath)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import qualified System.Posix.Files as Files

data WorkingTreeStatus = WorkingTreeStatus
    { workingStaged :: Bool
    , workingUnstaged :: Bool
    , workingUntracked :: Bool
    , workingUnmerged :: Bool
    }
    deriving (Eq, Show)

workingTreeDirty :: WorkingTreeStatus -> Bool
workingTreeDirty value = or [workingStaged value, workingUnstaged value, workingUntracked value, workingUnmerged value]

decodeWorkingTreeStatus :: ObjectFormat -> BS.ByteString -> Either String WorkingTreeStatus
decodeWorkingTreeStatus format bytes = do
    records <-
        if BS.null bytes
            then Right []
            else case BS.stripSuffix "\0" bytes of
                Just body | not (BS.null body) -> Right (BS.split 0 body)
                Just _ -> Left "Empty status record"
                Nothing -> Left "Status output lacks final NUL"
    go (WorkingTreeStatus False False False False) records
  where
    go summary [] = Right summary
    go summary (record : rest)
        | "# " `BS.isPrefixOf` record = go summary rest
        | Just path <- BS.stripPrefix "? " record = pathValue path >> go summary{workingUntracked = True} rest
        | Just path <- BS.stripPrefix "! " record = pathValue path >> go summary rest
        | "1 " `BS.isPrefixOf` record = do
            (fields, path) <- columns 8 record
            pathValue path
            case fields of
                ["1", xy, sub, mh, mi, mw, hh, hi] -> do
                    mapM_ mode [mh, mi, mw]
                    mapM_ object [hh, hi]
                    value <- tracked xy sub
                    go (combine summary value) rest
                _ -> Left "Invalid ordinary status entry"
        | "2 " `BS.isPrefixOf` record = do
            (fields, path) <- columns 9 record
            pathValue path
            (original, remaining) <- case rest of original : remaining -> Right (original, remaining); [] -> Left "Rename/copy status lacks original path"
            pathValue original
            case fields of
                ["2", xy, sub, mh, mi, mw, hh, hi, score] -> do
                    mapM_ mode [mh, mi, mw]
                    mapM_ object [hh, hi]
                    case BS.uncons score of
                        Just (kind, digits) | kind `elem` [82, 67], BS.elem kind xy, not (BS.null digits), BS.all decimal digits, Just (n, "") <- BSC.readInteger digits, n <= 100 -> Right ()
                        _ -> Left "Invalid rename/copy score"
                    value <- tracked xy sub
                    go (combine summary value) remaining
                _ -> Left "Invalid rename/copy status entry"
        | "u " `BS.isPrefixOf` record = do
            (fields, path) <- columns 10 record
            pathValue path
            case fields of
                ["u", xy, sub, m1, m2, m3, mw, h1, h2, h3] | xy `elem` ["DD", "AU", "UD", "UA", "DU", "AA", "UU"] -> do
                    mapM_ mode [m1, m2, m3, mw]
                    mapM_ object [h1, h2, h3]
                    value <- submodule sub
                    -- Unmerged XY describes conflict sides, not staged/unstaged.
                    go (combine summary value{workingUnmerged = True}) rest
                _ -> Left "Invalid unmerged status entry"
        | otherwise = Left "Unknown or empty status record"
    columns :: Int -> BS.ByteString -> Either String ([BS.ByteString], BS.ByteString)
    columns 0 value = Right ([], value)
    columns n value = case BSC.break (== ' ') value of
        (field, after)
            | not (BS.null field)
            , not (BS.null after) -> do
                (fields, path) <- columns (n - 1) (BS.drop 1 after)
                Right (field : fields, path)
        _ -> Left "Truncated status entry fields"
    pathValue path = if BS.null path then Left "Empty status pathname" else Right ()
    mode value = if value `elem` ["000000", "040000", "100644", "100755", "120000", "160000"] then Right () else Left "Invalid status file mode"
    object value
        | BS.length value == objectIdLength format && BS.all (== 48) value = Right ()
        | otherwise = () <$ parseObjectId format value
    decimal byte = byte >= 48 && byte <= 57
    tracked xy sub = do
        if BS.length xy == 2 && BS.all (`BS.elem` ".MTADRC") xy then Right () else Left "Invalid status XY"
        value <- submodule sub
        let result = combine value (WorkingTreeStatus (BS.take 1 xy /= ".") (BS.drop 1 xy /= ".") False False)
        if workingTreeDirty result then Right result else Left "Tracked status entry has no change"
    submodule "N..." = Right (WorkingTreeStatus False False False False)
    submodule value = case BS.unpack value of
        [83, c, m, u] | c `elem` [46, 67], m `elem` [46, 77], u `elem` [46, 85] -> Right (WorkingTreeStatus False (c /= 46 || m /= 46 || u /= 46) (u /= 46) False)
        _ -> Left "Invalid submodule status"
    combine a b = WorkingTreeStatus (workingStaged a || workingStaged b) (workingUnstaged a || workingUnstaged b) (workingUntracked a || workingUntracked b) (workingUnmerged a || workingUnmerged b)

-- These observations never substitute for removal safety. No ignored-file or
-- ongoing-operation checks are claimed, and Git keeps its own file-state rules.
readWorkingTreeStatus :: Git IO -> Repository -> Worktree -> IO (Either String WorkingTreeStatus)
readWorkingTreeStatus git expected record = do
    outcome <- try (runExceptT observe) :: IO (Either IOException (Either String WorkingTreeStatus))
    pure (either (Left . show) id outcome)
  where
    environment = readOnlyEnvironment ++ [(key, Nothing) | key <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_SHALLOW_FILE", "GIT_NAMESPACE", "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM", "GIT_IMPLICIT_WORK_TREE"]]
    command path bindings args = ExceptT $ do
        outcome <- runGit git (GitInvocation path args BS.empty (environment ++ bindings))
        pure $ case outcome of
            Left problem -> Left (show problem)
            Right value | gitExitCode value == ExitSuccess && BS.null (gitStderr value) -> Right (gitStdout value)
            Right value -> Left (show args ++ ": " ++ show (gitExitCode value, gitStderr value))
    line path bindings args = do
        bytes <- command path bindings args
        maybe (throwE "Missing identity output terminator") pure (BS.stripSuffix "\n" bytes)
    canonical bytes = lift (decodePath bytes >>= canonicalizePath)
    identity path = do
        rootInfo <- lift (Files.getSymbolicLinkStatus path)
        dotInfo <- lift (Files.getSymbolicLinkStatus (path </> ".git"))
        let metadataType = Files.isRegularFile dotInfo || (treeMain record && Files.isDirectory dotInfo)
        unless (Files.isDirectory rootInfo && not (Files.isSymbolicLink rootInfo) && metadataType) (throwE "Unsupported worktree directory or .git type")
        discovered <- lift (inspectRepository git path environment)
        actual <- either (throwE . show) pure discovered
        top <- maybe (throwE "Registered path is not inside a worktree") canonical (repositoryWorktree actual)
        root <- lift (canonicalizePath path)
        common <- canonical (repositoryCommonDirectory actual)
        expectedCommon <- canonical (repositoryCommonDirectory expected)
        admin <- canonical (repositoryGitDirectory actual)
        unless (not (repositoryIsBare actual) && top == root && common == expectedCommon && repositoryObjectFormat actual == repositoryObjectFormat expected) (throwE "Worktree repository identity differs from registration")
        if treeMain record
            then unless (admin == common) (throwE "Main worktree administration changed")
            else do
                unless (Files.isRegularFile dotInfo && takeDirectory admin == common </> "worktrees") (throwE "Linked worktree administration is not registered in this repository")
                backlink <- lift (BS.readFile (admin </> "gitdir"))
                raw <- maybe (throwE "Invalid worktree administration backlink") pure (BS.stripSuffix "\n" backlink)
                linked <- canonical raw
                own <- lift (canonicalizePath (path </> ".git"))
                unless (linked == own) (throwE "Worktree administration points to another path")
        -- process marshals environment and cwd with the filesystem encoding,
        -- unlike argv's CString encoding. Keep undecodable bytes lossless and
        -- override only these verified anchors after clearing inherited routing.
        let pinned = [("GIT_DIR", Just admin), ("GIT_WORK_TREE", Just root)]
        branch <- line path pinned ["symbolic-ref", "-q", "--no-recurse", "HEAD"]
        headBytes <- line path pinned ["rev-parse", "--verify", "--end-of-options", "HEAD"]
        headOid <- either throwE pure (parseObjectId (repositoryObjectFormat expected) headBytes)
        unless (treeBranch record == Just branch && treeHead record == Just headOid && not (treeBare record || treeDetached record)) (throwE "Worktree branch/HEAD differs from registration")
        pure (admin, root, (Files.deviceID rootInfo, Files.fileID rootInfo, Files.deviceID dotInfo, Files.fileID dotInfo))
    observe = do
        path <- lift (decodePath (treePath record))
        before@(admin, root, _) <- identity path
        bytes <- command path [("GIT_DIR", Just admin), ("GIT_WORK_TREE", Just root)] ["--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false", "status", "--porcelain=v2", "-z", "--untracked-files=normal", "--no-ahead-behind", "--ignore-submodules=none"]
        result <- either throwE pure (decodeWorkingTreeStatus (repositoryObjectFormat expected) bytes)
        after <- identity path
        unless (before == after) (throwE "Worktree identity changed during status query")
        pure result
