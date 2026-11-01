{-# LANGUAGE TemplateHaskell #-}

module GitRoam.BuildInfo (packageVersion, defaultGitExecutable) where

import Data.Maybe (fromMaybe)
import Data.Version (showVersion)
import Language.Haskell.TH.Syntax (lift, runIO)
import qualified Paths_git_roam as Package
import System.Environment (lookupEnv)

packageVersion :: String
packageVersion = showVersion Package.version

defaultGitExecutable :: FilePath
defaultGitExecutable =
    $( do
        executable <- runIO (fromMaybe "git" <$> lookupEnv "GIT_ROAM_GIT")
        lift executable
     )
