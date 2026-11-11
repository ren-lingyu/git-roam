{-# LANGUAGE OverloadedStrings #-}

-- Diagnostics are independent of presentation and application modules.
module GitRoam.Diagnostic (Diagnostic (..), Severity (..), Evidence (..), emptyEvidence) where

import qualified Data.ByteString as BS
import Data.Text (Text)
import GitRoam.Git.Worktrees (Worktree)
import GitRoam.ObjectId (ObjectId)
import GitRoam.Protocol.Identity (NodeId)

data Severity = Error | Warning deriving (Eq, Show)
data Diagnostic = Diagnostic {diagnosticCode :: Text, diagnosticSeverity :: Severity, diagnosticMessage :: Text} deriving (Eq, Show)

-- Nothing means unobserved, not false. Confirmation describes the operation,
-- not the post-compensation state of the repository.
data Evidence = Evidence
    { evidenceNode :: Maybe NodeId
    , evidenceCandidate :: Maybe ObjectId
    , evidenceRefConfirmed :: Maybe Bool
    , evidenceAttempted :: Maybe Bool
    , evidenceRemoved :: [(NodeId, BS.ByteString)]
    , evidenceRemainingWorktrees :: Maybe [Worktree]
    , evidenceActualRefs :: Maybe [(NodeId, ObjectId)]
    , evidenceRemainingConfig :: Maybe [BS.ByteString]
    }
    deriving (Eq, Show)

emptyEvidence :: Evidence
emptyEvidence = Evidence Nothing Nothing Nothing Nothing [] Nothing Nothing Nothing
