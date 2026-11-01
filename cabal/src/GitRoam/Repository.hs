{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Repository (
    Repository (..),
    RepositoryError (..),
    inspectRepository,
) where

import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import qualified Data.ByteString as BS
import GitRoam.Git
import GitRoam.ObjectId
import System.Exit (ExitCode (..))

data Repository = Repository
    { repositoryWorktree :: Maybe BS.ByteString
    , repositoryGitDirectory :: BS.ByteString
    , repositoryCommonDirectory :: BS.ByteString
    , repositoryIsBare :: Bool
    , repositoryObjectFormat :: ObjectFormat
    }
    deriving (Eq, Show)

data RepositoryError
    = RepositoryTransportError [String] GitError
    | RepositoryGitError [String] GitResult
    | RepositoryMalformedOutput [String] BS.ByteString
    deriving (Eq, Show)

-- Query each path separately: a path can contain whitespace or embedded newlines.
inspectRepository ::
    (Monad m) =>
    Git m ->
    FilePath ->
    [(String, Maybe String)] ->
    m (Either RepositoryError Repository)
inspectRepository git directory environment = runExceptT $ do
    bare <- boolean ["rev-parse", "--is-bare-repository"]
    inside <- boolean ["rev-parse", "--is-inside-work-tree"]
    worktree <-
        if inside
            then Just <$> path ["rev-parse", "--path-format=absolute", "--show-toplevel"]
            else pure Nothing
    gitDir <- path ["rev-parse", "--path-format=absolute", "--git-dir"]
    commonDir <- path ["rev-parse", "--path-format=absolute", "--git-common-dir"]
    let formatArgs = ["rev-parse", "--show-object-format=storage"]
    formatBytes <- line formatArgs
    format <- case parseObjectFormat formatBytes of
        Right value -> pure value
        Left _ -> ExceptT (pure (Left (RepositoryMalformedOutput formatArgs formatBytes)))
    pure (Repository worktree gitDir commonDir bare format)
  where
    query arguments = ExceptT $ do
        result <- runGit git (GitInvocation directory arguments BS.empty environment)
        pure $ case result of
            Left problem -> Left (RepositoryTransportError arguments problem)
            Right value
                | gitExitCode value /= ExitSuccess -> Left (RepositoryGitError arguments value)
                | otherwise -> Right (gitStdout value)
    malformed arguments bytes = ExceptT (pure (Left (RepositoryMalformedOutput arguments bytes)))
    line arguments = do
        bytes <- query arguments
        case BS.unsnoc bytes of
            Just (value, 10) | not (BS.null value) -> pure value
            _ -> malformed arguments bytes
    boolean arguments = do
        bytes <- line arguments
        case bytes of
            "true" -> pure True
            "false" -> pure False
            _ -> malformed arguments bytes
    path arguments = do
        bytes <- line arguments
        if "/" `BS.isPrefixOf` bytes && not (BS.elem 0 bytes)
            then pure bytes
            else malformed arguments bytes
