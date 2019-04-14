{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

module Nixfmt.Lexer
    ( file
    , lexeme
    , symbol
    ) where

import           Data.Char
import           Data.Text            as Text hiding (filter, length, map, span)
import           Nixfmt.Types
import           Nixfmt.Util
import           Text.Megaparsec
import           Text.Megaparsec.Char

data ParseTrivium = PTNewlines     Int
                  | PTLineComment  Text
                  | PTBlockComment [Text]
                  deriving (Show)

preLexeme :: Parser a -> Parser a
preLexeme p = p <* manyP (\x -> isSpace x && x /= '\n' && x /= '\r')

newlines :: Parser ParseTrivium
newlines = PTNewlines <$> length <$> some (preLexeme eol)

splitLines :: Text -> [Text]
splitLines = Text.lines . replace "\r\n" "\n"

lineComment :: Parser ParseTrivium
lineComment = preLexeme $ chunk "#" *>
    (PTLineComment <$> manyP (\x -> x /= '\n' && x /= '\r'))

blockComment :: Parser ParseTrivium
blockComment = try $ preLexeme $ chunk "/*" *>
    (PTBlockComment . splitLines . pack <$> manyTill anySingle (chunk "*/"))

convertTrailing :: [ParseTrivium] -> Maybe Text
convertTrailing = (\case
        "" -> Nothing
        tc -> Just $ cons ' ' tc
    ) . intercalate " " . filter (/="") . map (\case
        (PTLineComment lc) -> strip lc
        (PTBlockComment [bc]) -> strip bc
        _ -> "")

convertLeading :: [ParseTrivium] -> Trivia
convertLeading = Prelude.concat . map (\case
    (PTNewlines 1) -> []
    (PTNewlines _) -> [EmptyLine]
    (PTLineComment lc) -> [LineComment lc]
    (PTBlockComment bc) -> [BlockComment $ dropCommonIndentation bc])

isTrailing :: ParseTrivium -> Bool
isTrailing (PTLineComment _)    = True
isTrailing (PTBlockComment [_]) = True
isTrailing _                    = False

convertTrivia :: [ParseTrivium] -> (Maybe Text, Trivia)
convertTrivia pts = let (trailing, leading) = span isTrailing pts
                    in (convertTrailing trailing, convertLeading leading)

trivia :: Parser [ParseTrivium]
trivia = many $ hidden $ lineComment <|> blockComment <|> newlines

lexeme :: Parser NixToken -> Parser [NixAST]
lexeme p = do
    token <- preLexeme p
    (trailing, leading) <- convertTrivia <$> trivia
    return $ case leading of
                  [] -> [Leaf token trailing]
                  _  -> [Leaf token trailing, Trivia leading]

symbol :: NixToken -> Parser [NixAST]
symbol t = lexeme (chunk (pack $ show t) *> return t)

file :: Parser [NixAST] -> Parser NixAST
file p = do
    leading <- convertLeading <$> trivia
    body <- p
    eof
    return (Node File (Trivia leading : body))