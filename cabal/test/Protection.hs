{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_, unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import GitRoam.Application.Protection (evaluateTransaction)
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import System.Directory (createDirectory, removeDirectory)
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture (fixture, nodeA, nodeB, ok, root)

ref :: NodeId -> String
ref node = "refs/heads/" ++ BSC.unpack (nodeIdBytes node)

textOid :: ObjectId -> BS.ByteString
textOid = objectIdBytes

tip :: Git IO -> FilePath -> ObjectFormat -> NodeId -> IO ObjectId
tip git directory format node = do
    bytes <- BSC.init <$> ok git directory ["rev-parse", ref node] ""
    expectRight (parseObjectId format bytes)

treeOf :: Git IO -> FilePath -> ObjectId -> IO BS.ByteString
treeOf git directory oid =
    BSC.init <$> ok git directory ["rev-parse", BSC.unpack (textOid oid) ++ "^{tree}"] ""

commit :: Git IO -> FilePath -> ObjectFormat -> BS.ByteString -> [ObjectId] -> String -> IO ObjectId
commit git directory format tree parents message = do
    bytes <- BSC.init <$> ok git directory (["commit-tree", BSC.unpack tree] ++ concatMap (\oid -> ["-p", BSC.unpack (textOid oid)]) parents ++ ["-m", message]) ""
    expectRight (parseObjectId format bytes)

setRef :: Git IO -> FilePath -> NodeId -> ObjectId -> IO ()
setRef git directory node oid = do
    _ <- ok git directory ["update-ref", ref node, BSC.unpack (textOid oid)] ""
    pure ()

update :: NodeId -> BS.ByteString -> BS.ByteString -> BS.ByteString
update node old new = old <> " " <> new <> " " <> BSC.pack (ref node) <> "\n"

accept :: FilePath -> BS.ByteString -> IO ()
accept directory input = evaluateTransaction directory "prepared" input >>= expectRight

reject :: FilePath -> BS.ByteString -> IO ()
reject directory input = evaluateTransaction directory "prepared" input >>= expectLeft

main :: IO ()
main =
    runTests $
        [ ("unrelated reference events and non-prepared phases", fixture "files" Sha1 phases)
        , ("rejects malformed, duplicate and unmanaged updates", fixture "files" Sha1 invalidInput)
        , ("rejects external Root conflicts during single-Node Checkpoint updates", fixture "files" Sha1 crossRoot)
        , ("operation lock blocks concurrent reference checks", fixture "files" Sha1 locking)
        ]
            ++ [ ("prepared ref validation " ++ backend ++ " " ++ show format, fixture backend format (matrix format))
               | backend <- ["files", "reftable"]
               , format <- [Sha1, Sha256]
               ]

-- Non-prepared phases never veto a transaction. Ignore non-Node refs, but
-- reject malformed input even if it does not name a Node ref.
phases :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
phases git _ directory _ = do
    root git directory nodeA
    forM_ ["preparing", "committed", "aborted"] $ \phase ->
        evaluateTransaction directory phase "not a transaction row" >>= expectRight
    accept directory ""
    accept directory "zero new HEAD\n"
    accept directory "zero new refs/tags/version\n"
    reject directory "malformed\n"

invalidInput :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalidInput git _ directory _ = do
    root git directory nodeA
    a <- tip git directory Sha1 nodeA
    tree <- treeOf git directory a
    next <- commit git directory Sha1 tree [a] "Content"
    let old = textOid a
        new = textOid next
        pair = update nodeA old new
        zeros = BS.replicate (objectIdLength Sha1) 48
    reject directory (pair <> pair)
    reject directory (update nodeA old zeros)
    reject directory (update nodeB zeros new)
    reject directory (update nodeA old "invalid")
    -- A different Node's Root cannot become the new value of A's branch.
    root git directory nodeB
    b <- tip git directory Sha1 nodeB
    reject directory (update nodeA old (textOid b))
    tip git directory Sha1 nodeA >>= assertEqual a

-- If a new Checkpoint were validated in isolation, a context referencing a
-- competing B Root could evade the local branch's B identity. The validator
-- must fall back to full-repository validation for this type of update.
crossRoot :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
crossRoot git _ directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    aTree <- treeOf git directory a
    bTree <- treeOf git directory b
    otherB <- commit git directory Sha1 bTree [] "Competing B Root"
    unless (otherB /= b) (fail "Distinct Root commits must have distinct OIDs")
    bad <- commit git directory Sha1 aTree [a, otherB] "Context points at the wrong B Root"
    reject directory (update nodeA (textOid a) (textOid bad))
    -- The same context is valid when B has no managed branch, since the
    -- historical version need not remain in a current Node branch.
    _ <- ok git directory ["update-ref", "-d", ref nodeB] ""
    accept directory (update nodeA (textOid a) (textOid bad))

locking :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
locking git _ directory _ = do
    root git directory nodeA
    a <- tip git directory Sha1 nodeA
    let lock = directory </> ".git" </> "git-roam.operation.lock"
    createDirectory lock
    reject directory (update nodeA (textOid a) (textOid a))
    removeDirectory lock
    accept directory (update nodeA (textOid a) (textOid a))

matrix :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
matrix format git _ directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- tip git directory format nodeA
    b <- tip git directory format nodeB
    aTree <- treeOf git directory a
    bTree <- treeOf git directory b
    bContent <- commit git directory format bTree [b] "B Content"
    -- Single-Node Content extensions and amendments do not introduce
    -- additional context and are safe to validate as a local history.
    aContent <- commit git directory format aTree [a] "A Content"
    accept directory (update nodeA (textOid a) (textOid aContent))
    setRef git directory nodeA aContent
    amended <- commit git directory format aTree [a] "A amended Content"
    accept directory (update nodeA (textOid aContent) (textOid amended))
    setRef git directory nodeA amended

    -- A new Checkpoint can reference a B Content which is not a branch tip.
    k <- commit git directory format aTree [amended, bContent] "A records B's historical Content"
    accept directory (update nodeA (textOid amended) (textOid k))
    setRef git directory nodeA k

    -- Native Git rewrites are valid even when they discard this Checkpoint.
    accept directory (update nodeA (textOid k) (textOid a))
    -- A different Root is always forbidden, despite a valid UUID tree.
    anotherRoot <- commit git directory format aTree [] "Different A Root"
    reject directory (update nodeA (textOid k) (textOid anotherRoot))
    -- Invalid Content trees, including another Node identity, are rejected.
    wrong <- commit git directory format bTree [k] "Wrong identity for A"
    reject directory (update nodeA (textOid k) (textOid wrong))

    -- Update A and B together: full old/new managed states are validated.
    accept directory (update nodeA (textOid k) (textOid amended) <> update nodeB (textOid b) (textOid bContent))
    -- The old OID supplied by native Git is not the authority for observing
    -- local managed refs, and may be zero in some transaction variants.
    let zeros = BS.replicate (objectIdLength format) 48
    accept directory (update nodeA zeros (textOid k))
    -- Native ref deletion and creation still require controlled operations.
    reject directory (update nodeB (textOid b) zeros)
