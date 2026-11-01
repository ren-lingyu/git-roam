module GitRoam.Protocol.Objects (
    CommitObject (..),
    TreeEntry (..),
    TreeMode (..),
    ObjectProblem (..),
    HistorySource (..),
) where

import qualified Data.ByteString as BS
import GitRoam.ObjectId (ObjectId)

-- Untrusted, decoded native Git objects. Parent order and tree modes are exact.
data CommitObject = CommitObject
    { commitTree :: ObjectId
    , commitParents :: [ObjectId]
    }
    deriving (Eq, Show)

data TreeMode = Directory | RegularFile | ExecutableFile | SymbolicLink | Gitlink
    deriving (Eq, Show)

data TreeEntry = TreeEntry
    { entryName :: BS.ByteString
    , entryMode :: TreeMode
    , entryObject :: ObjectId
    }
    deriving (Eq, Show)

data ObjectProblem
    = MissingObject
    | WrongObjectType BS.ByteString
    | IncompleteHistory BS.ByteString
    | ObjectReadFailure BS.ByteString
    deriving (Eq, Show)

-- Providers must preserve stored parents (including shallow/replace boundaries).
-- Missing evidence is an error, never an empty parent list or an empty tree.
data HistorySource m = HistorySource
    { loadCommit :: ObjectId -> m (Either ObjectProblem CommitObject)
    , loadTree :: ObjectId -> m (Either ObjectProblem [TreeEntry])
    }
