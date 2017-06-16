module Lib where

import Control.Applicative
import Data.Char (toLower)
import qualified Data.Set as S
import qualified Data.MultiSet as MS
import Text.Trifecta
import Text.Parser.Expression
import Text.Parser.Token.Style

type EOM = [Equation]
data Equation = Equation { lhs :: Exp
                         , rhs :: Exp
                         } deriving Show
data Exp = Num Double
         | Term { name :: String
                , dependOn :: Arg
                , differentiatedBy :: Coords
                }
         | Add Exp Exp
         | Mul Exp Exp
         | Sub Exp Exp
         | Div Exp Exp
         deriving (Show, Eq)

type Arg = S.Set Coord
type Coords = MS.MultiSet Coord
data Coord = T | X | Y | Z deriving (Eq, Ord)

instance Show Coord where
    show T = "t"
    show X = "x"
    show Y = "y"
    show Z = "z"

parseEOM :: Parser EOM
parseEOM = many parseEquation

parseEquation :: Parser Equation
parseEquation = do
    spaces
    l <- parseExp
    spaces
    char '='
    spaces
    r <- parseExp
    spaces
    return $ Equation l r

parseExp :: Parser Exp
parseExp = parens expr
       <|> parseTerm
       <|> parseNum

expr :: Parser Exp
expr = buildExpressionParser table parseExp
    where
        table = [[binary "*" Mul AssocLeft, binary "/" Div AssocLeft]
                ,[binary "+" Add AssocLeft, binary "-" Sub AssocLeft]
                ]
        binary op f = Infix (f <$ reserve emptyOps op)

parseNum :: Parser Exp
parseNum = Num . either fromIntegral id <$> integerOrDouble

parseTerm :: Parser Exp
parseTerm = do
    n <- some letter
    as <- option S.empty $ brackets args
    ds <- option MS.empty $ MS.fromList <$> (char '_' *> some coord)
    return $ Term n as ds

args :: Parser Arg
args = S.fromList <$> some (coord <* optional comma)

coord :: Parser Coord
coord = (char 't' *> pure T)
    <|> (char 'x' *> pure X)
    <|> (char 'y' *> pure Y)
    <|> (char 'z' *> pure Z)

parseEOMFromFile :: String -> IO (Maybe EOM)
parseEOMFromFile = parseFromFile parseEOM

formatEOM :: EOM -> String
formatEOM = unlines . map formatEquation

formatEquation :: Equation -> String
formatEquation (Equation l r) = unwords [formatExp l, "=", formatExp r]

formatExp :: Exp -> String
formatExp (Num x) = show x
formatExp (Term n a ds) = n ++ formatArg a ++ formatDiff ds
formatExp (Mul e1 e2) = "(" ++ formatExp e1 ++ " * " ++ formatExp e2 ++")"
formatExp (Div e1 e2) = "(" ++ formatExp e1 ++ " / " ++ formatExp e2 ++")"
formatExp (Add e1 e2) = "(" ++ formatExp e1 ++ " + " ++ formatExp e2 ++")"
formatExp (Sub e1 e2) = "(" ++ formatExp e1 ++ " - " ++ formatExp e2 ++")"

formatArg :: Arg -> String
formatArg as | S.null as = ""
             | otherwise = show $ S.toList as

formatDiff :: Coords -> String
formatDiff cs | MS.null cs = ""
              | otherwise = "_" ++ concatMap show (MS.toAscList cs)

differentiatedByT :: EOM -> EOM
differentiatedByT eom = map (\(Equation l r) -> Equation (d T l) (replace $ d T r)) eom
    where
        replace (Add e1 e2) = Add (replace e1) (replace e2)
        replace (Sub e1 e2) = Sub (replace e1) (replace e2)
        replace (Mul e1 e2) = Mul (replace e1) (replace e2)
        replace (Div e1 e2) = Add (replace e1) (replace e2)
        -- Assume the number of ds is 2 at most
        replace e@(Term n a ds)
            | d0 == ds = find e eom
            | T `MS.member` ds = let ds' = head $ MS.toList (ds MS.\\ d0)
                                 in  d ds' $ find (Term n a d0) eom
            | otherwise = e
            where d0 = MS.singleton T
        replace e = e

find :: Exp -> EOM -> Exp
find e = rhs . head . filter (\eq -> lhs eq == e)

d :: Coord -> Exp -> Exp
d i (Num _) = Num 0.0
d i (Term n a d) | i `S.member` a = Term n a (MS.insert i d)
                 | otherwise = Term n a d
d i (Mul e1 e2) = Add (Mul (d i e1) e2) (Mul e1 (d i e2))
d i (Div e1 e2) = Sub (Div (d i e1) e2) (Mul (Div e1 (Mul e2 e2)) (d i e2))
d i (Add e1 e2) = Add (d i e1) (d i e2)
d i (Sub e1 e2) = Sub (d i e1) (d i e2)

-- This is not enough
simplify :: Exp -> Exp
simplify (Mul (Num 0) _) = Num 0
simplify (Mul _ (Num 0)) = Num 0
simplify (Mul (Num 1) e) = simplify e
simplify (Mul e (Num 1)) = simplify e
simplify (Mul e1 e2) = Mul (simplify e1) (simplify e2)
simplify (Div (Num 0) _) = Num 0
simplify (Div e (Num 1)) = simplify e
simplify (Div e1 e2) = Div (simplify e1) (simplify e2)
simplify (Add (Num 0) e) = simplify e
simplify (Add e (Num 0)) = simplify e
simplify (Add e1 e2) = Add (simplify e1) (simplify e2)
simplify (Sub (Num 0) e) = Mul (Num (-1)) (simplify e)
simplify (Sub e (Num 0)) = simplify e
simplify (Sub e1 e2) = Sub (simplify e1) (simplify e2)
simplify e = e
