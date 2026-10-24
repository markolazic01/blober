import Lake
open Lake DSL

require mathlib from git "https://github.com/leanprover-community/mathlib4.git" @ "v4.31.0"

package «batch-kzg» where

@[default_target]
lean_lib BatchKzg where
