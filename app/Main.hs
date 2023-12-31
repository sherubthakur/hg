module Main where

import Control.Monad (unless)
import Data.Char (isAlpha, isAlphaNum, isDigit)
import Data.Maybe (maybeToList)
import Data.Void (Void)
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import Text.Megaparsec
import Text.Megaparsec.Char

type Parser = Parsec Void String
type ParsingError = ParseErrorBundle String Void

reserved :: [Char]
reserved = ['\\', '[', ']', '^', '$', '+', '?', '.', '(', '|', ')']

gLit :: Parser (Parser Char)
gLit = do
    c <- escaped <|> noneOf reserved
    pure $ char c
  where
    escaped :: Parser Char
    escaped = char '\\' *> oneOf reserved

gDigit :: Parser (Parser Char)
gDigit = do
    _ <- string "\\d"
    pure $ satisfy isDigit

gAlphaNum :: Parser (Parser Char)
gAlphaNum = do
    _ <- string "\\w"
    pure $ satisfy isAlphaNum

gPositiveCharGroup :: Parser (Parser Char)
gPositiveCharGroup = do
    _ <- char '['
    chars <- many (satisfy isAlpha)
    _ <- char ']'
    pure $ satisfy (`elem` chars)

gNegCharGroup :: Parser (Parser Char)
gNegCharGroup = do
    _ <- char '['
    _ <- char '^'
    chars <- many (satisfy isAlpha)
    _ <- char ']'
    pure $ satisfy (`notElem` chars)

grep :: Parser (Parser String)
grep =
    choice
        [ gChoice
        , try (gModifiers gPositiveCharGroup)
        , gModifiers gNegCharGroup
        , try (gModifiers gDigit)
        , try (gModifiers gAlphaNum)
        , gModifiers gWildCard
        , gModifiers gLit
        ]

matchMany :: Parser (Parser String)
matchMany = mconcat <$> some grep

matchManyAnywhere :: Parser (Parser String)
matchManyAnywhere = skipManyTill anySingle <$> matchMany

grep' :: Parser (Parser String)
grep' = do
    maybeFromStart <- optional $ char '^'
    p <- case maybeFromStart of
        Nothing -> matchManyAnywhere
        Just _ -> matchMany
    maybeEnd <- optional $ char '$'
    case maybeEnd of
        Nothing -> pure p
        Just _ -> pure (p <* eof)

gOneOrMore :: Parser (Parser Char) -> Parser (Parser String)
gOneOrMore pp = do
    p <- pp
    maybePlus <- optional $ char '+'
    case maybePlus of
        Nothing -> pure ((: []) <$> p)
        Just _ -> pure $ some p

gModifiers :: Parser (Parser Char) -> Parser (Parser String)
gModifiers pp = gOneOrNone pp <|> gOneOrMore pp

gOneOrNone :: Parser (Parser Char) -> Parser (Parser String)
gOneOrNone pp = do
    p <- pp
    maybeOptional <- optional $ char '?'
    case maybeOptional of
        Nothing -> pure ((: []) <$> p)
        Just _ -> pure $ maybeToList <$> optional p

gWildCard :: Parser (Parser Char)
gWildCard = do
    _ <- char '.'
    pure $ noneOf reserved

gChoice :: Parser (Parser String)
gChoice = do
    _ <- char '('
    p1 <- mconcat <$> some grep
    _ <- char '|'
    p2 <- mconcat <$> some grep
    _ <- char ')'
    pure $ p1 <|> p2

matchPattern :: String -> String -> Either ParsingError String
matchPattern pattern input = do
    patternParser <- parse grep' "" pattern
    parse patternParser "" input

main :: IO ()
main = do
    args <- getArgs
    let pattern = args !! 1
    input_line <- getLine

    unless (head args == "-E") $ do
        putStrLn "Expected first argument to be '-E'"
        exitFailure
    case matchPattern pattern input_line of
        Right result -> do
            print result
            exitSuccess
        Left err -> do
            print err
            exitFailure

