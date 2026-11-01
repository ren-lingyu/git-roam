{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Git.Worktrees (Worktree (..), decodeWorktrees, listWorktrees, worktreeNode) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Set as Set
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import System.Exit (ExitCode (..))

data Worktree = Worktree
    { treePath :: BS.ByteString
    , treeHead :: Maybe ObjectId
    , treeBranch :: Maybe BS.ByteString
    , treeMain :: Bool
    , treeBare :: Bool
    , treeDetached :: Bool
    , treeLocked :: Maybe BS.ByteString
    , treePrunable :: Maybe BS.ByteString
    }
    deriving (Eq, Show)

worktreeNode :: Worktree -> Maybe NodeId
worktreeNode record = treeBranch record >>= BS.stripPrefix "refs/heads/" >>= either (const Nothing) Just . parseNodeId

decodeWorktrees :: ObjectFormat -> BS.ByteString -> Either String [Worktree]
decodeWorktrees format bytes = do
    unlessE (BS.null bytes || "\0\0" `BS.isSuffixOf` bytes) "Worktree output lacks its NUL record terminator"
    records <- mapM parse (zip [0 :: Int ..] (splitRecords (BS.split 0 bytes)))
    unlessE (length records == Set.size (Set.fromList (map treePath records))) "Duplicate worktree paths"
    pure records
  where
    splitRecords [] = []
    splitRecords ("" : rest) = splitRecords rest
    splitRecords fields = let (record, rest) = break BS.null fields in record : splitRecords rest
    parse (position, first : fields) | Just path <- BS.stripPrefix "worktree " first = do
        unlessE ("/" `BS.isPrefixOf` path) "Worktree path is not absolute"
        let values prefix = [value | field <- fields, Just value <- [BS.stripPrefix prefix field]]
            heads = values "HEAD "
            branches = values "branch "
            locked = [maybe "" id (BS.stripPrefix "locked " f) | f <- fields, f == "locked" || "locked " `BS.isPrefixOf` f]
            prunable = [maybe "" id (BS.stripPrefix "prunable " f) | f <- fields, f == "prunable" || "prunable " `BS.isPrefixOf` f]
            bare = "bare" `elem` fields
            detached = "detached" `elem` fields
        unlessE (all ((<= 1) . length) [heads, branches, locked, prunable]) "Duplicate worktree fields"
        unlessE (length (filter (== "bare") fields) <= 1 && length (filter (== "detached") fields) <= 1) "Duplicate worktree flags"
        unlessE (all (\f -> f `elem` ["bare", "detached", "locked", "prunable"] || any (`BS.isPrefixOf` f) ["HEAD ", "branch ", "locked ", "prunable "]) fields) "Unknown worktree field"
        unlessE (not (bare && (detached || not (null branches))) && not (detached && not (null branches))) "Contradictory worktree fields"
        unlessE (bare || detached || length branches == 1) "Worktree has no branch or detached state"
        headOid <- case heads of
            [oid] | BS.length oid == objectIdLength format && BS.all (== 48) oid -> pure Nothing
            [oid] -> Just <$> parseObjectId format oid
            [] | bare -> pure Nothing
            _ -> Left "Worktree has no HEAD"
        pure (Worktree path headOid (single branches) (position == 0) bare detached (single locked) (single prunable))
    parse _ = Left "Invalid worktree record"
    single [value] = Just value
    single _ = Nothing
    unlessE condition message = if condition then Right () else Left message

listWorktrees :: Git IO -> FilePath -> ObjectFormat -> IO (Either String [Worktree])
listWorktrees git directory format = do
    let environment = readOnlyEnvironment ++ [(key, Nothing) | key <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"]]
    outcome <- runGit git (GitInvocation directory ["worktree", "list", "--porcelain", "-z"] BS.empty environment)
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right result | gitExitCode result == ExitSuccess -> decodeWorktrees format (gitStdout result)
        Right result -> Left (BSC.unpack (gitStderr result))
